# syntax=docker/dockerfile:1.6
# 验证 Win7 客户端构建产物的 bats 测试镜像
# 用法: docker build -f clientbuildtest_win7.Dockerfile \
#           --build-arg BUILD_IMAGE=zotprime-client:win7-5.0.96.3 \
#           --build-arg WIN7_VERSION=5.0.96.3 \
#           -t zotprime-clienttest:win7-5.0.96.3 .
#        docker run --rm zotprime-clienttest:win7-5.0.96.3

FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    bats \
    git \
    jq \
    openssl \
    p7zip

ARG BUILD_IMAGE=zotprime-client:win7-5.0.96.3
ARG WIN7_VERSION=5.0.96.3

WORKDIR /tests

# 占位 bats 文件由 PR#2 提供（PR#4 Task 4.3 将替换为真实测试）
COPY tests/integration/win7-build.bats /tests/

# 从构建镜像 copy 产物
COPY --from=${BUILD_IMAGE} /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe /tests/dist/
COPY --from=${BUILD_IMAGE} /dist/Zotero-${WIN7_VERSION}_win-x86_64-setup.exe.sha256 /tests/dist/

CMD ["bats", "win7-build.bats"]
