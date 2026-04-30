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
#
# Supported Distributions:
#   - Arch-based: Arch, Manjaro, CachyOS, EndeavourOS
#   - Debian-based: Debian, Ubuntu, Linux Mint, Pop!_OS
#   - RHEL-based: Fedora, RHEL, CentOS, Rocky, AlmaLinux
#   - SUSE-based: openSUSE Leap, Tumbleweed
#   - Gentoo
#
# Author: iL1v3y by S1B Gr0up
# Version: 2.5
# License: MIT
################################################################################

set -o pipefail

################################################################################
# GLOBAL CONSTANTS
################################################################################

readonly SCRIPT_VERSION="2.7"
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

get_size_human() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1 || echo "0"; }
get_available_space_bytes() { df -B1 / | awk 'NR==2 {print $4}'; }

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

initialize_stats() { SPACE_BEFORE=$(get_available_space_bytes); PACKAGES_REMOVED=0; }
update_stats() { SPACE_AFTER=$(get_available_space_bytes); SPACE_FREED=$((SPACE_AFTER - SPACE_BEFORE)); }

################################################################################
# CLEANUP FUNCTIONS
################################################################################

# --- DEV TOOLS CLEANUP (NEW) ---
clean_dev_tools() {
    [ "${CONFIG[enable_dev_tools]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Development Tools"
    
    # Cargo (Rust)
    if [ -d "$TARGET_HOME/.cargo/registry" ]; then
        local size=$(get_size_human "$TARGET_HOME/.cargo/registry")
        if [ "$DRY_RUN_MODE" = true ]; then
            print_status "[DRY RUN] Would clean Cargo registry ($size)"
        elif ask_yes_no "Clean Cargo registry ($size)? (Will re-download dependencies)" "n"; then
            rm -rf "$TARGET_HOME/.cargo/registry/*"
            print_success "Cargo registry cleaned"
        fi
    fi

    # Go
    if command_exists go; then
        local go_cache=$(go env GOCACHE 2>/dev/null)
        if [ -d "$go_cache" ]; then
             if [ "$DRY_RUN_MODE" = true ]; then
                print_status "[DRY RUN] Would run 'go clean -modcache'"
            elif ask_yes_no "Clean Go module cache?" "n"; then
                go clean -modcache
                print_success "Go module cache cleaned"
            fi
        fi
    fi

    # Gradle
    if [ -d "$TARGET_HOME/.gradle/caches" ]; then
        local size=$(get_size_human "$TARGET_HOME/.gradle/caches")
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean Gradle caches ($size)"
        elif ask_yes_no "Clean Gradle caches ($size)?" "n"; then
            rm -rf "$TARGET_HOME/.gradle/caches/*"
            print_success "Gradle caches cleaned"
        fi
    fi

    # Maven
    if [ -d "$TARGET_HOME/.m2/repository" ]; then
        local size=$(get_size_human "$TARGET_HOME/.m2/repository")
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean Maven repository ($size)"
        elif ask_yes_no "Clean Maven repository ($size)?" "n"; then
            rm -rf "$TARGET_HOME/.m2/repository/*"
            print_success "Maven repository cleaned"
        fi
    fi
    
    # VS Code Workspace Storage (Accumulates junk from old projects)
    if [ -d "$TARGET_HOME/.config/Code/User/workspaceStorage" ]; then
        local size=$(get_size_human "$TARGET_HOME/.config/Code/User/workspaceStorage")
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean old VS Code workspaces ($size)"
        elif ask_yes_no "Clean VS Code Workspace Storage ($size)? (Resets window states for old projects)" "n"; then
            # Delete folders older than 30 days
            find "$TARGET_HOME/.config/Code/User/workspaceStorage" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null
            print_success "Old VS Code workspaces (>30 days) cleaned"
        fi
    fi
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
    
    for app in "${!apps[@]}"; do
        local path="${apps[$app]}"
        if [ -d "$path" ]; then
            local size=$(get_size_human "$path")
            if [ "$size" != "0" ]; then
                if [ "$DRY_RUN_MODE" = true ]; then
                    print_status "[DRY RUN] Would clean $app cache ($size)"
                else
                    rm -rf "$path/*" 2>/dev/null
                    print_success "Cleaned $app cache ($size)"
                fi
            fi
        fi
    done
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
        "arch"|"manjaro") cmd="sudo pacman -Sc --noconfirm" ;; 
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
    
    if [ "$DRY_RUN_MODE" = true ]; then
        print_status "[DRY RUN] Would prune $CONTAINER_RUNTIME system"
        [ "${CONFIG[enable_docker_volumes]}" = "true" ] && print_status "[DRY RUN] Would prune volumes (Aggressive)"
        return 0
    fi
    
    if ask_yes_no "Prune unused $CONTAINER_RUNTIME images/containers?" "n"; then
        $CONTAINER_RUNTIME system prune -af > /dev/null 2>&1
        print_success "$CONTAINER_RUNTIME system pruned"
    fi
    
    if [ "${CONFIG[enable_docker_volumes]}" = "true" ]; then
        print_warning "Volume pruning deletes ALL unused volumes. Database data might be lost."
        if ask_yes_no "Prune unused $CONTAINER_RUNTIME VOLUMES?" "n"; then
            $CONTAINER_RUNTIME volume prune -f > /dev/null 2>&1
            print_success "$CONTAINER_RUNTIME volumes pruned"
        fi
    fi
}

