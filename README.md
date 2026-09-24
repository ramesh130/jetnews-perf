# jetnews-perf

Performance captures of JetNews, Google's Compose sample app, with five known regressions ("plants")
and clean runs to compare them against. Each capture is a Perfetto trace from the API 36 emulator plus
a `run.json` that says what was built and measured.

| Path | What |
|---|---|
| `JetNews/` | The app: a modified copy of `android/compose-samples` at `0bbd72d`, Apache-2.0 ([`NOTICE.md`](NOTICE.md)). |
| `harness/` | `harness/lab run <scenario> [--plant <name>]`: build, install, drive, trace. Adapted from superPlayer's `devicelab/`. |
| `plants/` | Five patches against `JetNews/`, each a known regression, and [`plants/README.md`](plants/README.md), which says how each was sized. |
| `runs/<run_id>/` | One capture: `run.json`, `trace.perfetto-trace.gz`, the Perfetto config, screenshots before and after the measured part, the scenario's own records, and `plant.patch` for a planted run. |

**A planted run names its plant.** `run.json`, `plant.patch`, `plants/` and this repository's commit
messages say what was planted. They are the operator's record. Anything that must find a regression
from the trace alone gets the trace, and nothing from here that names the plant.

## Running a capture

```bash
emulator -avd superplayer_verify_36 -no-snapshot-load -no-boot-anim -no-window -no-audio -gpu swiftshader_indirect &
harness/lab run startup                                   # 20 cold starts, one trace
harness/lab run scroll --plant feed-card-grain            # the home feed scrolled, built with a plant
```

Needs JDK 17 (`/usr/libexec/java_home -v 17`, or `LAB_JAVA_HOME`), the Android SDK's `adb` on `PATH`,
and the AVD `superplayer_verify_36` (API 36, 1080x2400, userdebug, so `su` works). The build is
`./gradlew assembleDebug --max-workers=2`. `JetNews/` must have no uncommitted changes: `run.json`
records `base_commit`, and a run of anything else would not be rebuildable from it.

## Scenarios

| Scenario | What it drives | Data sources | Read with |
|---|---|---|---|
| `startup` | 20 cold starts, page cache dropped before each, after one untraced warm-up launch | `startup`, `frametimeline` | `startup_ttid_ms` |
| `scroll` | 3 rounds of 6 flings down the home feed and 6 back, after the same plan once untraced | `jank`, `frametimeline` | `frame_ui_time_p95_ms`, `jank_frames_pct`, `gc_time_ms` |
| `bookmarks` | 6 taps on the first recommended row's bookmark, 2 s apart, at the feed's top | `jank`, `frametimeline` | `main_thread_blocked_ms` |
| `leak` | 10 passes of home -> top story -> Back, two forced GCs, then one Java heap dump | `java_hprof` | `heap_growth_objects_by_class` |

The Perfetto fragments in `harness/perfetto/` are superPlayer devicelab's, copied unchanged, so these
traces record what superPlayer's do. The metrics named are perfettoagent's metric library's.

## Toolchain

JetNews at `0bbd72d` uses Gradle 9.5.0, AGP 9.3.1, Kotlin 2.4.20, compileSdk 37 and targetSdk 33 (below
the AVD's 36; it runs without a compatibility prompt). It builds unchanged on JDK 17. The captured APK
is the debug build, so `run.json` says `debuggable: true`: frame and startup times describe a debug
build, and every run, clean or planted, is the same kind of build.
