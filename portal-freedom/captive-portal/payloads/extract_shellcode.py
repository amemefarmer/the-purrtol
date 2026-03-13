#!/usr/bin/env python3
"""Extract .text / __text section from compiled object file and generate JS byte array."""
import struct
import sys
import os

def extract_from_elf(data):
    """Extract .text section from ELF object file."""
    fmt = '<' if data[5] == 1 else '>'
    e_shoff = struct.unpack(fmt+'Q', data[40:48])[0]
    e_shentsize = struct.unpack(fmt+'H', data[58:60])[0]
    e_shnum = struct.unpack(fmt+'H', data[60:62])[0]
    e_shstrndx = struct.unpack(fmt+'H', data[62:64])[0]
    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_name = struct.unpack(fmt+'I', data[off:off+4])[0]
        sh_offset = struct.unpack(fmt+'Q', data[off+24:off+32])[0]
        sh_size = struct.unpack(fmt+'Q', data[off+32:off+40])[0]
        sections.append((sh_name, sh_offset, sh_size))
    strtab_off = sections[e_shstrndx][1]
    strtab_sz = sections[e_shstrndx][2]
    strtab = data[strtab_off:strtab_off+strtab_sz]
    for sh_name, sh_offset, sh_size in sections:
        name_end = strtab.index(b'\x00', sh_name)
        name = strtab[sh_name:name_end].decode()
        if name == '.text':
            return data[sh_offset:sh_offset+sh_size]
    return None

def extract_from_macho(data):
    """Extract __text section from Mach-O object file."""
    ncmds = struct.unpack('<I', data[16:20])[0]
    offset = 32  # Skip mach_header_64
    for i in range(ncmds):
        cmd = struct.unpack('<I', data[offset:offset+4])[0]
        cmdsize = struct.unpack('<I', data[offset+4:offset+8])[0]
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack('<I', data[offset+64:offset+68])[0]
            sect_offset = offset + 72
            for j in range(nsects):
                sectname = data[sect_offset:sect_offset+16].rstrip(b'\x00').decode()
                sect_off = struct.unpack('<I', data[sect_offset+48:sect_offset+52])[0]
                sect_size = struct.unpack('<Q', data[sect_offset+40:sect_offset+48])[0]
                if sectname == '__text':
                    return data[sect_off:sect_off+sect_size]
                sect_offset += 80
        offset += cmdsize
    return None

def main():
    obj_file = sys.argv[1] if len(sys.argv) > 1 else 'shellcode.o'
    bin_file = sys.argv[2] if len(sys.argv) > 2 else 'shellcode.bin'
    js_file = sys.argv[3] if len(sys.argv) > 3 else 'shellcode_bytes.js'

    with open(obj_file, 'rb') as f:
        data = f.read()

    text = None
    if data[:4] == b'\x7fELF':
        text = extract_from_elf(data)
    elif struct.unpack('<I', data[:4])[0] == 0xFEEDFACF:
        text = extract_from_macho(data)
    else:
        print(f"Unknown object format: {data[:4].hex()}", file=sys.stderr)
        sys.exit(1)

    if text is None:
        print("Could not find text section", file=sys.stderr)
        sys.exit(1)

    # Write raw binary
    with open(bin_file, 'wb') as f:
        f.write(text)
    print(f"Shellcode binary: {bin_file} ({len(text)} bytes)")

    # Find _data offset (look for path string)
    path_bytes = b'/data/local/tmp/s2'
    data_offset = -1
    try:
        path_idx = text.index(path_bytes)
        data_offset = path_idx - 16  # _data is 16 bytes before path
        print(f"_data section at offset {data_offset} (0x{data_offset:x})")
        print(f"path string at offset {path_idx} (0x{path_idx:x})")
    except ValueError:
        print("WARNING: could not find path string in shellcode")

    # Generate JavaScript
    with open(js_file, 'w') as f:
        f.write(f"// Auto-generated from {obj_file}\n")
        f.write(f"// Size: {len(text)} bytes\n")
        if data_offset > 0:
            f.write(f"// _data offset: {data_offset} (0x{data_offset:x})\n")
        f.write(f"const SHELLCODE_SIZE = {len(text)};\n")
        if data_offset > 0:
            f.write(f"const SHELLCODE_DATA_OFFSET = {data_offset};\n")
        else:
            f.write(f"const SHELLCODE_DATA_OFFSET = -1;\n")
        f.write("const SHELLCODE = new Uint8Array([\n")
        for i in range(0, len(text), 16):
            chunk = text[i:i+16]
            hex_str = ', '.join(f'0x{b:02x}' for b in chunk)
            f.write(f"    {hex_str},\n")
        f.write("]);\n")
    print(f"JavaScript array: {js_file}")

if __name__ == '__main__':
    main()
