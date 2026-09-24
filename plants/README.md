# Plants

A plant is a known regression kept as a patch against `JetNews/`: `harness/lab run <scenario> --plant
<name>` applies it to a clean tree, builds, and reverts it before anything is measured. The run records
the commit it was applied to and the patch's sha256 in `run.json`, and copies the patch in as
`plant.patch`. This is superPlayer devicelab's procedure (its `plants/README.md`), and these are the same
five regressions, landed where perfettoagent's ADR-0017 maps them in JetNews.

Each is written as the change its author would have made, with a reason, and none says it is a
regression.

| Plant | Scenario | Change | Expected metric |
|---|---|---|---|
| `startup-article-cache` | `startup` | `JetnewsApplication.onCreate` writes (once) and then reads and checksums a 768 MiB "article cache" on the main thread, before `AppContainerImpl` is built | `startup_ttid_ms` |
| `feed-card-grain` | `scroll` | a grain over each `PostCardSimple` row, redrawn every frame, averaged from 6,000 boxed floats per row per draw | `frame_ui_time_p95_ms`, `gc_time_ms` |
| `bookmark-hold` | `bookmarks` | `Thread.sleep(120)` in `PostCardSimple`'s bookmark click, after `onToggleFavorite` | `main_thread_blocked_ms` |
| `feed-row-fit` | `scroll` | every `PostCardSimple` and `PostCardHistory` row's padding breathes by 4 dp, and `PostTitle` is fitted to the row's width in three lines, in 0.25 sp steps from 14 to 24 sp | `frame_ui_time_p95_ms`, `jank_frames_pct` |
| `bookmark-listener` | `leak` | `PostsRepository` gains `addFavoritesListener`, and each `PostCardSimple` registers one in `remember`, with no removal | `heap_growth_objects_by_class` |

## How each was sized

As in perfettoagent's ADR-0008: the clean runs were measured first, and each plant was made large
enough that the smallest planted value clears the largest clean value by more than the clean spread
(the largest clean value minus the smallest). Every value below is perfettoagent's metric library on the
run's trace, with the pinned trace processor 58.2. Runs are in `runs/`; the pilots that sized a plant
were made with an earlier size of its patch and are not kept, so their rows are the record.

### Clean runs

| Scenario | Runs | Metric | Range | Spread |
|---|---:|---|---|---:|
| `startup` | 7 | `startup_ttid_ms` | 837.51-987.67 | 150.16 |
| `scroll` | 7 | `frame_ui_time_p95_ms` | 25.72-29.82 | 4.10 |
| `scroll` | 7 | `jank_frames_pct` | 12.23-30.82 | 18.59 |
| `scroll` | 7 | `gc_time_ms` | 32.61-70.07 | 37.46 |
| `bookmarks` | 5 | `main_thread_blocked_ms` | 0.00-0.02 | 0.02 |
| `leak` | 3 | `heap_growth_objects_by_class`, headline delta between two clean runs | -183 to +146 | |

The startup spread is mostly drift between two sessions: the three runs at 11:13-11:21 UTC read
943.98-987.67, the four from 12:17 on read 837.51-858.88. Nothing in the build or the scenario changed
between them. The host was running other work, and that is what an emulator on a shared laptop measures.

### `startup-article-cache`

| Size | Runs | TTID p50 | Gap to the largest clean run |
|---|---:|---|---:|
| 192 MiB (pilot) | 1 | 1083.34 | 95.67 (0.6x spread) |
| 384 MiB (pilots) | 3 | 1144.54-1195.78 | 156.87 (1.0x) |
| **768 MiB** | 3 | 1529.76-1596.43 | **542.09 (3.6x)** |

