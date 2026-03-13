# Guide 00: Environment Setup

| | |
|---|---|
| **Risk Level** | ZERO -- no device interaction, software installs only |
| **Estimated Time** | 30-60 minutes |
| **Prerequisites** | macOS 13+ (Ventura or later), admin password, internet connection |
| **Device Needed** | No |

---

## Overview

Before touching your Portal, you need a working toolkit on your Mac. This guide walks you through installing every dependency from scratch. Nothing here interacts with your device, so there is zero risk.

By the end of this guide you will have:

- Homebrew (the macOS package manager)
- Python 3.11 with a virtual environment
- The **bkerler/edl** tool (for Qualcomm EDL communication)
- Android platform tools (adb, fastboot)
- Docker Desktop (optional, for building magiskboot)

---

## Step 1: Install Homebrew

Homebrew is the standard package manager for macOS. If you already have it, skip to Step 2.

Open **Terminal** (press Cmd+Space, type "Terminal", press Enter) and paste:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the on-screen prompts. You will need to enter your Mac password.

> **Important for Apple Silicon Macs (M1/M2/M3/M4):** After installation, Homebrew will tell you to run two commands to add it to your PATH. Copy and run both of those commands. They look something like:
>
> ```bash
> echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
> eval "$(/opt/homebrew/bin/brew shellenv)"
> ```

Verify it works:

```bash
brew --version
```

You should see something like `Homebrew 4.x.x`.

For more information, visit: [https://brew.sh](https://brew.sh)

---

## Step 2: Install Core Dependencies

Run the provided install script:

```bash
./scripts/setup/install_dependencies.sh
```

This script installs the following via Homebrew:

| Package | What It Does |
|---|---|
| `python@3.11` | Python runtime for the EDL tool |
| `libusb` | USB device communication library |
| `android-platform-tools` | Provides `adb` and `fastboot` commands |
| `git` | Version control (needed to clone repos) |
| `wget` | File downloader (used by firmware scripts) |

If you prefer to install manually:

```bash
brew install python@3.11 libusb android-platform-tools git wget
```

Verify the installs:

```bash
python3.11 --version    # Should print Python 3.11.x
adb --version            # Should print Android Debug Bridge version
fastboot --version       # Should print fastboot version
git --version            # Should print git version
```

---

## Step 3: Set Up bkerler/edl

The **bkerler/edl** tool is how your Mac communicates with your Portal in EDL (Emergency Download) mode. This is the single most important tool in the entire project.

Run the setup script:

```bash
./scripts/setup/setup_bkerler_edl.sh
```

What this script does behind the scenes:

1. Clones the [bkerler/edl](https://github.com/bkerler/edl) repository into `tools/edl/`
2. Creates a Python virtual environment at `tools/edl/venv/`
3. Installs all Python dependencies inside that virtual environment

If you prefer to do it manually:

```bash
# Clone the repository
git clone https://github.com/bkerler/edl.git tools/edl

# Create and activate a virtual environment
python3.11 -m venv tools/edl/venv
source tools/edl/venv/bin/activate

# Install dependencies
cd tools/edl
pip install -r requirements.txt
pip install .

# Deactivate when done
deactivate
```

> **Note:** The virtual environment keeps the EDL tool's Python packages isolated from your system Python. You do not need to activate it manually -- the project scripts handle this automatically.

---

## Step 4: Install Docker Desktop (Optional)

Docker is only needed if you plan to use **magiskboot** for repacking boot images. If you are just exploring and analyzing firmware, you can skip this step and come back later.

1. Download Docker Desktop from [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/)
2. Open the `.dmg` file and drag Docker to Applications
3. Launch Docker Desktop from Applications
4. Wait for Docker to finish starting (the whale icon in the menu bar will stop animating)

Verify Docker is running:

```bash
docker --version        # Should print Docker version
docker run hello-world  # Should print "Hello from Docker!"
```

---

## Step 5: Build the magiskboot Docker Image (Optional)

Only do this step if you completed Step 4.

```bash
docker build -t magiskboot tools/docker/
```

This builds a container image with `magiskboot` pre-installed. The build may take a few minutes.

Verify it built:

```bash
docker images | grep magiskboot
```

You should see a row with `magiskboot` in the REPOSITORY column.

---

## Step 6: Verify Everything Works

Run the verification script to check that all tools are properly installed:

```bash
./scripts/setup/verify_environment.sh
```

This script checks for every required tool and reports pass/fail for each one. A successful run looks like:

```
[PASS] Homebrew found
[PASS] Python 3.11 found
[PASS] libusb found
[PASS] adb found
[PASS] fastboot found
[PASS] git found
[PASS] wget found
[PASS] bkerler/edl installed
[SKIP] Docker not installed (optional)
[SKIP] magiskboot image not built (optional)

Environment is ready!
```

If Docker is installed, those lines will show `[PASS]` instead of `[SKIP]`.

---

## Troubleshooting

### libusb Issues on Apple Silicon (M1/M2/M3/M4)

If you get errors about `libusb` not being found, Homebrew on Apple Silicon installs to `/opt/homebrew/` instead of `/usr/local/`. Fix:

```bash
# Add this to your ~/.zshrc
export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"
```

Then reload your shell:

```bash
source ~/.zshrc
```

### Python Version Conflicts

If `python3` points to a different version (like 3.12 or 3.10), be explicit:

```bash
# Always use python3.11 directly
python3.11 --version

# If the EDL venv was created with the wrong Python, recreate it:
rm -rf tools/edl/venv
python3.11 -m venv tools/edl/venv
source tools/edl/venv/bin/activate
pip install -r tools/edl/requirements.txt
pip install .
deactivate
```

### Docker Memory Settings

If Docker builds fail or containers crash, increase Docker's memory allocation:

1. Open Docker Desktop
2. Go to Settings (gear icon) > Resources
3. Increase Memory to at least **4 GB**
4. Click "Apply & Restart"

### Homebrew "Command Not Found"

If `brew` is not found after installation, your PATH is not set up. Run:

```bash
# For Apple Silicon Macs:
eval "$(/opt/homebrew/bin/brew shellenv)"

# For Intel Macs:
eval "$(/usr/local/bin/brew shellenv)"
```

Then add the appropriate line to your `~/.zshrc` so it persists.

---

## What's Next?

Your environment is ready. Here is the recommended order for the remaining guides:

1. **[Guide 01: Entering EDL Mode](01_entering_edl_mode.md)** -- learn to put your Portal into diagnostic mode
2. **[Guide 02: Entering Fastboot Mode](02_entering_fastboot_mode.md)** -- learn the bootloader interface
3. **[Guide 03: Downloading Firmware](03_firmware_download.md)** -- grab firmware for offline study
4. **[Guide 04: Offline Firmware Analysis](04_offline_firmware_analysis.md)** -- the most valuable zero-risk activity
