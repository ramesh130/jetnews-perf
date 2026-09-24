# shellcheck shell=bash
# SPDX-License-Identifier: Apache-2.0
#
# Taps the bookmark of the feed's first "recommended" row, on and off, BOOKMARK_TAPS times (default 6,
# devicelab's jank scenario's number of taps), with BOOKMARK_REST_S of rest around each, in one trace
# with devicelab's jank data sources. The feed is at its top and still, so every tap lands on the same
# button.
#
# Where the button is: at the feed's top on the 1080x2400 AVD, the first recommended row's bookmark icon
# is centred at (1001, 1346) px, read off a screenshot and `uiautomator dump` of the base build. The tap
# is given in per mille of the screen, as devicelab's gestures are. The scenario checks the AVD's size.

SCENARIO_DATA_SOURCES=jank,frametimeline
BOOKMARK_TAPS="${BOOKMARK_TAPS:-6}"
BOOKMARK_REST_S="${BOOKMARK_REST_S:-2}"
BOOKMARK_X_PERMILLE=927
BOOKMARK_Y_PERMILLE=561
SCENARIO_PARAMETERS="{\"taps\": $BOOKMARK_TAPS, \"rest_s\": $BOOKMARK_REST_S, \"tap_permille\": [$BOOKMARK_X_PERMILLE, $BOOKMARK_Y_PERMILLE]}"

scenario_setup() {
    [ "$(ui_screen_size)" = "1080 2400" ] || die "the bookmark's position was read on a 1080x2400 screen"
    app_launch >/dev/null
    sleep 4
    assert_app_in_focus
    log "bookmarks: warm-up taps, untraced"
    ui_tap_permille "$BOOKMARK_X_PERMILLE" "$BOOKMARK_Y_PERMILLE"
    sleep "$BOOKMARK_REST_S"
    ui_tap_permille "$BOOKMARK_X_PERMILLE" "$BOOKMARK_Y_PERMILLE"
    sleep "$BOOKMARK_REST_S"
    assert_app_in_focus
}

scenario_drive() {
    local tap=1
    sleep "$BOOKMARK_REST_S"
    while [ "$tap" -le "$BOOKMARK_TAPS" ]; do
        ui_tap_permille "$BOOKMARK_X_PERMILLE" "$BOOKMARK_Y_PERMILLE"
        sleep "$BOOKMARK_REST_S"
        tap=$((tap + 1))
    done
    assert_app_in_focus
}
