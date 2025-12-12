#!/bin/bash

# Define colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}
   _         _   _      _            _             
  | |       (_) | |    | |          | |            
  | | __ _   _  | | __ | | __ _   __| | ___  _ __  
  | |/ _` | | | | |/ / | |/ _` | / _` |/ _ \| '_ \ 
  | | (_| | | | |   <  | | (_| || (_| | (_) | | | |
  |_|\__,_| |_| |_|\_\ |_|\__,_| \__,_|\___/|_| |_|

                                     Janitor Installer
${NC}"

echo -e "${CYAN}--- LinuxJanitor Installation Script ---"${NC}

# Define the source URL for the script (replace with your actual raw URL if different)
REPO_RAW_URL="https://raw.githubusercontent.com/ind4skylivey/LinuxJanitor/main"
SCRIPT_NAME="system-cleanup-enhanced.sh"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/$SCRIPT_NAME"

# --- Pre-installation Checks ---

# Check for curl or wget
if command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -fsSL"
elif command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -qO-"
else
    echo -e "${RED}Error: Neither 'curl' nor 'wget' found. Please install one of them to proceed.${NC}"
    exit 1
fi

echo -e "${BLUE}1. Checking for existing installation...${NC}"
if [ -f "$INSTALL_PATH" ]; then
    echo -e "${YELLOW}A previous version of LinuxJanitor was found at $INSTALL_PATH.${NC}"
    read -p "$(echo -e ${YELLOW}Do you want to overwrite it? [y/N]: ${NC})" OVERWRITE_CHOICE
    if [[ ! "$OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installation aborted.${NC}"
        exit 0
    fi
    echo -e "${GREEN}Overwriting existing installation...${NC}"
fi

# --- Create Installation Directory ---
echo -e "${BLUE}2. Creating installation directory ($INSTALL_DIR)...${NC}"
mkdir -p "$INSTALL_DIR" || { echo -e "${RED}Error: Failed to create $INSTALL_DIR.${NC}"; exit 1; }

# --- Download the Script ---
echo -e "${BLUE}3. Downloading LinuxJanitor script...${NC}"
$DOWNLOAD_CMD "$REPO_RAW_URL/$SCRIPT_NAME" > "$INSTALL_PATH" || { echo -e "${RED}Error: Failed to download the script.${NC}"; exit 1; }

# --- Make it Executable ---
echo -e "${BLUE}4. Making the script executable...${NC}"
chmod +x "$INSTALL_PATH" || { echo -e "${RED}Error: Failed to make the script executable.${NC}"; exit 1; }

echo -e "${GREEN}--- Installation Complete! ---"${NC}
echo -e "${GREEN}LinuxJanitor has been installed to: ${CYAN}$INSTALL_PATH${NC}"

# --- Check PATH ---
echo -e "${BLUE}5. Checking if $INSTALL_DIR is in your PATH...${NC}"
if [[ ":$PATH:" != ".*:"$INSTALL_DIR":"* ]]; then
    echo -e "${YELLOW}Warning: ${CYAN}$INSTALL_DIR${YELLOW} is not currently in your system's PATH.${NC}"
    echo -e "${YELLOW}You may need to add it to run LinuxJanitor directly from any directory.${NC}"
    echo -e "${YELLOW}To add it for your current session, run: ${CYAN}export PATH=\"
$PATH:$INSTALL_DIR\"${NC}"
    echo -e "${YELLOW}To make it permanent, add the above line to your shell's config file (e.g., ~/.bashrc, ~/.zshrc).${NC}"
else
    echo -e "${GREEN}Path check passed: ${CYAN}$INSTALL_DIR${GREEN} is in your PATH.${NC}"
fi

echo -e "\n${CYAN}--- How to Use LinuxJanitor ---"${NC}
echo -e "${BLUE}You can now run LinuxJanitor using the command: ${NC}"
echo -e "  ${GREEN}$SCRIPT_NAME ${NC}"
echo -e "${BLUE}For example, to run in interactive mode:${NC}"
echo -e "  ${GREEN}$SCRIPT_NAME -i${NC}"
echo -e "${BLUE}To run in aggressive mode (use with caution!):${NC}"
echo -e "  ${GREEN}$SCRIPT_NAME --aggressive${NC}"
echo -e "${BLUE}For more options, including dry-run and different aggressiveness levels:${NC}"
echo -e "  ${GREEN}$SCRIPT_NAME --help${NC}"

echo -e "\n${CYAN}--- Optional: Set up Systemd Timer ---"${NC}
echo -e "${BLUE}To enable automatic weekly cleanups (user-specific), run:${NC}"
echo -e "  ${GREEN}$SCRIPT_NAME --generate-timer${NC}"
echo -e "${BLUE}Then follow the instructions provided by the script to enable the timer.${NC}"

echo -e "\n${GREEN}Thank you for installing LinuxJanitor! Happy cleaning!${NC}"
