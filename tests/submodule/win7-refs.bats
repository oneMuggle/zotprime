#!/usr/bin/env bats

setup() {
    cd /home/fz/project/zotprime
}

@test "zotero-standalone-build-win7 points to 5.0.96.3" {
    [ -d client/zotero-standalone-build-win7 ] || skip "win7 build submodule not initialized"
    cd client/zotero-standalone-build-win7
    TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
    [ "$TAG" = "5.0.96.3" ]
}

@test "zotero-client-win7 version file says 5.0.96.3.SOURCE" {
    [ -f client/zotero-client-win7/version ] || skip "win7 client submodule not initialized"
    VER=$(cat client/zotero-client-win7/version | tr -d '\n')
    [ "$VER" = "5.0.96.3.SOURCE" ]
}
