# 🧹 LinuxJanitor

### Because your disk space is precious (and `node_modules` is a black hole).

**LinuxJanitor** is the Bash script your grandmother warned you about. It's an automated, multi-distro cleaning utility that goes into the dark corners of your filesystem and kicks out the dust bunnies (and the 40GB of Docker images you haven't used since 2021).

> **Current Version:** 2.5 "Power User Edition" ⚡

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

Stop reading and start cleaning.

```bash
# 1. Download the script (or clone this repo)
git clone https://github.com/ind4skylivey/LinuxJanitor.git
cd LinuxJanitor

# 2. Give it power
chmod +x system-cleanup-enhanced.sh

# 3. RUN IT
./system-cleanup-enhanced.sh
```

### Flags for the lazy:

| Flag | What it does |
|------|--------------|
| `-i` | **Interactive Mode.** Asks you for permission before every single step. For control freaks. |
| `-y` | **Yes Mode.** Don't ask questions, just do it. (Respects config). |
| `-d` | **Dry Run.** Pretend to clean so you can see how much space you *would* have saved. |
| `--aggressive` | **The fun mode.** See above. |
| `--safe` | **The boring mode.** See above. |

---

## 🛠️ Configuration

The script creates a config file at `~/.config/system-cleanup/config.conf`.
You can edit it manually if you want to permanently enable the "Kernel Assassin" or disable "Browser Cleanup" because you like keeping 4GB of cookies.

---

## ⚠️ Disclaimer

**I am not responsible if this script deletes your homework, your Bitcoin wallet, or your cat.**
I have tested this on my machines, but `rm -rf` is a powerful spell. Use `--dry-run` first if you are nervous.

---

**Made with 💻 and ☕ by [iL1v3y](https://github.com/ind4skylivey)**
