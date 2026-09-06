#!/usr/bin/env bats

load test_helper

@test "config: saved config overrides cleanup level defaults" {
    begin_test
    reset_cleanup_state

    CLEANUP_LEVEL="standard"
    configure_cleanup_level
    [ "${CONFIG["enable_dev_tools"]}" = "false" ]

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
enable_dev_tools=true
enable_docker_cleanup=true
paccache_keep=5
parallel_execution=false
EOF

    load_config

    [ "${CONFIG["enable_dev_tools"]}" = "true" ]
    [ "${CONFIG["enable_docker_cleanup"]}" = "true" ]
    [ "${CONFIG["paccache_keep"]}" = "5" ]
    [ "$PARALLEL_EXECUTION" = "false" ]
}

@test "config: invalid paccache_keep is reset to default" {
    begin_test
    reset_cleanup_state

    CONFIG["paccache_keep"]="2; rm -rf /"
    apply_config_globals
    [ "${CONFIG["paccache_keep"]}" = "2" ]
}

@test "config: apply_config_globals syncs parallel and backup flags" {
    begin_test
    reset_cleanup_state

    CONFIG["parallel_execution"]="false"
    CONFIG["backup_enabled"]="false"
    apply_config_globals
    [ "$PARALLEL_EXECUTION" = "false" ]
    [ "$ENABLE_BACKUP" = "false" ]
}

@test "config: boolean true/false values load correctly" {
    begin_test
    reset_cleanup_state

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
enable_browser_cache=true
enable_dev_tools=false
EOF
    load_config
    [ "${CONFIG["enable_browser_cache"]}" = "true" ]
    [ "${CONFIG["enable_dev_tools"]}" = "false" ]
}
