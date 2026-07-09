#!/bin/bash

################################################################################
# Enhanced Linux System Cleanup Script - Power User Edition
# 
# A comprehensive system cleanup automation tool with advanced features:
# - Multi-distro support with robust detection
# - 3 Aggressiveness Modes (Safe, Standard, Aggressive)
# - Dev Junk Cleanup (Cargo, Go, npm, Gradle, Maven, VS Code)
# - Electron/Heavy Apps Cleanup (Discord, Slack, Spotify)
# - Kernel Assassin (Old kernel removal)
# - Real-time progress visualization & Reporting
# - Snap & Flatpak cleanup
# - Telegram cache cleanup
# - Core dump & crash report cleanup
# - /var/log old file cleanup
# - /tmp & /var/tmp cleanup
# - pnpm/yarn/bun cache cleanup
# - Debtap & pkgfile cache (Arch)
# - paccache support (smart pacman cache)
# - fwupd cache cleanup
# - Config persistence (saves/loads settings)
# - Self-maintenance (auto-clean old reports)
#
# Supported Distributions:
#   - Arch-based: Arch, Manjaro, CachyOS, EndeavourOS
#   - Debian-based: Debian, Ubuntu, Linux Mint, Pop!_OS
#   - RHEL-based: Fedora, RHEL, CentOS, Rocky, AlmaLinux
#   - SUSE-based: openSUSE Leap, Tumbleweed
#   - Gentoo
#
# Author: iL1v3y by S1B Gr0up
# Version: 3.0
# License: MIT
################################################################################

set -o pipefail

################################################################################
# GLOBAL CONSTANTS
################################################################################

readonly SCRIPT_VERSION="3.0"
readonly SCRIPT_NAME="System Cleanup Enhanced"
# Config directories - set dynamically based on TARGET_USER
CONFIG_DIR=""

################################################################################
# COLOR DEFINITIONS
################################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'
readonly NC='\033[0m'

################################################################################
# PROTECTED CACHE DIRECTORIES (never deleted by any cleanup level)
################################################################################

readonly -a PROTECTED_CACHE_DIRS=(
    "nvim"
    "helix"
    "zellij"
    "vim"
    "emacs"
    "kitty"
    "alacritty"
    "tmux"
    "zen"
    "fish"
    "mesa_shader_cache"
    "fontconfig"
    "starship"
)

################################################################################
# GLOBAL VARIABLES
################################################################################

DISTRO=""
DISTRO_NAME=""
DISTRO_VERSION=""
DISTRO_ARCH=""
TARGET_USER=$(whoami)
TARGET_HOME=$(eval echo ~$TARGET_USER)
CONTAINER_RUNTIME=""
ALL_USERS_MODE=false
SPACE_BEFORE=0
SPACE_AFTER=0
SPACE_FREED=0
TOTAL_FREED=0
FREED_LOG=""
PACKAGES_REMOVED=0
INTERACTIVE_MODE=false
DRY_RUN_MODE=false
VERBOSE_MODE=false
ENABLE_BACKUP=true
PARALLEL_EXECUTION=true
CLEANUP_LEVEL="standard" # Default level: safe, standard, aggressive

################################################################################
# CONFIGURATION DEFAULTS
################################################################################

declare -A CONFIG=(
    [journal_retention]="2weeks"
    # Standard
    [enable_package_cache]="true"
    [enable_orphaned_packages]="true"
    [enable_journal_cleanup]="true"
    [enable_user_cache]="true"
    [enable_browser_cache]="true"
    [enable_thumbnails]="true"
    [enable_trash]="true"
    [enable_pip_cache]="true"
    [enable_npm_cache]="true"
    # Aggressive / Specific
    [enable_dev_tools]="false"
    [enable_electron_apps]="false"
    [enable_docker_cleanup]="false"
    [enable_docker_volumes]="false"
    [enable_old_kernels]="false"
    [enable_var_log]="false"
    [enable_snap]="false"
    [enable_flatpak]="false"
    [enable_telegram]="false"
    [enable_temp_dirs]="false"
    [enable_coredumps]="false"
    [enable_fwupd]="false"
    [enable_js_managers]="false"
    [enable_paccache]="false"
    [enable_debtap]="false"
    [enable_pkgfile]="false"
    [paccache_keep]="2"
    
    [backup_enabled]="true"
    [parallel_execution]="true"
)

################################################################################
# UTILITY FUNCTIONS
################################################################################

print_status() { echo -e "${DIM}[$(date '+%H:%M:%S')]${NC} ${BOLD}${CYAN}[INFO]${NC} ${WHITE}$1${NC}"; }
print_success() { echo -e "${DIM}[$(date '+%H:%M:%S')]${NC} ${BOLD}${GREEN}[SUCCESS]${NC} ${WHITE}$1${NC}"; }
print_warning() { echo -e "${DIM}[$(date '+%H:%M:%S')]${NC} ${BOLD}${YELLOW}[WARNING]${NC} ${WHITE}$1${NC}"; }
print_error() { echo -e "${DIM}[$(date '+%H:%M:%S')]${NC} ${BOLD}${RED}[ERROR]${NC} ${WHITE}$1${NC}" >&2; }
print_header() { echo -e "${BOLD}${PURPLE}$1${NC}"; }
print_verbose() { [ "$VERBOSE_MODE" = true ] && print_status "$1"; }

show_spinner() {
    local pid=$1
    local message=$2
    if [ "$INTERACTIVE_MODE" = true ]; then
        echo -ne "  ${CYAN}▶${NC} ${WHITE}${message}${NC}"
        wait $pid
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo -e "\r  ${GREEN}✓${NC} ${WHITE}${message}${NC}"
        else
            echo -e "\r  ${RED}✗${NC} ${WHITE}${message}${NC}"
        fi
        return $exit_code
    fi
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    tput civis
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " ${CYAN}[%c]${NC} ${WHITE}%s${NC}\r" "$spinstr" "$message"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    tput cnorm
    printf "    \r"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }
is_root() { [ "$(id -u)" -eq 0; }

# Get home directory for any user
get_user_home() {
    local user="$1"
    getent passwd "$user" 2>/dev/null | cut -d: -f6
}

# Resolve target user and home
resolve_target_user() {
    if [ -n "$TARGET_USER" ]; then
        local home
        home=$(get_user_home "$TARGET_USER")
        if [ -n "$home" ]; then
            TARGET_HOME="$home"
        else
            print_error "User '$TARGET_USER' not found. Using current user."
            TARGET_USER=$(whoami)
            TARGET_HOME=$(eval echo ~$TARGET_USER)
        fi
    else
        TARGET_USER=$(whoami)
        TARGET_HOME=$(eval echo ~$TARGET_USER)
    fi
    print_status "Target user: $TARGET_USER (home: $TARGET_HOME)"
}

# System users to exclude (never clean these)
readonly -a EXCLUDED_USERS=(
    "root" "daemon" "bin" "sys" "games" "man" 
    "lp" "mail" "news" "uucp" "proxy" "bind"
    "dbus" "http" "https" "gitlab" "mysql"
    "postgresql" "redis" "mongodb" "nobody"
)

# Get list of valid system users (real human users only)
get_system_users() {
    local users=()
    while IFS=: read -r username home _; do
        # Skip excluded users
        local skip=false
        for excluded in "${EXCLUDED_USERS[@]}"; do
            if [ "$username" = "$excluded" ]; then
                skip=true
                break
            fi
        done
        [ "$skip" = true ] && continue
        
        # Skip users without valid home or with nologin/false
        if [ -z "$home" ] || [ ! -d "$home" ]; then
            continue
        fi
        
        # Get shell
        local shell
        shell=$(getent passwd "$username" | cut -d: -f7)
        if [ "$shell" = "/bin/false" ] || [ "$shell" = "/usr/bin/nologin" ]; then
            continue
        fi
        
        users+=("$username")
    done < <(getent passwd)
    
    printf '%s\n' "${users[@]}"
}

# Run cleanup for a single user (used by --all-users mode)
cleanup_single_user() {
    local user="$1"
    local save_user=$TARGET_USER
    local save_home=$TARGET_HOME
    
    TARGET_USER="$user"
    TARGET_HOME=$(get_user_home "$user")
    
    print_status "Processing user: $user"
    
    # Set config directories based on target user
    CONFIG_DIR="$TARGET_HOME/.config/system-cleanup"
    CONFIG_FILE="$CONFIG_DIR/config.conf"
    LOG_DIR="$CONFIG_DIR/logs"
    BACKUP_DIR="$CONFIG_DIR/backups"
    REPORT_DIR="$CONFIG_DIR/reports"
    
    # Initialize directories
    initialize_directories
    
    # Run cleanup for this user (simulated if DRY_RUN_MODE)
    clean_common_caches
    clean_electron_apps
    clean_dev_tools
    
    print_success "Cleanup completed for: $user"
    
    # Restore original user
    TARGET_USER=$save_user
    TARGET_HOME=$save_home
}

# Process all users (--all-users mode)
process_all_users() {
    print_header "\n>>> Processing All Users"
    
    # Get list of users
    local users
    users=$(get_system_users)
    
    if [ -z "$users" ]; then
        print_warning "No valid users found to process"
        return 0
    fi
    
    local user_count
    user_count=$(echo "$users" | wc -l)
    print_status "Found $user_count users to process"
    
    echo "$users" | while read -r user; do
        print_status "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_status "User: $user"
        
        if ask_yes_no "Clean cache for user '$user'?" "y"; then
            cleanup_single_user "$user"
        else
            print_status "Skipped: $user"
        fi
    done
}

get_size_human() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | head -1 | cut -f1 || echo "0"; }
get_size_bytes() { local v; v=$(du -sb "$1" 2>/dev/null | head -1 | cut -f1); echo "${v:-0}"; }
get_size_bytes_sudo() { local v; v=$(sudo du -sb "$1" 2>/dev/null | head -1 | cut -f1); echo "${v:-0}"; }
get_available_space_bytes() { df -B1 / | awk 'NR==2 {print $4}'; }

track_freed() {
    local bytes=$1
    if [ "$bytes" -gt 0 ] 2>/dev/null && [ -n "$FREED_LOG" ]; then
        echo "$bytes" >> "$FREED_LOG"
    fi
}

sum_all_freed() {
    if [ -n "$FREED_LOG" ] && [ -f "$FREED_LOG" ]; then
        local total=0
        while read -r line; do
            total=$((total + line))
        done < "$FREED_LOG"
        TOTAL_FREED=$total
        rm -f "$FREED_LOG"
    fi
}

bytes_to_human() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then echo "$((bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then echo "$((bytes / 1048576))MB"
    else echo "$((bytes / 1073741824))GB"; fi
}

ask_yes_no() {
    local question=$1
    local default=${2:-"n"}
    [ "$DRY_RUN_MODE" = true ] && return 1
    if [ "$INTERACTIVE_MODE" = false ]; then
        # Check if we are in aggressive mode, some things might still need caution or force flag
        # For now, auto mode assumes yes if configured to run
        [ "$default" = "y" ] && return 0 || return 1
    fi
    
    local prompt
    [ "$default" = "y" ] && prompt="[Y/n]" || prompt="[y/N]"
    
    local answer
    read -p "$(echo -e ${CYAN}${question}${NC} ${prompt}: )" answer
    answer=${answer:-$default}
    [[ "$answer" =~ ^[Yy] ]]
}

################################################################################
# CONFIGURATION & LEVELS
################################################################################

initialize_directories() { mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR" "$REPORT_DIR" 2>/dev/null || true; }

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        print_status "Loading saved configuration from $CONFIG_FILE"
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            if [ -n "$key" ] && [ -n "$value" ]; then
                CONFIG[$key]="$value"
            fi
        done < "$CONFIG_FILE"
        print_success "Configuration loaded"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    {
        echo "# LinuxJanitor v${SCRIPT_VERSION} Configuration"
        echo "# Generated: $(date)"
        echo "# Edit manually or use the interactive menu"
        echo ""
        for key in "${!CONFIG[@]}"; do
            echo "$key=${CONFIG[$key]}"
        done
    } | sort > "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"
}

# Set configuration based on Aggressiveness Level
configure_cleanup_level() {
    print_status "Configuring for level: ${BOLD}${YELLOW}${CLEANUP_LEVEL^^}${NC}"
    
    case $CLEANUP_LEVEL in
        "safe")
            CONFIG[enable_package_cache]="false"
            CONFIG[enable_orphaned_packages]="false"
            CONFIG[enable_journal_cleanup]="false"
            CONFIG[enable_user_cache]="true"
            CONFIG[enable_browser_cache]="true"
            CONFIG[enable_thumbnails]="true"
            CONFIG[enable_trash]="true"
            CONFIG[enable_pip_cache]="false"
            CONFIG[enable_npm_cache]="false"
            CONFIG[enable_dev_tools]="false"
            CONFIG[enable_electron_apps]="true" # Safe to clean caches
            CONFIG[enable_docker_cleanup]="false"
            CONFIG[enable_docker_volumes]="false"
            CONFIG[enable_old_kernels]="false"
            CONFIG[enable_var_log]="false"
            CONFIG[enable_snap]="false"
            CONFIG[enable_flatpak]="false"
            CONFIG[enable_telegram]="false"
            CONFIG[enable_temp_dirs]="false"
            CONFIG[enable_coredumps]="false"
            CONFIG[enable_fwupd]="false"
            CONFIG[enable_js_managers]="false"
            CONFIG[enable_paccache]="false"
            CONFIG[enable_debtap]="false"
            CONFIG[enable_pkgfile]="false"
            ;; 
        "standard")
            CONFIG[enable_package_cache]="true"
            CONFIG[enable_orphaned_packages]="true"
            CONFIG[enable_journal_cleanup]="true"
            CONFIG[enable_user_cache]="true"
            CONFIG[enable_browser_cache]="true"
            CONFIG[enable_thumbnails]="true"
            CONFIG[enable_trash]="true"
            CONFIG[enable_pip_cache]="true"
            CONFIG[enable_npm_cache]="true"
            CONFIG[enable_dev_tools]="false" # Dev tools usually manual in standard
            CONFIG[enable_electron_apps]="true"
            CONFIG[enable_docker_cleanup]="false"
            CONFIG[enable_docker_volumes]="false"
            CONFIG[enable_old_kernels]="false"
            CONFIG[enable_var_log]="false"
            CONFIG[enable_snap]="true"
            CONFIG[enable_flatpak]="true"
            CONFIG[enable_telegram]="true"
            CONFIG[enable_temp_dirs]="true"
            CONFIG[enable_coredumps]="true"
            CONFIG[enable_fwupd]="true"
            CONFIG[enable_var_log]="false"
            CONFIG[enable_js_managers]="true"
            CONFIG[enable_paccache]="true"
            CONFIG[enable_debtap]="true"
            CONFIG[enable_pkgfile]="false"
            ;; 
        "aggressive")
            CONFIG[enable_package_cache]="true"
            CONFIG[enable_orphaned_packages]="true"
            CONFIG[enable_journal_cleanup]="true"
            CONFIG[enable_user_cache]="true"
            CONFIG[enable_browser_cache]="true"
            CONFIG[enable_thumbnails]="true"
            CONFIG[enable_trash]="true"
            CONFIG[enable_pip_cache]="true"
            CONFIG[enable_npm_cache]="true"
            CONFIG[enable_dev_tools]="true"
            CONFIG[enable_electron_apps]="true"
            CONFIG[enable_docker_cleanup]="true"
            CONFIG[enable_docker_volumes]="true" # Dangerous!
            CONFIG[enable_old_kernels]="true"    # Dangerous!
            CONFIG[journal_retention]="1d"       # Aggressive retention
            CONFIG[enable_snap]="true"
            CONFIG[enable_flatpak]="true"
            CONFIG[enable_telegram]="true"
            CONFIG[enable_temp_dirs]="true"
            CONFIG[enable_coredumps]="true"
            CONFIG[enable_fwupd]="true"
            CONFIG[enable_var_log]="true"
            CONFIG[enable_js_managers]="true"
            CONFIG[enable_paccache]="true"
            CONFIG[paccache_keep]="1"          # Aggressive: keep only current version
            CONFIG[enable_debtap]="true"
            CONFIG[enable_pkgfile]="true"
            ;; 
    esac
}

