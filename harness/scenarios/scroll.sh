# shellcheck shell=bash
# SPDX-License-Identifier: Apache-2.0
#
# Scrolls the home feed, in one trace that records what UI jank is read from: devicelab's jank data
# sources (`jank`, `frametimeline`), unchanged.
#
# The plan: SCROLL_ROUNDS rounds, each SCROLL_SWIPES flings down the feed and as many back up, with
# SCROLL_GAP_S between flings and SCROLL_REST_S between halves. The feed repeats its posts ten times
# (PostsData.kt), so it is several screens long and a round's flings move rows rather than overscroll.
# The whole plan runs once untraced first, so that what a first pass composes, loads and compiles once is
# not in the measurement, and the feed is brought back to its top before the traced pass.

SCENARIO_DATA_SOURCES=jank,frametimeline
SCROLL_ROUNDS="${SCROLL_ROUNDS:-3}"
SCROLL_SWIPES="${SCROLL_SWIPES:-6}"
SCROLL_SWIPE_MS="${SCROLL_SWIPE_MS:-300}"
SCROLL_GAP_S="${SCROLL_GAP_S:-1}"
SCROLL_REST_S="${SCROLL_REST_S:-2}"
SCENARIO_PARAMETERS="{\"rounds\": $SCROLL_ROUNDS, \"swipes\": $SCROLL_SWIPES, \"swipe_ms\": $SCROLL_SWIPE_MS, \"gap_s\": $SCROLL_GAP_S, \"rest_s\": $SCROLL_REST_S}"

scroll_plan() {
    local round=1 swipe
    while [ "$round" -le "$SCROLL_ROUNDS" ]; do
        swipe=1
        while [ "$swipe" -le "$SCROLL_SWIPES" ]; do
            ui_swipe "$SCROLL_SWIPE_MS" up
            sleep "$SCROLL_GAP_S"
            swipe=$((swipe + 1))
        done
        sleep "$SCROLL_REST_S"
        swipe=1
        while [ "$swipe" -le "$SCROLL_SWIPES" ]; do
            ui_swipe "$SCROLL_SWIPE_MS" down
            sleep "$SCROLL_GAP_S"
            swipe=$((swipe + 1))
        done
        sleep "$SCROLL_REST_S"
        round=$((round + 1))
    done
}

# Quick flicks back up until the feed is surely at its top; surplus ones at the top are no-ops.
scroll_to_top() {
    local swipe=0
    while [ "$swipe" -lt $((SCROLL_SWIPES * 3)) ]; do
        ui_swipe 150 down
        swipe=$((swipe + 1))
    done
    sleep "$SCROLL_REST_S"
}

scenario_setup() {
    app_launch >/dev/null
    sleep 4
    assert_app_in_focus
    log "scroll: warm-up pass, untraced"
    scroll_plan
    scroll_to_top
    assert_app_in_focus
}

scenario_drive() {
    log "scroll: $((SCROLL_ROUNDS * SCROLL_SWIPES * 2)) flings, traced"
    scroll_plan
    assert_app_in_focus
}
