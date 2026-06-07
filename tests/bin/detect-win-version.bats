#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../bin/detect-win-version.sh"
    [ -x "$SCRIPT" ] || skip "detect-win-version.sh not executable"
}

# IMPORTANT: The script writes diagnostic info to stderr (via log_ts).
# Bats `run` merges stdout+stderr into $output by default. We wrap the
# script in `bash -c "..." 2>/dev/null` so stderr is dropped BEFORE bats
# sees it. This works across all bats versions (not just 1.5+).

@test "recognizes Windows 7 from ver output" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 6.1.7601]'"
    [ "$status" -eq 0 ]
    [ "$output" = "win7" ]
}

@test "recognizes Windows 8 from ver output" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 6.3.9600]'"
    [ "$status" -eq 0 ]
    [ "$output" = "win8" ]
}

@test "recognizes Windows 10 from ver output (build 19045)" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 10.0.19045]'"
    [ "$status" -eq 0 ]
    [ "$output" = "win10" ]
}

@test "recognizes Windows 11 from ver output (build >= 22000)" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 10.0.22621]'"
    [ "$status" -eq 0 ]
    [ "$output" = "win11" ]
}

@test "recognizes Windows XP from ver output" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 5.1.2600]'"
    [ "$status" -eq 0 ]
    [ "$output" = "xp" ]
}

@test "returns unknown for unrecognized version" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 3.1]'"
    [ "$status" -eq 1 ]
    [ "$output" = "unknown" ]
}

@test "exits 2 when stdin is empty" {
    run bash -c "bash '$SCRIPT' 2>/dev/null < /dev/null"
    [ "$status" -eq 2 ]
}

@test "handles Win11 edge case (build 21999 = win10, not win11)" {
    run bash -c "bash '$SCRIPT' 2>/dev/null <<< 'Microsoft Windows [Version 10.0.21999]'"
    [ "$status" -eq 0 ]
    [ "$output" = "win10" ]
}