clean_common_caches() {
    if [ "${CONFIG[enable_user_cache]}" = "true" ]; then
        local exclude_args=()
        for dir in "${PROTECTED_CACHE_DIRS[@]}"; do
            exclude_args+=(-not -name "$dir")
        done
        find "$TARGET_HOME/.cache" -mindepth 1 -maxdepth 1 "${exclude_args[@]}" -exec rm -rf {} + 2>/dev/null
    fi
    [ "${CONFIG[enable_thumbnails]}" = "true" ] && rm -rf "$TARGET_HOME/.thumbnails/"* "$TARGET_HOME/.cache/thumbnails/"* 2>/dev/null
    [ "${CONFIG[enable_trash]}" = "true" ] && rm -rf "$TARGET_HOME/.local/share/Trash/"* 2>/dev/null
    return 0
}

################################################################################
# EXECUTION FLOW
################################################################################

run_cleanup_logic() {
    # 1. System/Admin tasks (Sequential)
    clean_package_cache
    remove_orphans
    clean_old_kernels # New
    clean_docker_enhanced
    
    # 2. User Level tasks (Can be Parallel)
    print_status "Running user-level cleanup tasks..."
    
    if [ "$PARALLEL_EXECUTION" = true ] && [ "$INTERACTIVE_MODE" = false ]; then
        clean_common_caches &
        local pid_common=$!
        clean_electron_apps & # New
        local pid_electron=$!
        clean_dev_tools &     # New
        local pid_dev=$!
        
        wait $pid_common $pid_electron $pid_dev
    else
        clean_common_caches
        clean_electron_apps
        clean_dev_tools
    fi
    
    # 3. Logs
    if [ "${CONFIG[enable_journal_cleanup]}" = "true" ]; then
        if [ "$DRY_RUN_MODE" = true ]; then print_status "[DRY RUN] Vacuum journal"; else
            sudo journalctl --vacuum-time="${CONFIG[journal_retention]}" > /dev/null 2>&1
        fi
    fi
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
    echo -e "  ${BOLD}1)${NC} ${GREEN}Standard Cleanup${NC} (Recommended - Pkg cache, Trash, Journals)"
    echo -e "  ${BOLD}2)${NC} ${BLUE}Safe Cleanup${NC}     (Temp files, Browser cache only)"
    echo -e "  ${BOLD}3)${NC} ${RED}Aggressive Cleanup${NC} (Dev junk, Docker, Old Kernels)"
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
            --user)
                TARGET_USER="$2"
                shift 2
                ;;
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
                        <td class="size-col">~VARIES</td>
                    </tr>
                    <tr>
                        <td>📦 Package Cache</td>
                        <td>System package manager cache</td>
                        <td class="size-col">~VARIES</td>
                    </tr>
                    <tr>
                        <td>🖼️ Thumbnails</td>
                        <td>Image thumbnails cache</td>
                        <td class="size-col">~VARIES</td>
                    </tr>
                    <tr>
                        <td>🗑️ Trash</td>
                        <td>User trashbin</td>
                        <td class="size-col">~VARIES</td>
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
    
    print_success "HTML Report generated: $report_file"
}

main "$@"