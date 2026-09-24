# shellcheck shell=bash
# SPDX-License-Identifier: Apache-2.0
#
# Home -> post -> back, LEAK_PASSES times (default 10), then one Java heap dump: the run's trace is that
# dump. devicelab's leak hunt, cut down to the one phase JetNews has: the feed left and entered again.
#
# A pass taps the feed's top story, which opens the post screen, waits LEAK_REST_S, and presses Back.
# One untraced pass comes first, so that what the first visit to a post loads once is in both runs alike.
# Before the dump: LEAK_SETTLE_S of quiet, then two forced GCs (SIGUSR1 as root, which ART answers with a
# collection), so the dump holds what is reachable and little else. The dump is java_hprof, taken when its
# data source starts, in a trace bounded at LEAK_DUMP_MS.
#
# The top story's card is centred at (540, 678) px on the 1080x2400 AVD at the feed's top, read off a
# screenshot of the base build.

SCENARIO_DATA_SOURCES=java_hprof
SCENARIO_OWN_TRACE=1
LEAK_PASSES="${LEAK_PASSES:-10}"
LEAK_REST_S="${LEAK_REST_S:-2}"
LEAK_SETTLE_S="${LEAK_SETTLE_S:-5}"
LEAK_DUMP_MS="${LEAK_DUMP_MS:-20000}"
SCENARIO_PARAMETERS="{\"passes\": $LEAK_PASSES, \"rest_s\": $LEAK_REST_S, \"settle_s\": $LEAK_SETTLE_S}"

leak_pass() {
    ui_tap_permille 500 283
    sleep "$LEAK_REST_S"
    adb_s shell input keyevent KEYCODE_BACK
    sleep "$LEAK_REST_S"
}

scenario_setup() {
    [ "$(ui_screen_size)" = "1080 2400" ] || die "the top story's position was read on a 1080x2400 screen"
    [ "$DEVICE_ROOT" = 1 ] || die "the leak scenario forces GCs before the dump, which needs root"
    app_launch >/dev/null
    sleep 4
    assert_app_in_focus
    log "leak: warm-up pass, untraced"
    leak_pass
    assert_app_in_focus
}

scenario_drive() {
    local pass=1 pid
    pid="$(app_pid)"
    while [ "$pass" -le "$LEAK_PASSES" ]; do
        leak_pass
        pass=$((pass + 1))
    done
    assert_app_in_focus
    sleep "$LEAK_SETTLE_S"
    adb_s shell su 0 kill -USR1 "$pid"
    sleep 2
    adb_s shell su 0 kill -USR1 "$pid"
    sleep 2
    log "leak: $LEAK_PASSES passes done; heap dump of pid $pid"
    trace_capture trace java_hprof "$LEAK_DUMP_MS"
    [ "$(app_pid)" = "$pid" ] || die "JetNews restarted during the run"
}
