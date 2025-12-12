#!/bin/bash

# ==========================================
#  LINUX JANITOR - INSTALLATION PROTOCOL
# ==========================================

# --- Visual Configuration ---
# Reset
NC='\033[0m'       # Text Reset

# Regular Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold
B_RED='\033[1;31m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_BLUE='\033[1;34m'
B_CYAN='\033[1;36m'
B_WHITE='\033[1;37m'

# Icons
ICON_OK="${GREEN}[✓]${NC}"
ICON_FAIL="${RED}[✗]${NC}"
ICON_WARN="${YELLOW}[!]${NC}"
ICON_INFO="${CYAN}[i]${NC}"
ICON_ACTION="${B_WHITE}[➜]${NC}"

# --- Configuration ---
REPO_RAW_URL="https://raw.githubusercontent.com/ind4skylivey/LinuxJanitor/main"
SCRIPT_NAME="system-cleanup-enhanced.sh"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"

# --- Functions ---

print_banner() {
    clear
    echo -e "${B_CYAN}"
    cat << "EOF"
     ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗                 
     ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝                 
     ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝                  
     ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗                  
     ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗                 
     ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝                 
                                                            
          ██╗ █████╗ ███╗   ██╗██╗████████╗ ██████╗ ██████╗ 
          ██║██╔══██╗████╗  ██║██║╚══██╔══╝██╔═████╗██╔══██╗
          ██║███████║██╔██╗ ██║██║   ██║   ██║██╔██║██████╔╝
     ██   ██║██╔══██║██║╚██╗██║██║   ██║   ████╔╝██║██╔══██╗
     ╚█████╔╝██║  ██║██║ ╚████║██║   ██║   ╚██████╔╝██║  ██║
      ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${NC}"
    echo -e "${B_WHITE}                            Because your disk space is precious                             ${NC}"
    echo -e "${BLUE}   ----------------------------------------------------------------------------------------   ${NC}"
    echo ""
}

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- Main Execution ---

print_banner

echo -e "${ICON_INFO} ${B_WHITE}Initializing Installation Sequence...${NC}"
echo -e "    Target User: ${YELLOW}$USER${NC}"
echo -e "    Target OS:   ${YELLOW}$(uname -s)/$(uname -m)${NC}"
echo -e "    Date:        ${YELLOW}$(date +%Y-%m-%d)${NC}"
echo ""
sleep 0.5

# 1. Dependency Check
echo -e "${ICON_ACTION} Scanning for download utilities..."
if command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -fsSL"
    echo -e "    ${ICON_OK} Found: ${GREEN}curl${NC}"
elif command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -qO-"
    echo -e "    ${ICON_OK} Found: ${GREEN}wget${NC}"
else
    echo -e "    ${ICON_FAIL} ${B_RED}Critical Error:${NC} Missing 'curl' or 'wget'."
    exit 1
fi
sleep 0.3

# 2. Existing Install Check
if [ -f "$INSTALL_PATH" ]; then
    echo ""
    echo -e "${ICON_WARN} Detected existing installation at: ${WHITE}$INSTALL_PATH${NC}"
    read -p "    ➜ Overwrite existing version? [y/N]: " OVERWRITE_CHOICE
    if [[ ! "$OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
        echo -e "\n${ICON_INFO} Installation aborted by user."
        exit 0
    fi
    echo -e "    ${ICON_ACTION} Removing old version..."
    rm "$INSTALL_PATH"
fi

# 3. Directory Setup
echo ""
echo -e "${ICON_ACTION} Verifying directory structure..."
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "    ${ICON_INFO} Creating directory: ${WHITE}$INSTALL_DIR${NC}"
    mkdir -p "$INSTALL_DIR"
else
    echo -e "    ${ICON_OK} Directory exists: ${WHITE}$INSTALL_DIR${NC}"
fi
sleep 0.3

# 4. Download
echo ""
echo -e "${ICON_ACTION} Downloading payload from GitHub..."
echo -e "    Source: ${BLUE}$REPO_RAW_URL/$SCRIPT_NAME${NC}"
$DOWNLOAD_CMD "$REPO_RAW_URL/$SCRIPT_NAME" > "$INSTALL_PATH" &
PID=$!
show_spinner $PID
wait $PID
if [ $? -eq 0 ]; then
    echo -e "    ${ICON_OK} ${GREEN}Download successful.${NC}"
else
    echo -e "    ${ICON_FAIL} ${B_RED}Download failed.${NC}"
    exit 1
fi

# 5. Permissions
echo ""
echo -e "${ICON_ACTION} Setting executable permissions..."
chmod +x "$INSTALL_PATH" && echo -e "    ${ICON_OK} Permissions updated (chmod +x)."
sleep 0.3

# 6. Path Check
echo ""
echo -e "${ICON_ACTION} Analyzing system PATH..."
if [[ ":$PATH:" != ".*:$INSTALL_DIR:*" ]]; then
    echo -e "    ${ICON_WARN} ${YELLOW}Notice:${NC} ${WHITE}$INSTALL_DIR${NC} is not in your PATH."
    echo -e "    To run 'system-cleanup-enhanced.sh' from anywhere, add this to your shell config:"
    echo -e "    ${CYAN}export PATH=\"PATH:$INSTALL_DIR\"${NC}"
else
    echo -e "    ${ICON_OK} System PATH is correctly configured."
fi

# --- Summary ---
echo ""
echo -e "${B_GREEN}==========================================${NC}"
echo -e "${B_GREEN}   INSTALLATION COMPLETE - SYSTEM READY   ${NC}"
echo -e "${B_GREEN}==========================================${NC}"
echo ""
echo -e "  ${B_WHITE}Command:${NC}  ${GREEN}$SCRIPT_NAME${NC}"
echo -e "  ${B_WHITE}Location:${NC} ${WHITE}$INSTALL_PATH${NC}"
echo ""
echo -e "${CYAN}USAGE EXAMPLES:${NC}"
echo -e "  ${WHITE}Run Interactive:${NC}    $SCRIPT_NAME -i"
echo -e "  ${WHITE}Run Aggressive:${NC}     $SCRIPT_NAME --aggressive"
echo -e "  ${WHITE}Setup Auto-Clean:${NC}   $SCRIPT_NAME --generate-timer"
echo ""
echo -e "${B_CYAN}Keep it clean, user.${NC}"
echo ""