superPlayer's plant was 192 MiB for a +214 ms gap; the JetNews debug build's clean starts are about
twice as long and twice as noisy, so the read had to be four times larger to clear the drift above. The
file is written by the first planted launch, the harness's untraced warm-up, and kept by `adb install
-r`; `adb shell pm clear com.example.jetnews` removes it.

### `feed-card-grain`

| Where, how many | `frame_ui_time_p95_ms` | `gc_time_ms` |
|---|---:|---:|
| redrawn when the row moves (`onGloballyPositioned`), 50,000 a row (pilot) | 29.03 | 27.73 |
| redrawn every frame, 2,000 a row (pilot) | 33.67 | 4306.26 |
| redrawn every frame, 4,000 a row (pilot) | 38.45 | 4097.64 |
| **redrawn every frame, 6,000 a row** (3 runs) | **54.17-54.88** | **5854.49-6821.92** |

- **Redrawn only as the row moved, it hardly ran.** A scrolled `LazyColumn` moves its items without
  drawing them again, and the grain read in the draw was not invalidated per frame. GC time did not move.
  So the grain is keyed to the frame clock, as superPlayer's is to its scrolled frames.
- **Every `PostCardSimple` in composition draws it**, and the recommended section is one `LazyColumn`
  item with its 30 rows in a `Column`, so while that section is on screen a frame allocates 30 times
  the count. At 6,000 that is 180,000 boxed floats a frame.
- **What it moves.** UI time's gap to the clean runs is 24.35 ms, 5.9x the spread; GC time's is
  5784.42 ms, 154x. It also makes every frame late: `jank_frames_pct` reads 100.00 on all three runs.

### `bookmark-hold`

120 ms, the roadmap's and superPlayer's, unchanged: the first pilot found six sleeps of the main thread,
and the three runs read 727.70-729.71 ms against 0.00-0.02 clean. The sleep is inside the tap's input
handling, outside `Choreographer#doFrame`, which is what `main_thread_blocked_ms` counts.

### `feed-row-fit`

| Title steps | `frame_ui_time_p95_ms` | `jank_frames_pct` |
|---|---:|---:|
| 0.05 sp (pilot) | 30.39 | 32.54 |
| **0.25 sp** (3 runs) | **100.52-103.76** | **38.01-41.80** |

- **The 0.05 sp pilot was not a measurement of the feed.** Its traced pass holds 24 text layouts in
  all, where the same build at idle on the feed did about 2,400 a frame and drew a frame every 120 ms.
  Driven by hand with the scenario's flings, that build took a fling as a tap and opened a post, where no
  row lives. That is why every run since keeps a screenshot before and after its measured part. 0.25 sp
  does a fifth of the layouts, and each of its runs' `after.png` shows the feed.
- **What it moves.** UI time's gap is 70.70 ms, 17x the spread. `jank_frames_pct` does **not** separate:
  the smallest planted run (38.01) is 7.19 points above the largest clean one (30.82), less than the
  18.59-point clean spread. As on superPlayer (perfettoagent's ADR-0011), jank on this emulator is noisy
  enough to hide the plant.

### `bookmark-listener`

Ten passes of home -> post -> back, plus the launch and the warm-up pass, compose the recommended section
twelve times, and each composition registers 30 listeners that are never removed. Against the clean run
`20260924T122846Z` the planted runs' heap grows by +1723 to +1854 reachable objects, against -183 to +146
between clean runs. The breakdown carries it:

- `PostCardsKt$$ExternalSyntheticLambda2` (the listener): 30 -> 360, +330;
- `SnapshotMutableStateImpl$StateStateRecord` +720, `ParcelableSnapshotMutableState` +360,
  `AtomicInt` +360 (the `bookmarked` state each listener holds);
- no class moves by more than 107 between two clean runs (`float[]`).

The lambda's class name is D8's synthetic name, so a clean build has a different lambda under the same
name (30 of them); the growth, not the name, is the finding.

## Adding or regenerating one

Make the change on a clean `JetNews/`, then `git diff > plants/<name>.patch` and check the tree out
again. Keep the change plausible and unmarked: a comment saying "planted" is what a reader of the diff
would then find.
