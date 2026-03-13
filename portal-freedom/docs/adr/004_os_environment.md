# ADR-004: OS Environment

**Status:** Accepted
**Date:** 2026-02-24
**Deciders:** Project owner

## Context

The user's development environment:

| Property | Value |
|---|---|
| OS | macOS (Darwin 25.2.0) |
| Architecture | Apple Silicon (ARM64) |
| Shell | zsh |
| Package Manager | Homebrew |

The project requires the following tool categories:

1. **EDL communication:** bkerler/edl (Python, cross-platform)
2. **Android platform tools:** adb, fastboot (available via Homebrew)
3. **USB device access:** libusb (available via Homebrew)
4. **Firmware analysis:** binwalk, file, strings, hexdump (available via Homebrew or built-in)
5. **Boot image manipulation:** magiskboot (part of Magisk, for unpacking/repacking Android boot images)
6. **Partition/image tools:** simg2img, lpunpack (available via android-platform-tools or standalone builds)

Most tools run natively on macOS ARM64. The notable exception is **magiskboot**, which does not have an official native macOS ARM64 build. The Magisk project provides Linux x86_64 and Android ARM64 binaries, but no macOS build.

### Options for magiskboot

| Option | Pros | Cons |
|---|---|---|
| Docker (Linux ARM64 container) | Clean, reproducible, no host pollution | Requires Docker Desktop (~2GB), slight startup overhead |
| Cross-compile from source | Native speed, no Docker dependency | Complex build process, may have issues with macOS-specific APIs |
| Linux VM | Full Linux environment | Heavy (4GB+ RAM), unnecessary for one tool |
| Rosetta 2 + Linux x86_64 binary | Simple | May not work, Rosetta translates macOS Mach-O not Linux ELF |

## Decision

Use **native macOS** for all tools except magiskboot, which will run via **Docker** (Linux ARM64 container).

### Native macOS Tools

```bash
# Android platform tools (adb, fastboot)
brew install android-platform-tools

# USB access
brew install libusb

# Python and EDL tool
brew install python
pip3 install edl

# Firmware analysis
brew install binwalk
# file, strings, hexdump are built into macOS
```

### Docker for magiskboot

```bash
# Install Docker Desktop for Mac (Apple Silicon)
brew install --cask docker

# Run magiskboot in a Linux ARM64 container
# (Dockerfile and wrapper script provided in tools/docker/)
```

A lightweight Alpine Linux ARM64 container will be used, with magiskboot installed from the Magisk release artifacts. A wrapper script will be provided so the user can run `./magiskboot.sh unpack boot.img` as if it were a native command.

## Consequences

- **Positive:** Minimal overhead. No VM management. Native performance for 95% of operations. Docker container is lightweight and reproducible. Homebrew handles dependencies cleanly. No Windows VM or USB passthrough issues.
- **Negative:** Docker Desktop requires ~2GB disk and has a background daemon. First-time Docker pull adds a one-time delay. Users unfamiliar with Docker have a small learning curve.
- **Mitigation:** Wrapper scripts abstract Docker commands. Setup script validates all dependencies. Docker is only needed for boot image manipulation, which comes later in the workflow.

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| Full Linux VM (UTM/Parallels) | Unnecessary overhead for the toolset needed. USB passthrough adds risk. Only magiskboot needs Linux. |
| Windows VM for QPST + tools | USB passthrough unreliable for QDLoader 9008. Most tools have macOS equivalents. |
| Dual-boot Linux | Overkill. Requires repartitioning. Apple Silicon Linux support is maturing but still has rough edges. |
| Asahi Linux | Promising but still lacks full hardware support. Not appropriate for a project that needs reliable USB and Docker. |
| WSL2 via Parallels | Nested virtualization. Unnecessarily complex. |

## References

- Homebrew: https://brew.sh
- Docker Desktop for Mac: https://www.docker.com/products/docker-desktop
- android-platform-tools (Homebrew): `brew info android-platform-tools`
- Magisk GitHub releases: https://github.com/topjohnwu/Magisk/releases
- bkerler/edl: https://github.com/bkerler/edl
