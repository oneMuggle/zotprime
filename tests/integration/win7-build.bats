#!/usr/bin/env bats
#
# 临时占位 bats 文件 — PR#4 Task 4.3 将以真实 Win7 集成测试覆盖此处。
# 当前唯一目的是让 `clientbuildtest_win7.Dockerfile` 的 `COPY` 步骤有合法源，
# 以便 PR#2 提交时整条 Dockerfile 链路能自洽。
#
# 不要在 PR#4 之前的提交里扩充本文件 — 真正的测试是 `installer exists`、
# `sha256 round-trips`、`resource/config.js 注入验证`、`manifest schema` 那一组。

setup() {
    cd /home/fz/project/zotprime
}

@test "placeholder - real tests land in PR#4 Task 4.3" {
    skip "real Win7 build integration tests implemented in PR#4"
}
