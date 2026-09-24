# shellcheck shell=bash
# SPDX-License-Identifier: Apache-2.0
#
# Cold starts of JetNews, STARTUP_LAUNCHES of them (default 20), in one trace. devicelab's startup
# scenario with the playback wait replaced: JetNews has no media, so each launch is followed by a fixed
# STARTUP_AFTER_S, long enough for the feed's fake 800 ms load and its first frames.
#
# Each launch: force-stop, drop the page cache (root, which the userdebug emulator image has), wait
# STARTUP_SETTLE_S, `am start -W`, refuse anything but COLD. The launch straight after the install is
# the harness's own warm-up and is not in the trace: it was 1124 ms against 889-911 ms for the next five
# when ADR-0017 of perfettoagent tried JetNews.

SCENARIO_DATA_SOURCES=startup,frametimeline
SCENARIO_TRACE_MS=900000
STARTUP_LAUNCHES="${STARTUP_LAUNCHES:-20}"
STARTUP_SETTLE_S="${STARTUP_SETTLE_S:-2}"
STARTUP_AFTER_S="${STARTUP_AFTER_S:-4}"
SCENARIO_PARAMETERS="{\"launches\": $STARTUP_LAUNCHES, \"settle_s\": $STARTUP_SETTLE_S, \"after_s\": $STARTUP_AFTER_S}"

scenario_setup() {
    [ "$DEVICE_ROOT" = 1 ] || die "the startup scenario drops the page cache before each launch, which needs root"
    : > "$RUN_DIR/launches.tsv"
    app_launch >/dev/null
    sleep "$STARTUP_AFTER_S"
    assert_app_in_focus
}

scenario_drive() {
    local launch=1 output state total wait
    while [ "$launch" -le "$STARTUP_LAUNCHES" ]; do
        adb_s shell am force-stop "$APP_PACKAGE"
        adb_s shell "su 0 sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'" || die "could not drop the page cache"
        sleep "$STARTUP_SETTLE_S"
        output="$(adb_s shell am start -W -n "$APP_PACKAGE/$APP_ACTIVITY" | tr -d '\r')"
        state="$(printf '%s\n' "$output" | sed -n 's/^LaunchState: //p')"
        total="$(printf '%s\n' "$output" | sed -n 's/^TotalTime: //p')"
        wait="$(printf '%s\n' "$output" | sed -n 's/^WaitTime: //p')"
        [ "$state" = COLD ] || die "launch $launch was '$state', not COLD: $output"
        printf '%s\t%s\t%s\t%s\n' "$launch" "$state" "$total" "$wait" >> "$RUN_DIR/launches.tsv"
        sleep "$STARTUP_AFTER_S"
        assert_app_in_focus
        log "startup: launch $launch of $STARTUP_LAUNCHES, TotalTime $total ms"
        launch=$((launch + 1))
    done
}
