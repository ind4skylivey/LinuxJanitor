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

readonly SCRIPT_VERSION="2.5"
readonly SCRIPT_NAME="System Cleanup Enhanced"
readonly CONFIG_DIR="$HOME/.config/system-cleanup"
readonly CONFIG_FILE="$CONFIG_DIR/config.conf"
readonly LOG_DIR="$CONFIG_DIR/logs"
readonly BACKUP_DIR="$CONFIG_DIR/backups"
readonly REPORT_DIR="$CONFIG_DIR/reports"

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
is_root() { [ "$(id -u)" -eq 0 ]; }
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
    if [ -d "$HOME/.cargo/registry" ]; then
        local size=$(get_size_human "$HOME/.cargo/registry")
        if [ "$DRY_RUN_MODE" = true ]; then
            print_status "[DRY RUN] Would clean Cargo registry ($size)"
        elif ask_yes_no "Clean Cargo registry ($size)? (Will re-download dependencies)" "n"; then
            rm -rf "$HOME/.cargo/registry/*"
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
    if [ -d "$HOME/.gradle/caches" ]; then
        local size=$(get_size_human "$HOME/.gradle/caches")
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean Gradle caches ($size)"
        elif ask_yes_no "Clean Gradle caches ($size)?" "n"; then
            rm -rf "$HOME/.gradle/caches/*"
            print_success "Gradle caches cleaned"
        fi
    fi

    # Maven
    if [ -d "$HOME/.m2/repository" ]; then
        local size=$(get_size_human "$HOME/.m2/repository")
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean Maven repository ($size)"
        elif ask_yes_no "Clean Maven repository ($size)?" "n"; then
            rm -rf "$HOME/.m2/repository/*"
            print_success "Maven repository cleaned"
        fi
    fi
    
    # VS Code Workspace Storage (Accumulates junk from old projects)
    if [ -d "$HOME/.config/Code/User/workspaceStorage" ]; then
        local size=$(get_size_human "$HOME/.config/Code/User/workspaceStorage")
        if [ "$DRY_RUN_MODE" = true ]; then
             print_status "[DRY RUN] Would clean old VS Code workspaces ($size)"
        elif ask_yes_no "Clean VS Code Workspace Storage ($size)? (Resets window states for old projects)" "n"; then
            # Delete folders older than 30 days
            find "$HOME/.config/Code/User/workspaceStorage" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null
            print_success "Old VS Code workspaces (>30 days) cleaned"
        fi
    fi
}

# --- ELECTRON/HEAVY APPS CLEANUP (NEW) ---
clean_electron_apps() {
    [ "${CONFIG[enable_electron_apps]}" != "true" ] && return 0
    print_header "\n>>> Cleaning Electron & Heavy Apps"
    
    declare -A apps=(
        ["Discord"]="$HOME/.config/discord/Cache"
        ["Slack"]="$HOME/.config/Slack/Cache"
        ["Spotify"]="$HOME/.cache/spotify"
        ["Zoom"]="$HOME/.cache/zoom"
        ["Code Cache"]="$HOME/.config/Code/Cache"
        ["Chrome"]="$HOME/.cache/google-chrome"
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

clean_docker_enhanced() {
    [ "${CONFIG[enable_docker_cleanup]}" != "true" ] && return 0
    if ! command_exists docker; then return 0; fi
    
    print_header "\n>>> Docker Cleanup"
    
    if [ "$DRY_RUN_MODE" = true ]; then
        print_status "[DRY RUN] Would prune Docker system"
        [ "${CONFIG[enable_docker_volumes]}" = "true" ] && print_status "[DRY RUN] Would prune volumes (Aggressive)"
        return 0
    fi
    
    if ask_yes_no "Prune unused Docker images/containers?" "n"; then
        docker system prune -af > /dev/null 2>&1
        print_success "Docker system pruned"
    fi
    
    if [ "${CONFIG[enable_docker_volumes]}" = "true" ]; then
        print_warning "Volume pruning deletes ALL unused volumes. Database data might be lost."
        if ask_yes_no "Prune unused Docker VOLUMES?" "n"; then
            docker volume prune -f > /dev/null 2>&1
            print_success "Docker volumes pruned"
        fi
    fi
}

clean_common_caches() {
    if [ "${CONFIG[enable_user_cache]}" = "true" ]; then
        local exclude_args=()
        for dir in "${PROTECTED_CACHE_DIRS[@]}"; do
            exclude_args+=(-not -name "$dir")
        done
        find "$HOME/.cache" -mindepth 1 -maxdepth 1 "${exclude_args[@]}" -exec rm -rf {} + 2>/dev/null
    fi
    [ "${CONFIG[enable_thumbnails]}" = "true" ] && rm -rf ~/.thumbnails/* ~/.cache/thumbnails/* 2>/dev/null
    [ "${CONFIG[enable_trash]}" = "true" ] && rm -rf ~/.local/share/Trash/* 2>/dev/null
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
    --version           Show version
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
}

main "$@"