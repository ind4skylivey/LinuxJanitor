#!/usr/bin/env bats

load test_helper

@test "dry_run: clean_common_caches does not delete files" {
    begin_test
    reset_cleanup_state
    DRY_RUN_MODE=true
    mkdir -p "$TARGET_HOME/.cache/junk" "$TARGET_HOME/.local/share/Trash/item"
    echo "keep" > "$TARGET_HOME/.cache/junk/file.txt"
    echo "trash" > "$TARGET_HOME/.local/share/Trash/item/doc.txt"

    output=$(clean_common_caches 2>&1)
    [[ "$output" == *"[DRY RUN]"* ]]
    [ -f "$TARGET_HOME/.cache/junk/file.txt" ]
    [ -f "$TARGET_HOME/.local/share/Trash/item/doc.txt" ]
}

@test "dry_run: clean_browser_cache does not delete browser data" {
    begin_test
    reset_cleanup_state
    DRY_RUN_MODE=true
    mkdir -p "$TARGET_HOME/.cache/chromium/Default"
    echo "data" > "$TARGET_HOME/.cache/chromium/Default/cache.bin"
    CONFIG["enable_browser_cache"]="true"

    output=$(clean_browser_cache 2>&1)
    [[ "$output" == *"[DRY RUN]"* ]]
    [ -f "$TARGET_HOME/.cache/chromium/Default/cache.bin" ]
}

@test "dry_run: clean_package_cache does not invoke package manager" {
    begin_test
    reset_cleanup_state
    DRY_RUN_MODE=true
    DISTRO="arch"
    CONFIG["enable_package_cache"]="true"
    CONFIG["enable_paccache"]="false"

    output=$(clean_package_cache 2>&1)
    [[ "$output" == *"[DRY RUN]"* ]]
}

@test "dry_run: non-dry run removes cache contents" {
    begin_test
    reset_cleanup_state
    DRY_RUN_MODE=false
    mkdir -p "$TARGET_HOME/.cache/junk"
    echo "keep" > "$TARGET_HOME/.cache/junk/file.txt"
    CONFIG["enable_user_cache"]="true"
    CONFIG["enable_thumbnails"]="false"
    CONFIG["enable_trash"]="false"

    clean_common_caches
    [ ! -f "$TARGET_HOME/.cache/junk/file.txt" ]
}
