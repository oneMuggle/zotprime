#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$REPO_ROOT"
}

@test "zotero-standalone-build-win7 points to 5.0.96.3" {
    [ -d client/zotero-standalone-build-win7 ] || skip "win7 build submodule not initialized"
    cd client/zotero-standalone-build-win7
    TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
    [ "$TAG" = "5.0.96.3" ]
}

@test "zotero-client-win7 version is 5.0.96.3.SOURCE" {
    [ -d client/zotero-client-win7 ] || skip "win7 client submodule not initialized"
    cd client/zotero-client-win7
    # 5.0.96.3 era has no `version` file; verify via install.rdf's em:version
    if [ -f version ]; then
        VER=$(cat version | tr -d '\n')
    else
        VER=$(git show 5.0.96.3:install.rdf 2>/dev/null | grep -oE 'em:version>[^<]+' | sed 's/em:version>//' | tr -d '\n' || echo "")
    fi
    [ "$VER" = "5.0.96.3.SOURCE" ]
}
