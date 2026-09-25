# shellcheck shell=bash
# SPDX-License-Identifier: Apache-2.0
#
# The harness's helpers: logging, the device, the Perfetto config and its sessions, plants, and run.json.
#
# Adapted from superPlayer's devicelab (lib/common.sh, lib/perfetto.sh, lib/plants.sh, lib/metadata.sh),
# Apache-2.0, copied rather than imported so that this repository runs on its own. What was dropped is
# what JetNews does not need: booting and replacing emulators, the TV device, publishing a library to
# Maven local and the stale-artifact check that guards it, and playback probes.

log() { printf '[lab %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() {
    log "error: $*"
    exit 1
}

# Every adb call goes to the one device the run adopted.
adb_s() { adb -s "$SERIAL" "$@"; }

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

json_str() {
    # perl -p prints nothing for empty input, so the empty string is written here.
    if [ -z "$1" ]; then
        printf '""'
        return
    fi
    printf '%s' "$1" | perl -0777 -pe '
        s/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g;
        s/([\x00-\x1f])/sprintf("\\u%04x", ord($1))/ge;
        $_ = "\"$_\"";'
}
json_bool() { if [ "$1" = 1 ]; then printf true; else printf false; fi; }

# --- The device ------------------------------------------------------------------------------------
#
# A booted device, found by serial (ANDROID_SERIAL, default emulator-5554). An emulator must run the
# AVD in AVD (default superplayer_verify_36); booting it is the operator's job: `emulator -avd
# superplayer_verify_36 -no-snapshot-load -no-boot-anim -no-window -no-audio -gpu
# swiftshader_indirect`, the flags devicelab boots it with. Any other serial is a physical device,
# which has no AVD to check: run.json names it by model instead. The startup and leak scenarios need
# root, which the userdebug emulator has and a retail phone does not.

device_adopt() {
    SERIAL="${ANDROID_SERIAL:-emulator-5554}"
    [ "$(adb_s shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] ||
        die "no booted device at $SERIAL; boot the AVD first"
    DEVICE_AVD=""
    if [[ "$SERIAL" == emulator-* ]]; then
        DEVICE_AVD="$(adb_s shell getprop ro.boot.qemu.avd_name | tr -d '\r')"
        [ "$DEVICE_AVD" = "${AVD:-superplayer_verify_36}" ] ||
            die "$SERIAL runs AVD '$DEVICE_AVD', not ${AVD:-superplayer_verify_36}"
    fi
    DEVICE_MODEL="$(adb_s shell getprop ro.product.model | tr -d '\r')"
    DEVICE_SDK="$(adb_s shell getprop ro.build.version.sdk | tr -d '\r')"
    DEVICE_ABI="$(adb_s shell getprop ro.product.cpu.abi | tr -d '\r')"
    DEVICE_FINGERPRINT="$(adb_s shell getprop ro.build.fingerprint | tr -d '\r')"
    DEVICE_ROOT=0
    [ "$(adb_s shell su 0 id -u 2>/dev/null | tr -d '\r')" != 0 ] || DEVICE_ROOT=1
}

# The app's pid, or nothing.
app_pid() { adb_s shell pidof "$APP_PACKAGE" | tr -d '\r'; }

# Force-stops the app and starts its launcher Activity, waiting for the platform to report the launch.
# Prints `am start -W`'s output.
app_launch() {
    adb_s shell am force-stop "$APP_PACKAGE"
    sleep "${LAUNCH_SETTLE_S:-2}"
    adb_s shell am start -W -n "$APP_PACKAGE/$APP_ACTIVITY" | tr -d '\r'
}

# Fails unless the app's Activity has focus: a dialog or a crash would make the rest of the run measure
# something else.
assert_app_in_focus() {
    local focus
    # Read whole before matching: `grep -q` would stop reading early, and under pipefail the writer's
    # SIGPIPE would fail the check.
    focus="$(adb_s shell dumpsys window | tr -d '\r' | grep mCurrentFocus || true)"
    case "$focus" in
        *"$APP_PACKAGE"*) ;;
        *) die "$APP_PACKAGE does not have focus: $focus" ;;
    esac
}

# The screen's size in pixels, as "<width> <height>".
ui_screen_size() {
    adb_s shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x\([0-9]*\)$/\1 \2/p' | tail -1
}

