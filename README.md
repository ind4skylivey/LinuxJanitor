![LinuxJanitor Banner](https://raw.githubusercontent.com/ind4skylivey/LinuxJanitor/main/assets/janitorlinux!%20v2.png)

# LinuxJanitor

**Version 3.0** — Automated system cleanup for Linux, with multi-distro support and configurable cleanup levels.

LinuxJanitor is a Bash utility that consolidates routine maintenance tasks—package manager caches, user caches, container images, journal logs, and development tool artifacts—into a single, repeatable workflow. It supports interactive menus, non-interactive automation, dry runs, and per-user or system-wide cleanup.

## Features

- **Three cleanup levels** — Safe, Standard (default), and Aggressive, each with distinct scope and risk profile
- **Multi-distro support** — Automatic detection for Arch, Debian, Fedora/RHEL, openSUSE, and Gentoo families
- **Interactive or scripted** — Menu-driven UI, CLI flags, and cron-friendly non-interactive mode
- **Dry run** — Preview actions and estimated space savings before making changes
- **HTML reports** — Post-run summaries with space freed, mode, and cleanup breakdown
- **Persistent configuration** — Settings saved to `~/.config/system-cleanup/config.conf`
- **Multi-user administration** — Target a specific user or clean all regular users on the system
- **Container runtime support** — Docker and Podman pruning in aggressive mode
- **Browser, pip, and npm caches** — Targeted cleanup via dedicated config toggles
- **Protected paths** — Editor, terminal, and font caches are never removed

## Supported distributions

| Family | Examples |
|--------|----------|
| Arch-based | Arch Linux, Manjaro, CachyOS, EndeavourOS |
| Debian-based | Debian, Ubuntu, Linux Mint, Pop!_OS |
| RHEL-based | Fedora, RHEL, CentOS, Rocky Linux, AlmaLinux |
| SUSE-based | openSUSE Leap, Tumbleweed |
| Other | Gentoo |

## Cleanup modes

### Safe (`--safe`)

Low-risk maintenance. Removes temporary and regenerable caches only.

- Browser caches, thumbnails, and temp files
- Suitable for conservative or first-time use

### Standard (`--standard`)

Default mode. Balances disk recovery with everyday development workflows.

- Everything in Safe mode
- Package manager cache (apt, pacman, dnf, and related tools)
- Trash, journal logs (retains the last two weeks by default)
- Snap, Flatpak, Telegram, JavaScript package managers (pnpm, yarn, bun)
- paccache, debtap, pkgfile (Arch), coredumps, fwupd, `/tmp` and `/var/tmp`

### Aggressive (`--aggressive`)

Extended cleanup for experienced users. May require re-downloading dependencies or data.

- Everything in Standard mode
- Development caches: npm, Cargo, Go modules, Gradle, Maven
- Docker/Podman images and optional volume pruning
- Old kernel removal (Debian/Fedora families)
- Electron app caches (Discord, Slack, Spotify, VS Code workspace history)
- `/var/log` — removes old compressed and rotated logs; truncates large log files
- debtap and pkgfile caches (Arch)

> **Recommendation:** Run with `--dry-run` before using aggressive mode on a new system.

## Installation

### Quick install

Downloads the script to `~/.local/bin` and sets executable permissions:

```bash
curl -fsSL https://raw.githubusercontent.com/ind4skylivey/LinuxJanitor/main/install.sh | bash
```

Ensure `~/.local/bin` is on your `PATH`:

```bash
export PATH="$PATH:$HOME/.local/bin"
```

### Manual install

```bash
git clone https://github.com/ind4skylivey/LinuxJanitor.git
cd LinuxJanitor
chmod +x system-cleanup-enhanced.sh
./system-cleanup-enhanced.sh
```

## Usage

Running without arguments opens the interactive menu.

```bash
system-cleanup-enhanced.sh
```

### CLI reference

| Flag | Description |
|------|-------------|
| `--safe` | Safe cleanup only |
| `--standard` | Standard cleanup (default) |
| `--aggressive` | Extended cleanup including dev and container artifacts |
| `-i`, `--interactive` | Confirm before each major step |
| `-y`, `--yes` | Non-interactive mode (suitable for automation) |
| `-d`, `--dry-run` | Preview actions without deleting files |
| `--no-backup` | Skip backup generation |
| `-u`, `--user USER` | Run cleanup for a specific user |
| `-a`, `--all-users` | Clean all regular users on the system |
| `-h`, `--help` | Show help |
| `--version` | Show version |

### Examples

```bash
# Standard cleanup with confirmation at each step
system-cleanup-enhanced.sh --standard -i

# Aggressive cleanup, fully automated
system-cleanup-enhanced.sh --aggressive -y

# Preview aggressive cleanup without making changes
system-cleanup-enhanced.sh --aggressive --dry-run

# Clean another user's caches
system-cleanup-enhanced.sh --user john --standard

# Clean all users (interactive confirmation per user)
system-cleanup-enhanced.sh --all-users

# Preview cleanup for all users
system-cleanup-enhanced.sh --all-users --dry-run
```

When using `--user`, the script runs with your current permissions. Use `sudo` if you need access to another user's files.

## Configuration

On first run, LinuxJanitor creates a configuration file at:

```
~/.config/system-cleanup/config.conf
```

You can enable or disable individual cleanup categories (browser cache, Docker, old kernels, Snap, Flatpak, and others) and adjust settings such as journal retention and paccache keep count. Changes persist across sessions.

HTML reports are written to `~/.config/system-cleanup/reports/`. The script automatically removes reports, logs, and backups older than 30–90 days.

## Multi-user mode

`--all-users` iterates over regular system accounts (excluding service users such as `root`, `daemon`, and `mysql`), prompting for confirmation before cleaning each user unless `-y` is set.

```bash
system-cleanup-enhanced.sh --all-users         # Interactive
system-cleanup-enhanced.sh -a --dry-run        # Preview only
system-cleanup-enhanced.sh -a -y               # Auto-confirm all users
```

User home directories are resolved via `getent passwd`, so user-specific paths (`.cache`, `.config`, and similar) are handled correctly.

## Safety

- Use `--dry-run` to review planned actions before running cleanup.
- Aggressive mode can remove development dependencies, container volumes, and old kernels.
- Protected cache directories (Neovim, Helix, Kitty, fontconfig, and others) are never deleted.
- The authors provide this tool as-is. Test on non-critical systems first and maintain backups of important data.

## Testing

LinuxJanitor uses [bats-core](https://github.com/bats-core/bats-core) for automated tests.

```bash
chmod +x scripts/run-tests.sh
./scripts/run-tests.sh
```

The runner uses a system-installed `bats` when available, or vendors bats-core into `tests/.deps/` on first run.

CI runs the same suite on every push and pull request via [`.github/workflows/test.yml`](.github/workflows/test.yml).

## License

MIT License. See the script header for details.

## Author

Maintained by [iL1v3y](https://github.com/ind4skylivey).