################################################################################
# DISTRIBUTION DETECTION
################################################################################

detect_distro() {
    print_status "Detecting Linux distribution..."
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        DISTRO=$ID
        DISTRO_NAME=$PRETTY_NAME
        DISTRO_VERSION=$VERSION_ID
    else
        DISTRO="unknown"
        DISTRO_NAME="Unknown"
    fi
    DISTRO_ARCH=$(uname -m)
    print_success "Detected: ${BOLD}${YELLOW}$DISTRO_NAME${NC} ($DISTRO_ARCH)"
}

################################################################################
# BACKUP & STATS
################################################################################

create_backup() {
    [ "${CONFIG[backup_enabled]}" != "true" ] && return 0
    [ "$ENABLE_BACKUP" != true ] && return 0
    
    print_status "Creating package list backup..."
    local backup_file="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "# System Cleanup Backup - $DISTRO_NAME - $(date)"
        if command_exists pacman; then pacman -Qq; 
        elif command_exists dpkg; then dpkg --get-selections; 
        elif command_exists dnf; then dnf list installed; 
        elif command_exists rpm; then rpm -qa; fi
    } > "$backup_file" 2>/dev/null
    
    print_success "Backup created: $backup_file"
}

initialize_stats() { TOTAL_FREED=0; SPACE_BEFORE=$(get_available_space_bytes); PACKAGES_REMOVED=0; FREED_LOG="$LOG_DIR/.freed_bytes_$$"; rm -f "$FREED_LOG"; touch "$FREED_LOG"; }
update_stats() { SPACE_AFTER=$(get_available_space_bytes); sum_all_freed; SPACE_FREED=$TOTAL_FREED; rm -f "$FREED_LOG" 2>/dev/null; }

################################################################################
# CLEANUP FUNCTIONS
################################################################################