# Swipes content upward (a scroll down the list) over `$1` ms, or downward with `$2` = down.
# Positions are fractions of the screen, as devicelab's ui.sh has them.
ui_swipe() {
    local duration="${1:-300}" size width height from to
    size="$(ui_screen_size)"
    width="${size% *}"
    height="${size#* }"
    from=$((height * 3 / 4))
    to=$((height / 4))
    [ "${2:-up}" != down ] || { from=$((height / 4)); to=$((height * 3 / 4)); }
    adb_s shell input swipe $((width / 2)) "$from" $((width / 2)) "$to" "$duration"
}

# Taps the point at fractions `$1`, `$2` (per mille) of the screen's width and height.
ui_tap_permille() {
    local size width height
    size="$(ui_screen_size)"
    width="${size% *}"
    height="${size#* }"
    adb_s shell input tap $((width * $1 / 1000)) $((height * $2 / 1000))
}

# --- The Perfetto config -------------------------------------------------------------------------
#
# perfetto/base.pbtxt plus one perfetto/sources/<name>.pbtxt per data source asked for, with
# @DURATION_MS@ and @PACKAGE@ substituted, as devicelab's lib/perfetto.sh composes it.

perfetto_config() {
    local duration="$1" requested="$2" name config
    config="$(
        cat "$HARNESS/perfetto/base.pbtxt"
        for name in $(printf '%s' "$requested" | tr ',' ' '); do
            [ -f "$HARNESS/perfetto/sources/$name.pbtxt" ] || die "no Perfetto data source '$name'"
            printf '\n# --- %s ---\n' "$name"
            cat "$HARNESS/perfetto/sources/$name.pbtxt"
        done
    )"
    config="$(printf '%s\n' "$config" | sed -e "s/@DURATION_MS@/$duration/g" -e "s/@PACKAGE@/$APP_PACKAGE/g")"
    ! printf '%s\n' "$config" | grep -q '@[A-Z_]*@' || die "unsubstituted placeholder in the Perfetto config"
    printf '%s\n' "$config"
}

# --- Sessions ------------------------------------------------------------------------------------
#
# Detached sessions, named by a key and stopped by it: on API 36 the shell user may not signal the
# perfetto process, so a trace cannot be ended with `kill` (devicelab's lib/perfetto.sh says more).
# TRACE_SETTLE_S stands in for `--background-wait`, which detaching rules out.

PERFETTO_DEVICE_DIR=/data/misc/perfetto-traces

perfetto_session_state() {
    local code
    code="$(adb_s shell "perfetto --is_detached=$1 >/dev/null 2>&1; echo \$?" | tr -d '\r')"
    case "$code" in
        0) printf 'running\n' ;;
        2) printf 'ended\n' ;;
        *) die "perfetto could not say whether session $1 is running (exit $code)" ;;
    esac
}

# Starts trace `$1` (a name in the run directory) with data sources `$2`, bounded at `$3` ms.
trace_begin() {
    local key="lab-$RUN_ID-$1" output
    perfetto_config "$3" "$2" > "$RUN_DIR/$1.perfetto-config.pbtxt"
    output="$(adb_s shell perfetto --txt -c - -o "$PERFETTO_DEVICE_DIR/$key.perfetto-trace" "--detach=$key" \
        < "$RUN_DIR/$1.perfetto-config.pbtxt" 2>&1 | tr -d '\r')" || true
    [ "$(perfetto_session_state "$key")" = running ] || die "perfetto did not start session $key: $output"
    OPEN_SESSION="$key"
    sleep "${TRACE_SETTLE_S:-2}"
}

# Stops trace `$1` if it still runs, pulls it into the run directory, and gzips it (`gzip -9 -n`, as
# perfettoagent's fixtures are, ADR-0010 there).
trace_end() {
    local key="lab-$RUN_ID-$1" device_file
    device_file="$PERFETTO_DEVICE_DIR/$key.perfetto-trace"
    if [ "$(perfetto_session_state "$key")" = running ]; then
        adb_s shell perfetto "--attach=$key" --stop >/dev/null 2>&1 || die "perfetto did not stop session $key"
    fi
    OPEN_SESSION=""
    adb_s pull "$device_file" "$RUN_DIR/$1.perfetto-trace" >/dev/null || die "could not pull $device_file"
    adb_s shell rm -f "$device_file"
    [ -s "$RUN_DIR/$1.perfetto-trace" ] || die "perfetto wrote an empty trace for $1"
    gzip -9 -n "$RUN_DIR/$1.perfetto-trace"
}

