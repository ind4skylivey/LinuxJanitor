![LinuxJanitor Banner](https://raw.githubusercontent.com/ind4skylivey/LinuxJanitor/main/assets/janitorlinux!%20v2.png)

# 🧹 LinuxJanitor

### Because your disk space is precious (and `node_modules` is a black hole).

**LinuxJanitor** is the Bash script your grandmother warned you about. It's an automated, multi-distro cleaning utility that goes into the dark corners of your filesystem and kicks out the dust bunnies (and the 40GB of Docker images you haven't used since 2021).

> **Current Version:** 2.7 "Power User Edition" ⚡

---

## 🧐 Why?

Because manual cleanup is for people with too much free time.
I got tired of running `pacman -Sc`, `docker system prune`, and deleting `~/.cache` manually every week. So I wrote a script that does it all, looks cool while doing it (spinners! progress bars!), and supports pretty much every major distro.

**Supported Distros:**
- 🏹 Arch Linux (Manjaro, Endeavour, etc.) - *I use Arch btw.*
- 🌀 Debian / Ubuntu / Mint / Pop!_OS
- 🎩 Fedora / RHEL / CentOS
- 🦎 openSUSE
- Gentoo (if you are compiling this README, hi).

---

## 🔥 The "Choose Your Violence" Modes

We have 3 levels of aggressiveness, because sometimes you just want to tidy up, and sometimes you want to nuke everything from orbit.

### 1. 🛡️ `--safe` (The "I have trust issues" mode)
Runs with safety scissors. Only touches temporary caches that are guaranteed to regenerate.
- Cleans: Browser caches, Thumbnails, Temp files.
- **Risk Level:** 0/10. Safe for your grandma's laptop.

### 2. 🧹 `--standard` (The "Regular human" mode)
**Default.** The sweet spot. Cleans what needs to be cleaned without breaking your dev environment.
- Cleans: Everything in Safe + Package Manager Cache (apt/pacman/dnf), Trash, Journal logs (keeps last 2 weeks).
- **Risk Level:** 2/10. Standard maintenance.

### 3. 💀 `--aggressive` (The "I choose violence" mode)
**WARNING:** This mode wakes up and chooses chaos. Ideally for Power Users who know what `git clone` means.
- **Dev Junk:** Nukes `node_modules` caches, Cargo registry (Rust), Go mod cache, Gradle/Maven. **(You will have to re-download deps!)**
- **Docker:** Prunes images AND **Volumes** (optional confirmation).
- **Kernel Assassin:** Hunts down old kernels and removes them (Debian/Fedora).
- **Electron Bloat:** Cleans heavy caches from Discord, Slack, Spotify, VS Code workspace history.
- **Risk Level:** 8/10. Don't come crying if you have to re-download the internet.

---

## 🚀 Usage

### ⚡ One-Command Install (The "I'm lazy" method)
Download, install to `~/.local/bin`, and make it executable automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/ind4skylivey/LinuxJanitor/main/install.sh | bash
```

Then you can just run it from anywhere:
```bash
system-cleanup-enhanced.sh
```
*(Running it without arguments opens the Interactive Menu)*

### 🐢 Manual Install
Old school? I respect that.

```bash
# 1. Download the script (or clone this repo)
git clone https://github.com/ind4skylivey/LinuxJanitor.git
cd LinuxJanitor

# 2. Give it power
chmod +x system-cleanup-enhanced.sh

# 3. RUN IT (Opens Menu)
./system-cleanup-enhanced.sh
```

### 🤖 CLI Arguments (For Automation & Speed)
Skip the menu and just get things done:

| Flag | What it does |
|------|--------------|
| `--safe` | **The boring mode.** See above. |
| `--standard` | **The default.** Standard cleanup. |
| `--aggressive` | **The fun mode.** See above. |
| `-i` | **Interactive Steps.** Asks for permission before *every* single step. |
| `-y` | **Yes Mode.** Automatic mode. Great for cron jobs. |
| `-d` | **Dry Run.** Pretend to clean. See how much space you *would* save. |
| `-u, --user USER` | Run cleanup for a specific user (useful for system admins). |
| `-a, --all-users` | Clean ALL users on the system (asks confirmation per user). |

---

## 🛠️ Configuration

The script creates a config file at `~/.config/system-cleanup/config.conf`.
You can edit it manually if you want to permanently enable the "Kernel Assassin" or disable "Browser Cleanup" because you like keeping 4GB of cookies.

---

## 👤 Running for Other Users

You can clean up other users' caches without switching accounts:

```bash
# Clean another user's cache
./system-cleanup-enhanced.sh --user john --standard

# Clean root's cache (if you dare)
sudo ./system-cleanup-enhanced.sh --user root --aggressive

# Dry run for another user
./system-cleanup-enhanced.sh -u mary --dry-run

# Clean ALL users on the system (v2.7)
./system-cleanup-enhanced.sh --all-users
```

---

## 🔥 v2.7 New Features

### 📄 HTML Report
Generate beautiful HTML reports after cleanup:
- Visual dashboard with charts and icons
- Space freed, mode, distro summary
- Cleanup details breakdown
- Reports saved to `~/.config/system-cleanup/reports/`

### 👥 --all-users Mode (v2.7)
Clean all users on the system with confirmation per user:
```bash
./system-cleanup-enhanced.sh --all-users         # Interactive
./system-cleanup-enhanced.sh -a --dry-run        # Preview only
./system-cleanup-enhanced.sh -a -y               # Auto confirm all
```
- Excludes system users (root, daemon, mysql, etc.)
- Asks confirmation for each user before cleaning

### 🐳 Podman Support (v2.7)
Now supports both Podman and Docker:
- Auto-detects available container runtime
- If both detected, asks which to use
- Works seamlessly with `--aggressive` mode

**How it works:**
- Uses `getent passwd` to resolve the correct home directory
- All user-specific paths (`.cache`, `.config`, etc.) are automatically redirected
- Perfect for system admins managing multiple accounts

**Note:** When using `--user`, the script runs with YOUR permissions. Use `sudo` if you need to access other users' files.

---

## ⚠️ Disclaimer

**I am not responsible if this script deletes your homework, your Bitcoin wallet, or your cat.**
I have tested this on my machines, but `rm -rf` is a powerful spell. Use `--dry-run` first if you are nervous.

---

**Made with 💻 and ☕ by [iL1v3y](https://github.com/ind4skylivey)**
