#!/bin/sh
# Host control-flow tests; requires macOS/Xcode and Defold SDK headers.
set -eu
: "${DMSDK_INCLUDE:?Set DMSDK_INCLUDE to the directory containing dmsdk/lua/lua.h}"
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/fmod-ios-audio.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wl,-dead_strip \
    -I "$DMSDK_INCLUDE" -I "$repo_dir/cicd/ios_audio_stubs" \
    "$repo_dir/cicd/test_ios_audio.m" -framework Foundation -o "$test_dir/test_ios_audio"
for scenario in default resume-default ambient invalid startup-failure startup-fmod-failure \
                startup-category-fmod-failure resume-success resume-category-failure \
                resume-activation-failure resume-category-activation-failure resume-retry-success \
                resume-category-retry-success resume-cancel-retry resume-not-permitted; do
    "$test_dir/test_ios_audio" "$scenario" > "$test_dir/$scenario.log" 2>&1 || {
        cat "$test_dir/$scenario.log"
        exit 1
    }
    printf 'PASS %s\n' "$scenario"
done