# Waits up to `$2` s for trace `$1` to end at its own duration, then pulls it. For a data source that
# records a moment, such as java_hprof's heap dump, taken when the source starts.
trace_capture() {
    local key="lab-$RUN_ID-$1" deadline
    trace_begin "$1" "$2" "$3"
    deadline=$(($(date +%s) + $3 / 1000 + 60))
    while [ "$(perfetto_session_state "$key")" = running ]; do
        [ "$(date +%s)" -lt "$deadline" ] || die "trace $1 was still running after its bound"
        sleep 2
    done
    trace_end "$1"
}

abandon_session() {
    [ -n "${OPEN_SESSION:-}" ] || return 0
    adb_s shell perfetto "--attach=$OPEN_SESSION" --stop >/dev/null 2>&1 || true
    adb_s shell rm -f "$PERFETTO_DEVICE_DIR/$OPEN_SESSION.perfetto-trace" >/dev/null 2>&1 || true
}

# --- Plants --------------------------------------------------------------------------------------
#
# A plant is a patch in plants/, applied to a clean JetNews/ for the build and reverted once the APK is
# built, as devicelab's lib/plants.sh does. The run records the commit it was applied to and the patch's
# sha256, and copies the patch in as plant.patch.

PLANT_NAME=""
PLANT_APPLIED=0

app_tree_clean() { [ -z "$(git -C "$REPO" status --porcelain -- JetNews)" ]; }

plant_apply() {
    local file="$REPO/plants/$1.patch"
    [ -f "$file" ] || die "no plant '$1'; available: $(cd "$REPO/plants" && ls ./*.patch | sed 's|^\./||; s|\.patch$||' | tr '\n' ' ')"
    app_tree_clean || die "plant '$1' is applied only to a clean JetNews/"
    git -C "$REPO" apply --check "$file" || die "plant '$1' does not apply"
    PLANT_NAME="$1"
    PLANT_FILE="$file"
    PLANT_PATCH_SHA256="$(sha256_of "$file")"
    git -C "$REPO" apply "$file"
    PLANT_APPLIED=1
    log "planted '$1' (patch sha256 ${PLANT_PATCH_SHA256:0:12}) on $BASE_COMMIT"
}

plant_revert() {
    [ "$PLANT_APPLIED" = 1 ] || return 0
    git -C "$REPO" apply -R "$PLANT_FILE" || { log "error: could not revert plant '$PLANT_NAME'"; return 1; }
    PLANT_APPLIED=0
    app_tree_clean || { log "error: JetNews/ is not clean after reverting '$PLANT_NAME'"; return 1; }
    log "reverted plant '$PLANT_NAME'"
}

plant_json() {
    if [ -z "$PLANT_NAME" ]; then
        printf 'null'
        return
    fi
    printf '{"name": %s, "patch": "plant.patch", "patch_sha256": %s, "base_commit": %s}' \
        "$(json_str "$PLANT_NAME")" "$(json_str "$PLANT_PATCH_SHA256")" "$(json_str "$BASE_COMMIT")"
}

# --- run.json ------------------------------------------------------------------------------------

run_json() {
    cat <<JSON
{
  "schema": 1,
  "run_id": $(json_str "$RUN_ID"),
  "started_at": $(json_str "$RUN_STARTED_AT"),
  "finished_at": $(json_str "$RUN_FINISHED_AT"),
  "scenario": $(json_str "$SCENARIO"),
  "base_commit": $(json_str "$BASE_COMMIT"),
  "app": {
    "package": $(json_str "$APP_PACKAGE"),
    "source_tree": $(json_str "$APP_TREE"),
    "upstream": "android/compose-samples 0bbd72d69834ec86a9a72bd3513118755fb286c5, JetNews/",
    "build_type": "debug",
    "debuggable": true,
    "apk_sha256": $(json_str "$APK_SHA256")
  },
  "plant": $(plant_json),
  "device": {
    "serial": $(json_str "$SERIAL"),
    "avd": $(json_str "$DEVICE_AVD"),
    "model": $(json_str "$DEVICE_MODEL"),
    "sdk": $(json_str "$DEVICE_SDK"),
    "abi": $(json_str "$DEVICE_ABI"),
    "build_fingerprint": $(json_str "$DEVICE_FINGERPRINT"),
    "root": $(json_bool "$DEVICE_ROOT")
  },
  "host": {
    "os": $(json_str "$(uname -sm)"),
    "jdk": $(json_str "$JDK_VERSION")
  },
  "perfetto": {
    "data_sources": $(json_str "$SCENARIO_DATA_SOURCES"),
    "config": "trace.perfetto-config.pbtxt",
    "trace": "trace.perfetto-trace.gz"
  },
  "parameters": $SCENARIO_PARAMETERS
}
JSON
}
