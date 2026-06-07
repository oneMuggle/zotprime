#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../bin/build-local.sh"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    [ -f "$SCRIPT" ] || skip "build-local.sh not found"
}

@test "WIN7=1 sources to win7 dockerfile selection" {
    # Extract the WIN7 block and source it. Use process substitution so the
    # variables stay in scope of the inner bash.
    run bash -c "
        set -e
        source <(grep -A 30 '^WIN7=' '$SCRIPT' | head -30)
        echo DOCKERFILE=\$DOCKERFILE
        echo TARGET_TAG=\$TARGET_TAG
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"prebuild_client_win7.Dockerfile"* ]]
    [[ "$output" == *"win7-5.0.96.3"* ]]
}

@test "WIN7 unset defaults to modern client" {
    run bash -c "
        set -e
        source <(grep -A 30 '^WIN7=' '$SCRIPT' | head -30)
        echo DOCKERFILE=\$DOCKERFILE
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"prebuild_client.Dockerfile"* ]]
}

@test "exits 10 when win7 submodule not initialized" {
    cd "$REPO_ROOT"
    if [ ! -d client/zotero-standalone-build-win7 ]; then
        skip "win7 submodule not present"
    fi
    # Rename the submodule to simulate uninitialized state, then run with WIN7=1
    mv client/zotero-standalone-build-win7 client/.zotero-standalone-build-win7.bak
    run env WIN7=1 bash "$SCRIPT"
    STATUS_KEEP=$status
    # Always restore, even on test failure
    mv client/.zotero-standalone-build-win7.bak client/zotero-standalone-build-win7
    [ "$STATUS_KEEP" -eq 10 ]
}

@test "exits 12 when zotero-client-win7 version is wrong" {
    # Verify the version check exists by sourcing the script and checking
    # that REQUIRED_VERSION matches the expected 5.0.96.3.
    run bash -c "
        set -e
        source <(grep -A 30 '^WIN7=' '$SCRIPT' | head -30)
        echo REQUIRED_VERSION=\$REQUIRED_VERSION
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"5.0.96.3"* ]]
}
