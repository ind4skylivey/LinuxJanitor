#!/usr/bin/env bash

# Shared setup for LinuxJanitor bats tests.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/system-cleanup-enhanced.sh"
FIXTURES_DIR="${BATS_TEST_DIRNAME:-$ROOT_DIR/tests}/fixtures"

teardown() {
    :
}

common_setup() {
    TEST_HOME="$BATS_TMPDIR/home"
    mkdir -p "$TEST_HOME/.cache" "$TEST_HOME/.config/system-cleanup/logs"
    export HOME="$TEST_HOME"
    export PATH="$BATS_TMPDIR/bin:$PATH"
    export TERM=dumb
}

begin_test() {
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    common_setup
}

write_mock_getent() {
    local passwd_file="$1"
    mkdir -p "$BATS_TMPDIR/bin"
    cat > "$BATS_TMPDIR/bin/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" != "passwd" ]]; then
    exit 1
fi
if [[ -n "\${2:-}" ]]; then
    grep "^\$2:" "$passwd_file" || true
else
    cat "$passwd_file"
fi
EOF
    chmod +x "$BATS_TMPDIR/bin/getent"
}

write_passwd_fixture() {
    local passwd_file="$BATS_TMPDIR/passwd.test"
    mkdir -p "$TEST_HOME/alice" "$TEST_HOME/bob"
    cat > "$passwd_file" <<EOF
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
alice:x:1001:1001:Alice:${TEST_HOME}/alice:/bin/bash
bob:x:1002:1002:Bob:${TEST_HOME}/bob:/bin/bash
svc:x:999:999:Service:/var/lib/svc:/usr/sbin/nologin
EOF
    write_mock_getent "$passwd_file"
}

reset_cleanup_state() {
    TARGET_USER="testuser"
    TARGET_HOME="$TEST_HOME"
    CONFIG_DIR="$TARGET_HOME/.config/system-cleanup"
    CONFIG_FILE="$CONFIG_DIR/config.conf"
    LOG_DIR="$CONFIG_DIR/logs"
    BACKUP_DIR="$CONFIG_DIR/backups"
    REPORT_DIR="$CONFIG_DIR/reports"
    DRY_RUN_MODE=false
    AUTO_YES=false
    INTERACTIVE_MODE=false
    CLEANUP_LEVEL="standard"
    FREED_LOG="$LOG_DIR/.freed_bytes_test"
    rm -f "$FREED_LOG"
    touch "$FREED_LOG"
    TOTAL_FREED=0

    configure_cleanup_level
}
