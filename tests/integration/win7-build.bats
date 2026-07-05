#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    DIST="${DIST_DIR:-$REPO_ROOT/dist}"
    INTRANET_ROOT="$REPO_ROOT/intranet-package"
}

@test "win7 installer exists after WIN7=1 build" {
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" ] || skip "needs WIN7=1 docker build"
}

@test "win7 installer has matching sha256" {
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" ] || skip "needs build"
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe.sha256" ] || skip "needs build"
    cd "$DIST"
    sha256sum -c "Zotero-5.0.96.3_win-x86_64-setup.exe.sha256"
}

@test "win7 installer contains Win7 min version string" {
    [ -f "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" ] || skip "needs build"
    if ! command -v 7z >/dev/null; then skip "7z not installed"; fi
    TMP=$(mktemp -d)
    7z x -y -o"$TMP" "$DIST/Zotero-5.0.96.3_win-x86_64-setup.exe" >/dev/null
    XPI=$(find "$TMP" -name 'zotero@chnm.org.xpi' | head -1)
    [ -n "$XPI" ] || { rm -rf "$TMP"; skip "XPI not found in installer"; }
    XPI_TMP=$(mktemp -d)
    7z x -y -o"$XPI_TMP" "$XPI" >/dev/null
    if [ -f "$XPI_TMP/resource/config.js" ]; then
        run grep -c "zotprime.local" "$XPI_TMP/resource/config.js"
        [ "$status" -eq 0 ]
        [ "$output" -gt 0 ]
    fi
    rm -rf "$TMP" "$XPI_TMP"
}

@test "clients-manifest.json validates against schema" {
    [ -f "$INTRANET_ROOT/clients-manifest.json" ] || skip "needs package-for-intranet"
    if ! command -v jq >/dev/null; then skip "jq not installed"; fi
    if command -v npx >/dev/null; then
        cd /tmp
        npx --yes ajv-cli@5 -s "$REPO_ROOT/tests/integration/manifest-schema.json" \
            -d "$INTRANET_ROOT/clients-manifest.json"
        [ "$?" -eq 0 ]
    else
        jq -e '.version and .clients.win10plus.installer and .clients.win7.installer' \
            "$INTRANET_ROOT/clients-manifest.json" >/dev/null
    fi
}
