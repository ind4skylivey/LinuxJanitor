#!/usr/bin/env bats

load test_helper

@test "helpers: AUTO_YES approves ask_yes_no prompts" {
    begin_test
    reset_cleanup_state

    AUTO_YES=true
    INTERACTIVE_MODE=false
    ask_yes_no "Delete everything?" "n"
    [ "$?" -eq 0 ]
}

@test "helpers: non-interactive mode uses default when AUTO_YES is false" {
    begin_test
    reset_cleanup_state

    AUTO_YES=false
    INTERACTIVE_MODE=false
    status=0
    ask_yes_no "Proceed?" "n" || status=$?
    [ "$status" -eq 1 ]
    status=0
    ask_yes_no "Proceed?" "y" || status=$?
    [ "$status" -eq 0 ]
}

@test "helpers: ask_yes_no returns false during dry run" {
    begin_test
    reset_cleanup_state

    DRY_RUN_MODE=true
    status=0
    ask_yes_no "Proceed?" "y" || status=$?
    [ "$status" -eq 1 ]
}

@test "helpers: escape_for_sed escapes sed metacharacters" {
    begin_test

    escaped=$(escape_for_sed "a/b|c&d")
    [ "$escaped" = 'a\/b\|c\&d' ]
}

@test "helpers: dev cleanup removes cargo registry contents" {
    begin_test
    reset_cleanup_state

    DRY_RUN_MODE=false
    AUTO_YES=true
    CONFIG["enable_dev_tools"]="true"
    mkdir -p "$TARGET_HOME/.cargo/registry/cache"
    echo "crate" > "$TARGET_HOME/.cargo/registry/cache/lib.rlib"

    clean_dev_tools
    [ ! -f "$TARGET_HOME/.cargo/registry/cache/lib.rlib" ]
}

@test "helpers: clean_package_cache skips arch when paccache step is enabled" {
    begin_test
    reset_cleanup_state

    DISTRO="arch"
    CONFIG["enable_package_cache"]="true"
    CONFIG["enable_paccache"]="true"
    DRY_RUN_MODE=false
    VERBOSE_MODE=true

    output=$(clean_package_cache 2>&1)
    [[ "$output" == *"handled by paccache step"* ]]
}
