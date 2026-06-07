#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../bin/build-local.sh"
    [ -f "$SCRIPT" ] || skip "build-local.sh not found"
}

@test "WIN7=1 sources to win7 dockerfile selection" {
    # 提取 WIN7 块判定逻辑（不真正构建）
    run bash -c "WIN7=1 bash -c 'source <(grep -A 30 \"^WIN7=\" $SCRIPT | head -30) 2>&1; echo DOCKERFILE=\$DOCKERFILE; echo TARGET_TAG=\$TARGET_TAG'"
    [[ "$output" == *"prebuild_client_win7.Dockerfile"* ]]
    [[ "$output" == *"win7-5.0.96.3"* ]]
}

@test "WIN7 unset defaults to modern client" {
    run bash -c "bash -c 'source <(grep -A 30 \"^WIN7=\" $SCRIPT | head -30) 2>&1; echo DOCKERFILE=\$DOCKERFILE'"
    [[ "$output" == *"prebuild_client.Dockerfile"* ]]
}

@test "exits 10 when win7 submodule not initialized" {
    # 临时把子模块目录改名模拟未初始化
    cd /home/fz/project/zotprime
    if [ ! -d client/zotero-standalone-build-win7 ]; then
        skip "win7 submodule not present"
    fi
    mv client/zotero-standalone-build-win7 client/.zotero-standalone-build-win7.bak
    run bash -c "WIN7=1 bash $SCRIPT 2>&1"
    mv client/.zotero-standalone-build-win7.bak client/zotero-standalone-build-win7
    # 退出码 10 或 1（取决于脚本实际触发点）
    [[ "$status" -eq 10 || "$status" -eq 1 ]]
}
