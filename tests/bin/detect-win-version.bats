#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../bin/detect-win-version.sh"
    [ -x "$SCRIPT" ] || skip "detect-win-version.sh not executable"
}

@test "recognizes Windows 7 from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 6.1.7601]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win7" ]
}

@test "recognizes Windows 8 from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 6.3.9600]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win8" ]
}

@test "recognizes Windows 10 from ver output (build 19045)" {
    run bash -c "echo 'Microsoft Windows [Version 10.0.19045]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win10" ]
}

@test "recognizes Windows 11 from ver output (build >= 22000)" {
    run bash -c "echo 'Microsoft Windows [Version 10.0.22621]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "win11" ]
}

@test "recognizes Windows XP from ver output" {
    run bash -c "echo 'Microsoft Windows [Version 5.1.2600]' | $SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "xp" ]
}

@test "returns unknown for unrecognized version" {
    run bash -c "echo 'Microsoft Windows [Version 3.1]' | $SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" = "unknown" ]
}

@test "exits 2 when stdin is empty (TTY mode without --probe)" {
    # /dev/null 给空 stdin
    run bash -c "$SCRIPT < /dev/null"
    # 脚本会走到 ! [ -t 0 ] 判 false (因为 < /dev/null 重定向不算 TTY)
    # 但 VER_LINE 为空 → exit 2
    [ "$status" -eq 2 ]
}