# --- DEV TOOLS CLEANUP (NEW) ---
clean_dev_tools() {
    [ "${CONFIG[enable_dev_tools]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Development Tools"
    
    local freed_total=0

    # Cargo (Rust)
    if [ -d "$TARGET_HOME/.cargo/registry" ]; then
        local size=$(get_size_human "$TARGET_HOME/.cargo/registry")
        local size_bytes=$(du -sb "$TARGET_HOME/.cargo/registry" 2>/dev/null | cut -f1)
        if [ "$DRY_RUN_MODE" = true ]; then
            print_status "[DRY RUN] Would clean Cargo registry ($size)"
        elif ask_yes_no "Clean Cargo registry ($size)? (Will re-download dependencies)" "n"; then
            rm -rf "$TARGET_HOME/.cargo/registry/*"
            freed_total=$((freed_total + ${size_bytes:-0}))
            print_success "Cargo registry cleaned"
        fi
    fi

    # Go
    if command_exists go; then
        local go_cache=$(go env GOCACHE 2>/dev/null)
        if [ -d "$go_cache" ]; then
            local size_bytes=$(du -sb "$go_cache" 2>/dev/null | cut -f1)
             if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would run 'go clean -modcache'"
            elif ask_yes_no "Clean Go module cache?" "n"; then
                go clean -modcache
                freed_total=$((freed_total + ${size_bytes:-0}))
                print_success "Go module cache cleaned"
            fi
        fi
    fi

    # Gradle
    if [ -d "$TARGET_HOME/.gradle/caches" ]; then
        local size=$(get_size_human "$TARGET_HOME/.gradle/caches")
        local size_bytes=$(du -sb "$TARGET_HOME/.gradle/caches" 2>/dev/null | cut -f1)
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean Gradle caches ($size)"
        elif ask_yes_no "Clean Gradle caches ($size)?" "n"; then
            rm -rf "$TARGET_HOME/.gradle/caches/*"
            freed_total=$((freed_total + ${size_bytes:-0}))
            print_success "Gradle caches cleaned"
        fi
    fi

    # Maven
    if [ -d "$TARGET_HOME/.m2/repository" ]; then
        local size=$(get_size_human "$TARGET_HOME/.m2/repository")
        local size_bytes=$(du -sb "$TARGET_HOME/.m2/repository" 2>/dev/null | cut -f1)
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean Maven repository ($size)"
        elif ask_yes_no "Clean Maven repository ($size)?" "n"; then
            rm -rf "$TARGET_HOME/.m2/repository/*"
            freed_total=$((freed_total + ${size_bytes:-0}))
            print_success "Maven repository cleaned"
        fi
    fi
    
    # VS Code Workspace Storage (Accumulates junk from old projects)
    if [ -d "$TARGET_HOME/.config/Code/User/workspaceStorage" ]; then
        local size=$(get_size_human "$TARGET_HOME/.config/Code/User/workspaceStorage")
        local size_bytes=$(du -sb "$TARGET_HOME/.config/Code/User/workspaceStorage" 2>/dev/null | cut -f1)
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean old VS Code workspaces ($size)"
        elif ask_yes_no "Clean VS Code Workspace Storage ($size)? (Resets window states for old projects)" "n"; then
            # Delete folders older than 30 days
            find "$TARGET_HOME/.config/Code/User/workspaceStorage" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null
            local new_bytes=$(du -sb "$TARGET_HOME/.config/Code/User/workspaceStorage" 2>/dev/null | cut -f1)
            freed_total=$((freed_total + ${size_bytes:-0} - ${new_bytes:-0}))
            print_success "Old VS Code workspaces (>30 days) cleaned"
        fi
    fi

    track_freed $freed_total
}

# --- ELECTRON/HEAVY APPS CLEANUP (NEW) ---
clean_electron_apps() {
    [ "${CONFIG[enable_electron_apps]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Electron & Heavy Apps"
    
    declare -A apps=(
        ["Discord"]="$TARGET_HOME/.config/discord/Cache"
        ["Slack"]="$TARGET_HOME/.config/Slack/Cache"
        ["Spotify"]="$TARGET_HOME/.cache/spotify"
        ["Zoom"]="$TARGET_HOME/.cache/zoom"
        ["Code Cache"]="$TARGET_HOME/.config/Code/Cache"
        ["Chrome"]="$TARGET_HOME/.cache/google-chrome"
    )
    
    local freed_total=0
    for app in "${!apps[@]}"; do
        local path="${apps[$app]}"
        if [ -d "$path" ]; then
            local size=$(get_size_human "$path")
            local size_bytes=$(du -sb "$path" 2>/dev/null | cut -f1)
            if [ "$size" != "0" ]; then
                if [ "$DRY_RUN_MODE" = true ]; then
                    print_status "[DRY RUN] Would clean $app cache ($size)"
                else
                    rm -rf "$path/"* 2>/dev/null
                    freed_total=$((freed_total + ${size_bytes:-0}))
                    print_success "Cleaned $app cache ($size)"
                fi
            fi
        fi
    done
    track_freed $freed_total
}

# --- PACMAN ADVANCED CACHE (v3.0) ---
clean_paccache() {
    [ "${CONFIG[enable_paccache]}" != "true" ] && return 0
    case $DISTRO in
        "arch"|"manjaro"|"cachyos"|"endeavouros")
            print_status "Cleaning pacman cache (keeping ${CONFIG[paccache_keep]:-2} versions)..."
            if command_exists paccache; then
                local cache_size=$(sudo du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
                local cache_bytes=$(get_size_bytes_sudo /var/cache/pacman/pkg/)
                if [ "$DRY_RUN_MODE" = true ]; then
                    print_status "[DRY RUN] Would run paccache -rk${CONFIG[paccache_keep]:-2} ($cache_size)"
                else
                    (sudo paccache -rk${CONFIG[paccache_keep]:-2} > /dev/null 2>&1) &
                    show_spinner $! "Cleaning pacman cache (keeping ${CONFIG[paccache_keep]:-2} versions)..."
                    local new_size=$(sudo du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
                    local new_bytes=$(get_size_bytes_sudo /var/cache/pacman/pkg/)
                    local freed=$((cache_bytes - new_bytes))
                    track_freed $freed
                    print_success "Pacman cache: $cache_size → $new_size"
                fi
            else
                print_warning "paccache not found. Install pacman-contrib: sudo pacman -S pacman-contrib"
            fi
            ;;
    esac
}

# --- DEBTAP CACHE (v3.0) ---
clean_debtap() {
    [ "${CONFIG[enable_debtap]}" != "true" ] && return 0
    case $DISTRO in
        "arch"|"manjaro"|"cachyos"|"endeavouros")
            if [ -d "/var/cache/debtap" ]; then
                local size=$(sudo du -sh /var/cache/debtap/ 2>/dev/null | cut -f1)
                local size_bytes=$(sudo du -sb /var/cache/debtap/ 2>/dev/null | cut -f1)
                if [ "$DRY_RUN_MODE" = true ]; then
                    print_status "[DRY RUN] Would clean debtap cache ($size)"
                else
                    sudo rm -rf /var/cache/debtap/* 2>/dev/null
                    track_freed ${size_bytes:-0}
                    print_success "Debtap cache cleaned ($size)"
                fi
            fi
            ;;
    esac
}

# --- PKGFILE CACHE (v3.0) ---
clean_pkgfile() {
    [ "${CONFIG[enable_pkgfile]}" != "true" ] && return 0
    case $DISTRO in
        "arch"|"manjaro"|"cachyos"|"endeavouros")
            if [ -d "/var/cache/pkgfile" ]; then
                local size=$(sudo du -sh /var/cache/pkgfile/ 2>/dev/null | cut -f1)
                local size_bytes=$(sudo du -sb /var/cache/pkgfile/ 2>/dev/null | cut -f1)
                if [ "$DRY_RUN_MODE" = true ]; then
                    print_status "[DRY RUN] Would clean pkgfile cache ($size)"
                else
                    sudo rm -rf /var/cache/pkgfile/* 2>/dev/null
                    track_freed ${size_bytes:-0}
                    print_success "Pkgfile cache cleaned ($size)"
                fi
            fi
            ;;
    esac
}

# --- SNAP CLEANUP (v3.0) ---
clean_snap() {
    [ "${CONFIG[enable_snap]}" != "true" ] && return 0
    command_exists snap || return 0
    print_header "\n>>> Cleaning Snap"

    if [ -d "/var/lib/snapd/cache" ]; then
        local cache_size=$(sudo du -sh /var/lib/snapd/cache/ 2>/dev/null | cut -f1)
        local cache_bytes=$(sudo du -sb /var/lib/snapd/cache/ 2>/dev/null | cut -f1)
        if [ "$DRY_RUN_MODE" = true ]; then
            print_status "[DRY RUN] Would clean snap cache ($cache_size)"
        else
            sudo rm -rf /var/lib/snapd/cache/* 2>/dev/null
            track_freed ${cache_bytes:-0}
            print_success "Snap download cache cleaned ($cache_size)"
        fi
    fi

    if [ "$DRY_RUN_MODE" = true ]; then
        print_status "[DRY RUN] Would remove disabled snap revisions"
    else
        local disabled_count=0
        while read -r snap_name snap_rev; do
            if [ -n "$snap_name" ] && [ -n "$snap_rev" ]; then
                sudo snap remove "$snap_name" --revision="$snap_rev" > /dev/null 2>&1
                ((disabled_count++))
            fi
        done < <(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')
        if [ $disabled_count -gt 0 ]; then
            print_success "Removed $disabled_count disabled snap revision(s)"
        else
            print_status "No disabled snap revisions found"
        fi
    fi
}

# --- FLATPAK CLEANUP (v3.0) ---
clean_flatpak() {
    [ "${CONFIG[enable_flatpak]}" != "true" ] && return 0
    command_exists flatpak || return 0
    print_header "\n>>> Cleaning Flatpak"

    if [ "$DRY_RUN_MODE" = true ]; then
        print_status "[DRY RUN] Would run 'flatpak uninstall --unused'"
    else
        local unused=$(flatpak list --unused 2>/dev/null | wc -l)
        if [ "$unused" -gt 0 ]; then
            print_status "Found $unused unused Flatpak runtimes/apps"
            flatpak uninstall --unused -y > /dev/null 2>&1
            # Flatpak doesn't easily report freed bytes; skip tracking
            print_success "Removed $unused unused Flatpak items"
        else
            print_status "No unused Flatpak items found"
        fi
    fi
}

# --- TELEGRAM CACHE (v3.0) ---
clean_telegram() {
    [ "${CONFIG[enable_telegram]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Telegram"

    local tg_paths=(
        "$TARGET_HOME/.local/share/TelegramDesktop/tdata/user_data/cache"
        "$TARGET_HOME/.local/share/TelegramDesktop/tdata/emoji"
        "$TARGET_HOME/.local/share/TelegramDesktop/tdata/user_data/media_cache"
        "$TARGET_HOME/.local/share/TelegramDesktop/tdata/temp"
    )

    local total_size=0
    for tg_path in "${tg_paths[@]}"; do
        if [ -d "$tg_path" ]; then
            local size_bytes=$(du -sb "$tg_path" 2>/dev/null | cut -f1)
            total_size=$((total_size + size_bytes))
            if [ "$DRY_RUN_MODE" = true ]; then
                local human_size=$(get_size_human "$tg_path")
                print_status "[DRY RUN] Would clean $tg_path ($human_size)"
            else
                rm -rf "$tg_path"/* 2>/dev/null
            fi
        fi
    done

    if [ $total_size -gt 0 ]; then
        track_freed $total_size
        print_success "Telegram cache cleaned ($(bytes_to_human $total_size))"
    else
        print_status "No Telegram cache found"
    fi
}

# --- TEMP DIRECTORIES (v3.0) ---
clean_temp_dirs() {
    [ "${CONFIG[enable_temp_dirs]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Temp Directories"

    local temp_dirs=("/tmp" "/var/tmp")
    for dir in "${temp_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size=$(sudo du -sh "$dir" 2>/dev/null | cut -f1)
            local size_bytes=$(sudo du -sb "$dir" 2>/dev/null | cut -f1)
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would clean $dir ($size)"
            else
                sudo find "$dir" -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null
                local new_bytes=$(sudo du -sb "$dir" 2>/dev/null | cut -f1)
                local freed=$(( ${size_bytes:-0} - ${new_bytes:-0} ))
                track_freed $freed
                print_success "Cleaned $dir (files older than 1 day, was $size)"
            fi
        fi
    done
}

# --- CORE DUMPS (v3.0) ---
clean_coredumps() {
    [ "${CONFIG[enable_coredumps]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Core Dumps"

    if [ -d "/var/lib/systemd/coredump" ]; then
        local size=$(sudo du -sh /var/lib/systemd/coredump/ 2>/dev/null | cut -f1)
        local size_bytes=$(sudo du -sb /var/lib/systemd/coredump/ 2>/dev/null | cut -f1)
        if [ "$size" != "0" ] && [ -n "$size" ]; then
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would clean systemd coredumps ($size)"
            else
                sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null
                track_freed ${size_bytes:-0}
                print_success "Systemd coredumps cleaned ($size)"
            fi
        fi
    fi

    if [ -d "/var/crash" ]; then
        local crash_files=$(sudo find /var/crash -type f 2>/dev/null | wc -l)
        if [ "$crash_files" -gt 0 ]; then
            local size=$(sudo du -sh /var/crash/ 2>/dev/null | cut -f1)
            local size_bytes=$(sudo du -sb /var/crash/ 2>/dev/null | cut -f1)
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would clean $crash_files crash reports ($size)"
            else
                sudo rm -rf /var/crash/* 2>/dev/null
                track_freed ${size_bytes:-0}
                print_success "Crash reports cleaned ($crash_files files, $size)"
            fi
        fi
    fi
}

# --- FWUPD CACHE (v3.0) ---
clean_fwupd() {
    [ "${CONFIG[enable_fwupd]}" != "true" ] && return 0
    if [ -d "/var/cache/fwupd" ]; then
        local size=$(sudo du -sh /var/cache/fwupd/ 2>/dev/null | cut -f1)
        local size_bytes=$(sudo du -sb /var/cache/fwupd/ 2>/dev/null | cut -f1)
        if [ "$size" != "0" ] && [ -n "$size" ]; then
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would clean fwupd cache ($size)"
            else
                sudo rm -rf /var/cache/fwupd/* 2>/dev/null
                track_freed ${size_bytes:-0}
                print_success "Fwupd cache cleaned ($size)"
            fi
        fi
    fi
}

# --- VAR LOG CLEANUP (v3.0) ---
clean_var_log() {
    [ "${CONFIG[enable_var_log]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Old Log Files"

    if [ "$DRY_RUN_MODE" = true ]; then
        local gz_count=$(sudo find /var/log -name "*.gz" 2>/dev/null | wc -l)
        local old_count=$(sudo find /var/log -name "*.old" 2>/dev/null | wc -l)
        local rotated_count=$(sudo find /var/log -name "*.1" -o -name "*.2" -o -name "*.3" 2>/dev/null | wc -l)
        print_status "[DRY RUN] Would clean: $gz_count .gz, $old_count .old, $rotated_count rotated logs"
    else
        sudo find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        sudo find /var/log -name "*.old" -delete 2>/dev/null
        sudo find /var/log -name "*.[0-9]" -mtime +7 -delete 2>/dev/null
        sudo find /var/log -name "*.log" -size +50M -exec truncate -s 0 {} \; 2>/dev/null
        print_success "Old log files cleaned"
    fi
}

# --- JS PACKAGE MANAGERS (v3.0) ---
clean_js_managers() {
    [ "${CONFIG[enable_js_managers]}" != "true" ] && return 0
    print_header "\n>>> Cleaning JS Package Managers"

    local freed_total=0

    if command_exists pnpm; then
        local store_path=$(pnpm store path 2>/dev/null)
        if [ -n "$store_path" ] && [ -d "$store_path" ]; then
            local size=$(get_size_human "$store_path")
            local size_bytes=$(du -sb "$store_path" 2>/dev/null | cut -f1)
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would prune pnpm store ($size)"
            else
                pnpm store prune > /dev/null 2>&1
                local new_bytes=$(du -sb "$store_path" 2>/dev/null | cut -f1)
                freed_total=$((freed_total + ${size_bytes:-0} - ${new_bytes:-0}))
                print_success "pnpm store pruned ($size)"
            fi
        fi
    fi

    if command_exists yarn; then
        if [ -d "$TARGET_HOME/.cache/yarn" ]; then
            local size=$(get_size_human "$TARGET_HOME/.cache/yarn")
            local size_bytes=$(du -sb "$TARGET_HOME/.cache/yarn" 2>/dev/null | cut -f1)
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would clean yarn cache ($size)"
            else
                yarn cache clean > /dev/null 2>&1
                local new_bytes=$(du -sb "$TARGET_HOME/.cache/yarn" 2>/dev/null | cut -f1)
                freed_total=$((freed_total + ${size_bytes:-0} - ${new_bytes:-0}))
                print_success "Yarn cache cleaned ($size)"
            fi
        fi
    fi

    if command_exists bun; then
        local bun_cache="$TARGET_HOME/.bun/install/cache"
        if [ -d "$bun_cache" ]; then
            local size=$(get_size_human "$bun_cache")
            local size_bytes=$(du -sb "$bun_cache" 2>/dev/null | cut -f1)
            if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would clean bun cache ($size)"
            else
                bun pm cache rm > /dev/null 2>&1
                local new_bytes=$(du -sb "$bun_cache" 2>/dev/null | cut -f1)
                freed_total=$((freed_total + ${size_bytes:-0} - ${new_bytes:-0}))
                print_success "Bun cache cleaned ($size)"
            fi
        fi
    fi

    track_freed $freed_total
}

# --- SELF-REPORT CLEANUP (v3.0) ---
clean_own_reports() {
    if [ -d "$REPORT_DIR" ]; then
        local old_reports=$(find "$REPORT_DIR" -name "*.html" -mtime +30 2>/dev/null | wc -l)
        if [ "$old_reports" -gt 0 ]; then
            find "$REPORT_DIR" -name "*.html" -mtime +30 -delete 2>/dev/null
            print_status "Cleaned $old_reports old report(s) (>30 days)"
        fi
    fi
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null
    fi
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -name "*.log" -mtime +90 -delete 2>/dev/null
    fi
}

# --- KERNEL ASSASSIN (NEW) ---
clean_old_kernels() {
    [ "${CONFIG[enable_old_kernels]}" != "true" ] && return 0
    print_header "\n>>> Kernel Assassin (Remove Old Kernels)"
    
    local current_kernel=$(uname -r)
    print_status "Current Kernel: $current_kernel"
    
    if [ "$DRY_RUN_MODE" = true ]; then
        print_status "[DRY RUN] Would attempt to remove old kernels (keeping current + 1 backup)"
        return 0
    fi

    case $DISTRO in
        "ubuntu"|"debian"|"linuxmint"|"pop")
            if ask_yes_no "Remove old kernels (keeping current)? This triggers apt autoremove." "n"; then
                 (sudo apt-get autoremove --purge -y > /dev/null 2>&1) &
                 show_spinner $! "Purging old kernels..."
                 print_success "Old kernels purged."
            fi
            ;; 
        "fedora"|"rhel"|"centos"|"almalinux")
             if ask_yes_no "Remove old kernels (keep latest 2)?" "n"; then
                 (sudo dnf remove --oldinstallonly --setopt installonly_limit=2 -y > /dev/null 2>&1) &
                 show_spinner $! "Removing old kernels..."
                 print_success "Old kernels removed."
             fi
             ;; 
        "arch"|"manjaro")
             print_warning "Kernel cleanup on Arch is risky via script. Recommendation: Use 'pacman -Sc' (already handled) or remove manual kernel packages."
             ;; 
        *)
             print_verbose "Kernel cleanup not implemented for $DISTRO"
             ;; 
    esac
}

# --- STANDARD CLEANUP WRAPPERS ---

clean_package_cache() {
    [ "${CONFIG[enable_package_cache]}" != "true" ] && return 0
    print_status "Cleaning package cache..."
    
    local cmd=""
    case $DISTRO in
        "arch"|"manjaro"|"cachyos"|"endeavouros")
            if command_exists paccache; then
                cmd="sudo paccache -rk${CONFIG[paccache_keep]:-2} --noconfirm"
            else
                cmd="sudo pacman -Sc --noconfirm"
            fi
            ;;
        "debian"|"ubuntu"|"linuxmint")  cmd="sudo apt clean && sudo apt autoclean" ;; 
        "fedora"|"rhel"|"centos")       cmd="sudo dnf clean all" ;; 
    esac
    
    if [ -n "$cmd" ]; then
        if [ "$DRY_RUN_MODE" = true ]; then print_status "[DRY RUN] Would run: $cmd"; else
            eval "$cmd > /dev/null 2>&1" &
            show_spinner $! "Cleaning package cache..."
        fi
    fi
}

remove_orphans() {
    [ "${CONFIG[enable_orphaned_packages]}" != "true" ] && return 0
    print_status "Checking for orphaned packages..."
    
    case $DISTRO in
        "arch"|"manjaro")
            if [ -n "$(pacman -Qtdq)" ]; then
                 if [ "$DRY_RUN_MODE" = true ]; then print_status "[DRY RUN] Would remove orphans"; else
                    if ask_yes_no "Remove orphaned packages?" "y"; then
                        sudo pacman -Rns $(pacman -Qtdq) --noconfirm > /dev/null 2>&1
                        print_success "Orphans removed"
                    fi
                 fi
            fi
            ;; 
        "debian"|"ubuntu")
             if [ "$DRY_RUN_MODE" = true ]; then print_status "[DRY RUN] Would run apt autoremove"; else
                sudo apt autoremove -y > /dev/null 2>&1
                print_success "Auto-remove completed"
             fi
             ;; 
    esac
}

# Detect container runtime (Podman or Docker)
detect_container_runtime() {
    local has_podman=false
    local has_docker=false
    
    command_exists podman && has_podman=true
    command_exists docker && has_docker=true
    
    if [ "$has_podman" = true ] && [ "$has_docker" = true ]; then
        print_status "Both Podman and Docker detected"
        if ask_yes_no "Which container runtime to use? (podman/docker)" "y"; then
            CONTAINER_RUNTIME="podman"
        else
            CONTAINER_RUNTIME="docker"
        fi
    elif [ "$has_podman" = true ]; then
        CONTAINER_RUNTIME="podman"
    elif [ "$has_docker" = true ]; then
        CONTAINER_RUNTIME="docker"
    else
        CONTAINER_RUNTIME=""
    fi
    
    [ -n "$CONTAINER_RUNTIME" ] && print_status "Using container runtime: $CONTAINER_RUNTIME"
}

clean_docker_enhanced() {
    [ "${CONFIG[enable_docker_cleanup]}" != "true" ] && return 0
    
    # Detect runtime
    detect_container_runtime
    [ -z "$CONTAINER_RUNTIME" ] && return 0
    
    print_header "\n>>> Container Cleanup ($CONTAINER_RUNTIME)"
    
    # In aggressive mode, auto-confirm Docker cleanup
    local docker_default="n"
    [ "$CLEANUP_LEVEL" = "aggressive" ] && docker_default="y"
    
    if [ "$DRY_RUN_MODE" = true ]; then
        print_status "[DRY RUN] Would prune $CONTAINER_RUNTIME system"
        [ "${CONFIG[enable_docker_volumes]}" = "true" ] && print_status "[DRY RUN] Would prune volumes (Aggressive)"
        return 0
    fi
    
    if ask_yes_no "Prune unused $CONTAINER_RUNTIME images/containers?" "$docker_default"; then
        $CONTAINER_RUNTIME system prune -af > /dev/null 2>&1
        print_success "$CONTAINER_RUNTIME system pruned"
    fi
    
    if [ "${CONFIG[enable_docker_volumes]}" = "true" ]; then
        print_warning "Volume pruning deletes ALL unused volumes. Database data might be lost."
        if ask_yes_no "Prune unused $CONTAINER_RUNTIME VOLUMES?" "$docker_default"; then
            $CONTAINER_RUNTIME volume prune -f > /dev/null 2>&1
            print_success "$CONTAINER_RUNTIME volumes pruned"
        fi
    fi
}

clean_common_caches() {
    local freed_total=0
    if [ "${CONFIG[enable_user_cache]}" = "true" ]; then
        local cache_bytes=$(du -sb "$TARGET_HOME/.cache" 2>/dev/null | cut -f1)
        local exclude_args=()
        for dir in "${PROTECTED_CACHE_DIRS[@]}"; do
            exclude_args+=(-not -name "$dir")
        done
        find "$TARGET_HOME/.cache" -mindepth 1 -maxdepth 1 "${exclude_args[@]}" -exec rm -rf {} + 2>/dev/null
        local new_bytes=$(du -sb "$TARGET_HOME/.cache" 2>/dev/null | cut -f1)
        freed_total=$((freed_total + ${cache_bytes:-0} - ${new_bytes:-0}))
    fi
    if [ "${CONFIG[enable_thumbnails]}" = "true" ]; then
        local thumb_bytes=0
        [ -d "$TARGET_HOME/.thumbnails" ] && thumb_bytes=$(du -sb "$TARGET_HOME/.thumbnails" 2>/dev/null | cut -f1)
        [ -d "$TARGET_HOME/.cache/thumbnails" ] && thumb_bytes=$((thumb_bytes + $(du -sb "$TARGET_HOME/.cache/thumbnails" 2>/dev/null | cut -f1)))
        rm -rf "$TARGET_HOME/.thumbnails/"* "$TARGET_HOME/.cache/thumbnails/"* 2>/dev/null
        freed_total=$((freed_total + ${thumb_bytes:-0}))
    fi
    if [ "${CONFIG[enable_trash]}" = "true" ]; then
        local trash_bytes=$(du -sb "$TARGET_HOME/.local/share/Trash/" 2>/dev/null | cut -f1)
        rm -rf "$TARGET_HOME/.local/share/Trash/"* 2>/dev/null
        freed_total=$((freed_total + ${trash_bytes:-0}))
    fi
    track_freed $freed_total
    return 0
}

################################################################################
# EXECUTION FLOW
################################################################################

run_cleanup_logic() {
    # 1. System/Admin tasks (Sequential)
    clean_package_cache
    clean_paccache
    clean_debtap
    clean_pkgfile
    remove_orphans
    clean_old_kernels
    clean_docker_enhanced
    clean_snap
    clean_flatpak
    clean_fwupd
    clean_var_log
    clean_coredumps
    clean_temp_dirs
    
    # 2. User Level tasks (Can be Parallel)
    print_status "Running user-level cleanup tasks..."
    
    if [ "$PARALLEL_EXECUTION" = true ] && [ "$INTERACTIVE_MODE" = false ]; then
        clean_common_caches &
        local pid_common=$!
        clean_electron_apps &
        local pid_electron=$!
        clean_dev_tools &
        local pid_dev=$!
        clean_telegram &
        local pid_telegram=$!
        clean_js_managers &
        local pid_js=$!
        
        wait $pid_common $pid_electron $pid_dev $pid_telegram $pid_js
    else
        clean_common_caches
        clean_electron_apps
        clean_dev_tools
        clean_telegram
        clean_js_managers
    fi
    
    # 3. Logs
    if [ "${CONFIG[enable_journal_cleanup]}" = "true" ]; then
        if [ "$DRY_RUN_MODE" = true ]; then print_status "[DRY RUN] Vacuum journal"; else
            sudo journalctl --vacuum-time="${CONFIG[journal_retention]}" > /dev/null 2>&1
        fi
    fi
    
    # 4. Self-maintenance
    clean_own_reports
}

################################################################################
# MENUS & ARGUMENTS
################################################################################

show_main_menu() {
    clear
    print_header "╔═══════════════════════════════════════════════════════════════╗"
    print_header "║   System Cleanup Enhanced v${SCRIPT_VERSION} - Power User Edition        ║"
    print_header "║                      Main Menu                                ║"
    print_header "╚═══════════════════════════════════════════════════════════════╝"
    echo
    echo -e "${CYAN}Select a cleanup mode:${NC}"
    echo
    echo -e "  ${BOLD}1)${NC} ${GREEN}Standard Cleanup${NC} (Recommended - Pkg cache, Trash, Snap, Flatpak, Telegram)"
    echo -e "  ${BOLD}2)${NC} ${BLUE}Safe Cleanup${NC}     (Temp files, Browser cache only)"
    echo -e "  ${BOLD}3)${NC} ${RED}Aggressive Cleanup${NC} (Dev junk, Docker, Old Kernels, debtap, pkgfile, /var/log)"
    echo -e "  ${BOLD}4)${NC} ${YELLOW}Interactive Mode${NC}   (Ask for every step)"
    echo -e "  ${BOLD}5)${NC} ${PURPLE}Dry Run${NC}            (Simulation only - Aggressive check)"
    echo -e "  ${BOLD}6)${NC} Exit"
    echo
    
    local choice
    read -p "$(echo -e ${YELLOW}Select option [1-6]:${NC} )" choice
    
    case $choice in
        1) CLEANUP_LEVEL="standard"; INTERACTIVE_MODE=false ;;
        2) CLEANUP_LEVEL="safe"; INTERACTIVE_MODE=false ;;
        3) CLEANUP_LEVEL="aggressive"; INTERACTIVE_MODE=false ;;
        4) CLEANUP_LEVEL="standard"; INTERACTIVE_MODE=true ;;
        5) DRY_RUN_MODE=true; CLEANUP_LEVEL="aggressive" ;;
        6) echo "Bye!"; exit 0 ;;
        *) echo "Invalid option"; sleep 1; show_main_menu ;;
    esac
}

show_help() {
    cat << EOF
${BOLD}${CYAN}System Cleanup Enhanced v${SCRIPT_VERSION} - Power User Edition${NC}

${BOLD}USAGE:${NC}
    $(basename "$0") [OPTIONS]

${BOLD}MODES:${NC}
    --safe              Clean only temp caches (0 risk)
    --standard          Standard cleanup (Packages, caches, trash) [Default]
    --aggressive        Dev junk, Docker volumes, Old kernels (High risk/reward)

${BOLD}OPTIONS:${NC}
    -i, --interactive   Ask before each major step
    -y, --yes           Automatic mode
    -d, --dry-run       Show what would happen
    --no-backup         Skip backup generation
    -u, --user USER     Run cleanup for a specific user (default: current user)
    -a, --all-users     Clean all users on the system (with confirmation)
    -h, --help          Show this help message
    --version           Show version

${BOLD}EXAMPLES:${NC}
    $(basename "$0")                    # Interactive menu
    $(basename "$0") --standard          # Standard cleanup
    $(basename "$0") --aggressive -y     # Aggressive cleanup, no prompts
    $(basename "$0") --user john         # Clean John's user cache
    $(basename "$0") -u mary --dry-run   # Simulate cleaning Mary's cache
    $(basename "$0") --all-users         # Clean ALL users on system
    $(basename "$0") -a --dry-run        # Preview what would be cleaned for all users
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --safe) CLEANUP_LEVEL="safe"; shift ;; 
            --standard) CLEANUP_LEVEL="standard"; shift ;; 
            --aggressive) CLEANUP_LEVEL="aggressive"; shift ;; 
            -i|--interactive) INTERACTIVE_MODE=true; shift ;; 
            -y|--yes) INTERACTIVE_MODE=false; shift ;; 
            -d|--dry-run) DRY_RUN_MODE=true; shift ;; 
            --no-backup) ENABLE_BACKUP=false; shift ;; 
            -u|--user)
                TARGET_USER="$2"
                shift 2
                ;;
            -a|--all-users)
                ALL_USERS_MODE=true
                shift
                ;;
            -h|--help) show_help; exit 0 ;; 
            *) shift ;; 
        esac
    done
}

main() {
    # If no arguments provided, show interactive menu
    if [ $# -eq 0 ]; then
        show_main_menu
    else
        parse_arguments "$@"
    fi
    
    # Resolve target user and home directory
    resolve_target_user
    
    # Handle --all-users mode
    if [ "$ALL_USERS_MODE" = true ]; then
        if [ "$DRY_RUN_MODE" = true ]; then
            print_warning "DRY RUN - Preview only (use -y to run without prompts)"
        fi
        detect_distro
        process_all_users
        print_success "All users processing completed!"
        return 0
    fi
    
    # Set config directories based on target user
    CONFIG_DIR="$TARGET_HOME/.config/system-cleanup"
    CONFIG_FILE="$CONFIG_DIR/config.conf"
    LOG_DIR="$CONFIG_DIR/logs"
    BACKUP_DIR="$CONFIG_DIR/backups"
    REPORT_DIR="$CONFIG_DIR/reports"
    
    # Initialize
    initialize_directories
    load_config
    configure_cleanup_level
    
    # Header
    print_header "╔═══════════════════════════════════════════════════════════════╗"
    print_header "║   System Cleanup Enhanced v${SCRIPT_VERSION} - Mode: ${CLEANUP_LEVEL^^}          ║"
    print_header "╚═══════════════════════════════════════════════════════════════╝"
    echo
    
    # Sudo check if needed
    if [ "$CLEANUP_LEVEL" != "safe" ] && [ "$DRY_RUN_MODE" = false ]; then
        sudo -v || { print_error "Sudo required for this mode."; exit 1; }
    fi
    
    detect_distro
    initialize_stats
    create_backup
    
    # Run
    echo
    if [ "$DRY_RUN_MODE" = true ]; then print_warning "DRY RUN ACTIVE"; fi
    run_cleanup_logic
    
    # Summary
    save_config
    update_stats
    echo
    print_header "═════════════════════════════════════════════════════════════════"
    echo -e "${BOLD}${YELLOW}Space Freed:${NC} ${GREEN}$(bytes_to_human $SPACE_FREED)${NC}"
    echo "Report saved to: $REPORT_DIR"
    
    # Generate HTML Report
    generate_html_report
}

# Generate HTML Report
generate_html_report() {
    local report_file="$REPORT_DIR/cleanup_$(date +%Y%m%d_%H%M%S).html"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local space_freed_display=$(bytes_to_human $SPACE_FREED)
    
    local user_cache_size="N/A"
    if [ -d "$TARGET_HOME/.cache" ]; then
        user_cache_size=$(du -sh "$TARGET_HOME/.cache/" 2>/dev/null | cut -f1)
    fi
    local journal_size=$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[KMGT]' || echo "0")
    local pacman_cache_size="N/A"
    if [ -d "/var/cache/pacman/pkg" ]; then
        pacman_cache_size=$(sudo du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
    fi
    local trash_size="N/A"
    if [ -d "$TARGET_HOME/.local/share/Trash" ]; then
        trash_size=$(du -sh "$TARGET_HOME/.local/share/Trash/" 2>/dev/null | cut -f1)
    fi
    local thumb_size="N/A"
    if [ -d "$TARGET_HOME/.cache/thumbnails" ]; then
        thumb_size=$(du -sh "$TARGET_HOME/.cache/thumbnails/" 2>/dev/null | cut -f1)
    fi
    
    local total_disk=$(df -B1 / | awk 'NR==2 {print $2}')
    local pct=0
    if [ "$total_disk" -gt 0 ] && [ "$SPACE_FREED" -gt 0 ]; then
        pct=$((SPACE_FREED * 100 / total_disk))
    fi
    local dashoffset=$((440 - (440 * pct / 100)))
    
    cat > "$report_file" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LinuxJanitor Cleanup Report</title>
    <style>
        :root {
            --primary: #2ecc71;
            --primary-dark: #27ae60;
            --danger: #e74c3c;
            --warning: #f39c12;
            --dark: #2c3e50;
            --dark-light: #34495e;
            --light: #ecf0f1;
            --light-dark: #bdc3c7;
            --accent: #3498db;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); min-height: 100vh; padding: 20px; color: var(--light); }
        .container { max-width: 900px; margin: 0 auto; }
        
        /* Header */
        .header { text-align: center; padding: 40px 0; }
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; background: linear-gradient(90deg, var(--primary), var(--accent)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .header .version { color: var(--light-dark); font-size: 0.9rem; }
        .header .timestamp { color: var(--light-dark); margin-top: 10px; }
        
        /* Cards */
        .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }
        .card { background: rgba(255,255,255,0.05); border-radius: 15px; padding: 25px; text-align: center; border: 1px solid rgba(255,255,255,0.1); backdrop-filter: blur(10px); }
        .card .icon { font-size: 2.5rem; margin-bottom: 15px; }
        .card .label { color: var(--light-dark); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; }
        .card .value { font-size: 1.8rem; font-weight: bold; margin-top: 10px; }
        .card.space .value { color: var(--primary); }
        .card.mode .value { color: var(--warning); }
        .card.distro .value { color: var(--accent); }
        
        /* Donut Chart */
        .chart-section { background: rgba(255,255,255,0.05); border-radius: 15px; padding: 30px; margin: 30px 0; border: 1px solid rgba(255,255,255,0.1); }
        .chart-section h2 { margin-bottom: 20px; color: var(--light); }
        .donut-chart { width: 200px; height: 200px; margin: 0 auto; position: relative; }
        .donut-chart svg { transform: rotate(-90deg); }
        .donut-chart circle { fill: none; stroke-width: 30; }
        .donut-chart .bg { stroke: rgba(255,255,255,0.1); }
        .donut-chart .progress { stroke: var(--primary); stroke-linecap: round; transition: stroke-dashoffset 1s ease; }
        .donut-chart .center-text { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); text-align: center; }
        .donut-chart .center-text .size { font-size: 1.5rem; font-weight: bold; }
        .donut-chart .center-text .label { font-size: 0.8rem; color: var(--light-dark); }
        
        /* Legend */
        .legend { display: flex; flex-wrap: wrap; gap: 15px; justify-content: center; margin-top: 25px; }
        .legend-item { display: flex; align-items: center; gap: 8px; }
        .legend-dot { width: 12px; height: 12px; border-radius: 50%; }
        
        /* Details Table */
        .details { background: rgba(255,255,255,0.05); border-radius: 15px; padding: 30px; margin: 30px 0; border: 1px solid rgba(255,255,255,0.1); }
        .details h2 { margin-bottom: 20px; color: var(--light); }
        .details table { width: 100%; border-collapse: collapse; }
        .details th, .details td { padding: 12px 15px; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
        .details th { color: var(--light-dark); font-weight: 600; font-size: 0.85rem; text-transform: uppercase; }
        .details td { color: var(--light); }
        .details tr:last-child td { border-bottom: none; }
        .details .size-col { text-align: right; font-family: monospace; }
        
        /* Footer */
        .footer { text-align: center; padding: 30px; color: var(--light-dark); font-size: 0.85rem; }
        .footer .made-with { margin-top: 10px; }
        
        /* Status badges */
        .badge { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; }
        .badge.safe { background: rgba(46, 204, 113, 0.2); color: var(--primary); }
        .badge.standard { background: rgba(243, 156, 18, 0.2); color: var(--warning); }
        .badge.aggressive { background: rgba(231, 76, 60, 0.2); color: var(--danger); }
        
        /* Animations */
        @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
        .card { animation: fadeIn 0.5s ease forwards; }
        .card:nth-child(1) { animation-delay: 0.1s; }
        .card:nth-child(2) { animation-delay: 0.2s; }
        .card:nth-child(3) { animation-delay: 0.3s; }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <h1>🧹 LinuxJanitor</h1>
            <div class="version">vSCRIPT_VERSION - Power User Edition</div>
            <div class="timestamp">TIMESTAMP</div>
        </div>
        
        <!-- Summary Cards -->
        <div class="cards">
            <div class="card space">
                <div class="icon">💾</div>
                <div class="label">Space Freed</div>
                <div class="value">SPACE_FREED</div>
            </div>
            <div class="card mode">
                <div class="icon">⚡</div>
                <div class="label">Mode</div>
                <div class="value"><span class="badge MODE">MODE_UPPER</span></div>
            </div>
            <div class="card distro">
                <div class="icon">🐧</div>
                <div class="label">System</div>
                <div class="value">DISTRO</div>
            </div>
        </div>
        
        <!-- Donut Chart -->
        <div class="chart-section">
            <h2>📊 Cleanup Summary</h2>
            <div class="donut-chart">
                <svg width="200" height="200" viewBox="0 0 200 200">
                    <circle class="bg" cx="100" cy="100" r="70"></circle>
                    <circle class="progress" cx="100" cy="100" r="70" stroke-dasharray="440" stroke-dashoffset="220"></circle>
                </svg>
                <div class="center-text">
                    <div class="size">50%</div>
                    <div class="label">of target</div>
                </div>
            </div>
            <div class="legend">
                <div class="legend-item"><span class="legend-dot" style="background: #2ecc71"></span> User Cache</div>
                <div class="legend-item"><span class="legend-dot" style="background: #3498db"></span> Package Cache</div>
                <div class="legend-item"><span class="legend-dot" style="background: #9b59b6"></span> Thumbnails</div>
                <div class="legend-item"><span class="legend-dot" style="background: #e74c3c"></span> Trash</div>
            </div>
        </div>
        
        <!-- Details Table -->
        <div class="details">
            <h2>📋 Cleanup Details</h2>
            <table>
                <thead>
                    <tr>
                        <th>Category</th>
                        <th>Description</th>
                        <th class="size-col">Size</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>🗂️ User Cache</td>
                        <td>~/.cache/* (protected caches retained)</td>
                        <td class="size-col">USER_CACHE_SIZE</td>
                    </tr>
                    <tr>
                        <td>📦 Package Cache</td>
                        <td>System package manager cache</td>
                        <td class="size-col">PKG_CACHE_SIZE</td>
                    </tr>
                    <tr>
                        <td>🖼️ Thumbnails</td>
                        <td>Image thumbnails cache</td>
                        <td class="size-col">THUMB_SIZE</td>
                    </tr>
                    <tr>
                        <td>🗑️ Trash</td>
                        <td>User trashbin</td>
                        <td class="size-col">TRASH_SIZE</td>
                    </tr>
                </tbody>
            </table>
        </div>
        
        <!-- Footer -->
        <div class="footer">
            <div>Generated by LinuxJanitor vSCRIPT_VERSION</div>
            <div class="made-with">🧹 Keeping your Linux clean since 2024</div>
        </div>
    </div>
</body>
</html>
HTMLEOF

    # Replace variables
    sed -i "s|SCRIPT_VERSION|${SCRIPT_VERSION}|g" "$report_file"
    sed -i "s|TIMESTAMP|${timestamp}|g" "$report_file"
    sed -i "s|SPACE_FREED|${space_freed_display}|g" "$report_file"
    sed -i "s|MODE_UPPER|${CLEANUP_LEVEL^^}|g" "$report_file"
    sed -i "s|MODE|${CLEANUP_LEVEL}|g" "$report_file"
    sed -i "s|DISTRO|${DISTRO_NAME:-Unknown}|g" "$report_file"
    sed -i "s|USER_CACHE_SIZE|${user_cache_size:-N/A}|g" "$report_file"
    sed -i "s|PKG_CACHE_SIZE|${pacman_cache_size:-N/A}|g" "$report_file"
    sed -i "s|THUMB_SIZE|${thumb_size:-N/A}|g" "$report_file"
    sed -i "s|TRASH_SIZE|${trash_size:-N/A}|g" "$report_file"
    sed -i "s|50%|${pct}%|g" "$report_file"
    sed -i "s|stroke-dashoffset=\"220\"|stroke-dashoffset=\"${dashoffset}\"|g" "$report_file"
    
    print_success "HTML Report generated: $report_file"
}

main "$@"