#!/usr/bin/env python3
"""
Deep analysis of LinuxLoader-terry.efi for Portal exploit adaptation.
Identifies critical offsets needed for CVE-2021-1931 exploit.

Reference: xperable target-p114.c (Sony MSM8998) offsets:
  - exploit_continue:     0x28DC8 (stage1_cont)
  - download_buf_ptr:     0xFB658
  - bl_state_struct:      0xF3B78
  - FAIL_response_ret:    0x28E64
  - oem_unlock_handler:   0x4D9E4
  - erase_handler:        0x28298
  - flash_handler_area:   0x264A4
  - download_finished:    0x24B3C
  - debug_log_check:      0x07CE8
  - boot_cmd_handler:     0x286DC
  - VerifiedBootDxe skip: 0x25FC (in VB module)
  - code_boundary:        0xe7000
"""

import pefile
import struct
import sys
import os
import json
from collections import defaultdict

EFI_PATH = "/Users/vibebox/Documents/Facebook_Portal/portal-freedom/firmware/LinuxLoader-terry.efi"
OUT_DIR = "/Users/vibebox/Documents/Facebook_Portal/portal-freedom/firmware/analysis"

def main():
    with open(EFI_PATH, 'rb') as f:
        data = f.read()

    pe = pefile.PE(EFI_PATH)

    results = {}

    # ==================== PE HEADER ANALYSIS ====================
    print("=" * 80)
    print("PE HEADER ANALYSIS: LinuxLoader-terry.efi")
    print("=" * 80)

    print(f"\nFile size: {len(data)} bytes (0x{len(data):x})")
    print(f"Machine: 0x{pe.FILE_HEADER.Machine:x} ({'AArch64' if pe.FILE_HEADER.Machine == 0xAA64 else 'Unknown'})")
    print(f"Number of sections: {pe.FILE_HEADER.NumberOfSections}")
    print(f"Image base: 0x{pe.OPTIONAL_HEADER.ImageBase:x}")
    print(f"Entry point (RVA): 0x{pe.OPTIONAL_HEADER.AddressOfEntryPoint:x}")
    print(f"Section alignment: 0x{pe.OPTIONAL_HEADER.SectionAlignment:x}")
    print(f"File alignment: 0x{pe.OPTIONAL_HEADER.FileAlignment:x}")
    print(f"Image size: 0x{pe.OPTIONAL_HEADER.SizeOfImage:x}")

    results['pe_info'] = {
        'file_size': len(data),
        'machine': hex(pe.FILE_HEADER.Machine),
        'image_base': hex(pe.OPTIONAL_HEADER.ImageBase),
        'entry_point_rva': hex(pe.OPTIONAL_HEADER.AddressOfEntryPoint),
        'image_size': hex(pe.OPTIONAL_HEADER.SizeOfImage),
    }

    print("\n--- SECTIONS ---")
    sections = {}
    for section in pe.sections:
        name = section.Name.decode('ascii', errors='replace').rstrip('\x00')
        print(f"  {name:10s}  VA=0x{section.VirtualAddress:06x}  "
              f"VSize=0x{section.Misc_VirtualSize:06x}  "
              f"RawOff=0x{section.PointerToRawData:06x}  "
              f"RawSize=0x{section.SizeOfRawData:06x}  "
              f"Chars=0x{section.Characteristics:08x}")
        sections[name] = {
            'va': section.VirtualAddress,
            'vsize': section.Misc_VirtualSize,
            'raw_offset': section.PointerToRawData,
            'raw_size': section.SizeOfRawData,
            'characteristics': hex(section.Characteristics),
        }
    results['sections'] = sections

    # Get section data
    text_section = None
    data_section = None
    for section in pe.sections:
        name = section.Name.decode('ascii', errors='replace').rstrip('\x00')
        if name == '.text':
            text_section = section
        elif name == '.data':
            data_section = section

    if text_section:
        text_data = data[text_section.PointerToRawData:text_section.PointerToRawData + text_section.SizeOfRawData]
        text_va = text_section.VirtualAddress
        print(f"\n.text code boundary: 0x{text_section.VirtualAddress + text_section.Misc_VirtualSize:x}")
        results['code_boundary'] = hex(text_section.VirtualAddress + text_section.Misc_VirtualSize)

    if data_section:
        data_sect_data = data[data_section.PointerToRawData:data_section.PointerToRawData + data_section.SizeOfRawData]
        data_va = data_section.VirtualAddress

    # ==================== STRING EXTRACTION ====================
    print("\n" + "=" * 80)
    print("STRING ANALYSIS")
    print("=" * 80)

    # Extract all printable strings >= 4 chars
    strings = []
    current = b""
    current_offset = 0
    for i, b in enumerate(data):
        if 0x20 <= b < 0x7f:
            if not current:
                current_offset = i
            current += bytes([b])
        else:
            if len(current) >= 4:
                try:
                    s = current.decode('ascii')
                    # Convert file offset to RVA
                    rva = pe.get_rva_from_offset(current_offset) if current_offset < len(data) else None
                    strings.append((current_offset, rva, s))
                except:
                    pass
            current = b""
            current_offset = 0

    # Save all strings
    with open(os.path.join(OUT_DIR, "all_strings.txt"), 'w') as f:
        for off, rva, s in strings:
            rva_str = f"0x{rva:06x}" if rva is not None else "N/A"
            f.write(f"FileOff=0x{off:06x}  RVA={rva_str}  {s}\n")
    print(f"Total strings extracted: {len(strings)} (saved to all_strings.txt)")

    # Categorize key strings
    categories = {
        'fastboot_commands': ['download', 'flash:', 'erase:', 'boot', 'getvar:', 'continue', 'reboot',
                              'oem ', 'flashing ', 'set_active'],
        'error_messages': ['not allowed', 'unknown command', 'No such partition', 'FAILED',
                          'error', 'Invalid', 'Command not allowed'],
        'lock_state': ['unlock', 'locked', 'Unlocked', 'is_unlocked', 'lock_state',
                       'DeviceInfo', 'device_info', 'Unsealed', 'sealed'],
        'boot_flow': ['Download Finished', 'Fastboot', 'Processing commands',
                      'androidboot', 'force_enable_usb_adb', 'developer mode',
                      'LinuxLoader', 'VerifiedBoot', 'dm-verity'],
        'format_strings': ['%s', '%d', '%x', '%p', '%llx', '%08x'],
        'uefi_functions': ['AllocatePool', 'AllocatePages', 'FreePool', 'FreePages',
                           'HandleProtocol', 'LocateProtocol', 'InstallProtocol',
                           'gBS', 'gRT', 'gST', 'EFI_'],
        'portal_specific': ['Portal', 'aloha', 'ohana', 'terry', 'cipher', 'atlas',
                           'facebook', 'PortalLib', 'portal'],
        'memory_ops': ['memcpy', 'memset', 'memmove', 'CopyMem', 'SetMem', 'ZeroMem'],
    }

    categorized = defaultdict(list)
    for off, rva, s in strings:
        for cat, keywords in categories.items():
            for kw in keywords:
                if kw.lower() in s.lower():
                    rva_str = f"0x{rva:06x}" if rva is not None else "N/A"
                    categorized[cat].append((off, rva, s[:120]))
                    break

    for cat, items in sorted(categorized.items()):
        print(f"\n--- {cat.upper()} ({len(items)} matches) ---")
        for off, rva, s in items[:30]:  # Limit output
            rva_str = f"0x{rva:06x}" if rva is not None else "N/A"
            print(f"  FileOff=0x{off:06x}  RVA={rva_str}  \"{s}\"")
        if len(items) > 30:
            print(f"  ... and {len(items) - 30} more")

    # ==================== FASTBOOT COMMAND TABLE SEARCH ====================
    print("\n" + "=" * 80)
    print("FASTBOOT COMMAND TABLE SEARCH")
    print("=" * 80)

    # Key fastboot command strings and their file offsets
    cmd_strings = {}
    for off, rva, s in strings:
        # Look for exact fastboot command strings
        clean = s.strip()
        if clean in ['download', 'flash:', 'erase:', 'boot', 'getvar:', 'continue',
                     'reboot', 'reboot-bootloader', 'oem', 'set_active:',
                     'flashing', 'upload']:
            if rva is not None:
                cmd_strings[clean] = (off, rva)
                print(f"  CMD string '{clean}' at FileOff=0x{off:06x} RVA=0x{rva:06x}")

    # Also look for the OEM subcommands
    oem_cmds = {}
    for off, rva, s in strings:
        clean = s.strip()
        if clean.startswith('get_unlock_bootloader_nonce') or \
           clean.startswith('device-info') or \
           clean.startswith('soc-serialno') or \
           clean.startswith('seal-for-ship') or \
           clean.startswith('adb-lock') or \
           clean.startswith('battery-') or \
           clean.startswith('get-batt-cap') or \
           clean.startswith('get_unlock_ability') or \
           clean.startswith('unlock_bootloader') or \
           clean.startswith('unlock_critical') or \
           clean.startswith('lock_critical') or \
           clean == 'unlock' or clean == 'lock':
            if rva is not None:
                oem_cmds[clean] = (off, rva)
                print(f"  OEM/flashing cmd '{clean}' at FileOff=0x{off:06x} RVA=0x{rva:06x}")

    results['cmd_strings'] = {k: hex(v[1]) for k, v in cmd_strings.items()}
    results['oem_cmds'] = {k: hex(v[1]) for k, v in oem_cmds.items()}

    # ==================== POINTER TABLE SEARCH ====================
    print("\n" + "=" * 80)
    print("POINTER TABLE SEARCH (command dispatch tables)")
    print("=" * 80)

    # In UEFI fastboot, the command table is typically an array of:
    # { char *name, void (*handler)(void*) }
    # So we look for RVA pointers to known command strings in the .data section

    if data_section:
        print(f"\nSearching .data section (VA=0x{data_va:x}, size=0x{data_section.Misc_VirtualSize:x})...")

        # For each known command string RVA, search for 8-byte pointers in .data
        for cmd_name, (cmd_off, cmd_rva) in sorted(cmd_strings.items(), key=lambda x: x[1][1]):
            # Search for this RVA as a 64-bit little-endian pointer
            target_bytes = struct.pack('<Q', cmd_rva)
            pos = 0
            while True:
                idx = data_sect_data.find(target_bytes, pos)
                if idx == -1:
                    break
                ptr_rva = data_va + idx
                # The handler function pointer should be right after (or before) the string pointer
                if idx + 8 < len(data_sect_data):
                    handler_ptr = struct.unpack('<Q', data_sect_data[idx+8:idx+16])[0]
                    print(f"  CMD '{cmd_name}' ptr at RVA=0x{ptr_rva:06x}, "
                          f"handler candidate at 0x{handler_ptr:06x}")
                if idx >= 8:
                    prev_ptr = struct.unpack('<Q', data_sect_data[idx-8:idx])[0]
                    if 0x1000 <= prev_ptr <= 0x95000:  # Within .text section
                        print(f"  CMD '{cmd_name}' ptr at RVA=0x{ptr_rva:06x}, "
                              f"prev entry handler at 0x{prev_ptr:06x}")
                pos = idx + 1

    # Also search in .text for ADRP+ADD patterns loading string addresses
    # AArch64 ADRP: bits [31:24] = 1x01_0000, imm = bits[23:5] << 12 | bits[30:29] << 12
    # AArch64 ADD:  bits [31:22] = 1001_0001_0x

    print("\n--- ADRP+ADD patterns referencing key strings ---")
    if text_section:
        # For each key string, find code references using ADRP+ADD pair
        key_rvas = {}
        for off, rva, s in strings:
            if rva is not None:
                for kw in ['download', 'flash:', 'unknown command', 'Flashing is not allowed',
                          'Download Finished', 'No such partition', 'Fastboot: Processing commands',
                          'oem device-info', 'androidboot.force_enable_usb_adb',
                          'Portal is starting up in developer mode']:
                    if s.startswith(kw):
                        key_rvas[kw] = rva
                        break

        print(f"\n  Key string RVAs to search for:")
        for kw, rva in sorted(key_rvas.items(), key=lambda x: x[1]):
            print(f"    '{kw}' -> RVA 0x{rva:06x} (page=0x{rva & ~0xfff:06x}, offset=0x{rva & 0xfff:03x})")

        # Scan .text for ADRP instructions
        # ADRP format: [31] op=1, [30:29] immlo, [28:24] 10000, [23:5] immhi, [4:0] Rd
        adrp_refs = defaultdict(list)
        for i in range(0, len(text_data) - 4, 4):
            insn = struct.unpack('<I', text_data[i:i+4])[0]
            # Check if ADRP: bits[28:24] == 10000 and bit[31] == 1
            if (insn & 0x9F000000) == 0x90000000:
                rd = insn & 0x1f
                immhi = (insn >> 5) & 0x7ffff
                immlo = (insn >> 29) & 0x3
                imm = (immhi << 2) | immlo
                # Sign extend 21-bit value
                if imm & (1 << 20):
                    imm -= (1 << 21)

                pc = text_va + i
                page_addr = (pc & ~0xfff) + (imm << 12)

                # Check if this page matches any of our key strings
                for kw, target_rva in key_rvas.items():
                    target_page = target_rva & ~0xfff
                    if page_addr == target_page:
                        # Check next instruction for ADD with the right page offset
                        if i + 4 < len(text_data):
                            next_insn = struct.unpack('<I', text_data[i+4:i+8])[0]
                            # ADD Xd, Xn, #imm12: [31:22] = 1001_0001_00, [21:10] = imm12, [9:5] = Rn, [4:0] = Rd
                            if (next_insn & 0xFFC00000) == 0x91000000:
                                add_rd = next_insn & 0x1f
                                add_rn = (next_insn >> 5) & 0x1f
                                add_imm = (next_insn >> 10) & 0xfff
                                if add_rn == rd:  # Same register
                                    full_addr = page_addr + add_imm
                                    if full_addr == target_rva:
                                        code_rva = text_va + i
                                        adrp_refs[kw].append(code_rva)
                                        print(f"\n  XREF: '{kw}' referenced at code RVA 0x{code_rva:06x}")
                                        print(f"    ADRP x{rd}, #0x{page_addr:x} ; ADD x{add_rd}, x{add_rn}, #0x{add_imm:x}")

        results['string_xrefs'] = {k: [hex(v) for v in vs] for k, vs in adrp_refs.items()}

    # ==================== DOWNLOAD HANDLER ANALYSIS ====================
    print("\n" + "=" * 80)
    print("DOWNLOAD HANDLER ANALYSIS (CVE-2021-1931 target)")
    print("=" * 80)

    # The download command handler is where the overflow happens.
    # In xperable, the key is the fastboot_download_512MB_buffer_ptr
    # Look for patterns that reference the download buffer

    # Search for "download" string references in code
    if 'download' in adrp_refs:
        for ref_addr in adrp_refs['download']:
            offset_in_text = ref_addr - text_va
            # Print surrounding instructions (10 before, 20 after)
            start = max(0, offset_in_text - 40)
            end = min(len(text_data), offset_in_text + 80)
            print(f"\n  Code around download reference at 0x{ref_addr:06x}:")
            for j in range(start, end, 4):
                insn = struct.unpack('<I', text_data[j:j+4])[0]
                addr = text_va + j
                marker = " <---" if j == offset_in_text else ""
                print(f"    0x{addr:06x}: {insn:08x}{marker}")

    if 'Download Finished' in adrp_refs:
        for ref_addr in adrp_refs['Download Finished']:
            offset_in_text = ref_addr - text_va
            start = max(0, offset_in_text - 80)
            end = min(len(text_data), offset_in_text + 40)
            print(f"\n  Code around 'Download Finished' reference at 0x{ref_addr:06x}:")
            for j in range(start, end, 4):
                insn = struct.unpack('<I', text_data[j:j+4])[0]
                addr = text_va + j
                marker = " <---" if j == offset_in_text else ""
                print(f"    0x{addr:06x}: {insn:08x}{marker}")

    # ==================== BL (Branch-Link) PATTERN ANALYSIS ====================
    print("\n" + "=" * 80)
    print("FUNCTION CALL DENSITY (BL instruction hotspots)")
    print("=" * 80)

    # Count BL instructions per 0x1000 byte region
    bl_density = defaultdict(int)
    if text_section:
        for i in range(0, len(text_data) - 4, 4):
            insn = struct.unpack('<I', text_data[i:i+4])[0]
            # BL: bits[31:26] = 100101
            if (insn & 0xFC000000) == 0x94000000:
                region = (text_va + i) & ~0xfff
                bl_density[region] += 1

        # Show top regions (likely main function areas)
        top_regions = sorted(bl_density.items(), key=lambda x: -x[1])[:20]
        for region, count in top_regions:
            print(f"  Region 0x{region:06x}: {count} BL calls")

    # ==================== SPECIFIC PATTERN SEARCHES ====================
    print("\n" + "=" * 80)
    print("SPECIFIC EXPLOIT-RELEVANT PATTERNS")
    print("=" * 80)

    # 1. Search for the "No such partition" error handler
    #    In p114, "flash:fb" triggers this, and the exploit patches code at 0x26560
    if 'No such partition' in adrp_refs:
        print(f"\n  'No such partition' references: {[hex(x) for x in adrp_refs['No such partition']]}")

    # 2. Search for the "Flashing is not allowed" error
    #    In p114, this is near 0x264D0
    if 'Flashing is not allowed' in adrp_refs:
        print(f"\n  'Flashing is not allowed' references: {[hex(x) for x in adrp_refs['Flashing is not allowed']]}")

    # 3. Search for "unknown command" handler
    #    This is the default case in the fastboot command dispatch
    if 'unknown command' in adrp_refs:
        print(f"\n  'unknown command' references: {[hex(x) for x in adrp_refs['unknown command']]}")

    # 4. Look for STP X29, X30 (function prologues) to identify function boundaries
    print("\n--- Function prologues (STP X29, X30, [SP, ...]) ---")
    func_starts = []
    if text_section:
        for i in range(0, len(text_data) - 4, 4):
            insn = struct.unpack('<I', text_data[i:i+4])[0]
            # STP X29, X30, [SP, #-N]! pre-index
            # Format: x010_1001_11xx_xxxx_x111_1011_1110_1xxx
            # More specifically: STP x29, x30, [sp, #imm]! = A9Bxxxxx or A9Axxxxx pattern
            if (insn & 0xFFE07FFF) == 0xA9007BFD or \
               (insn & 0xFFC07FFF) == 0xA9807BFD:
                func_starts.append(text_va + i)

    print(f"  Found {len(func_starts)} potential function starts")
    results['function_count'] = len(func_starts)

    # Find functions near key string references
    for kw, refs in adrp_refs.items():
        for ref in refs:
            # Find the nearest function start before this reference
            nearest = None
            for fs in func_starts:
                if fs <= ref:
                    nearest = fs
                else:
                    break
            if nearest:
                print(f"  '{kw}' at 0x{ref:06x} is in function starting at 0x{nearest:06x} (offset +0x{ref-nearest:x})")

    # ==================== SPECIFIC OPCODE PATTERN SEARCH ====================
    print("\n" + "=" * 80)
    print("OPCODE PATTERN SEARCH")
    print("=" * 80)

    # Search for the xperable-specific signature: code B3 ED FF 97
    # This is the BL to the FAIL response handler
    # In p114 test2/test3, it searches for this pattern to find the return address
    pattern_97FFED_B3 = bytes([0xB3, 0xED, 0xFF, 0x97])  # bl #-0x97ff*4 + offset

    if text_section:
        # More general: look for BL instructions with large negative offsets
        # (which point to common utility functions at the start of .text)
        print("\n  Searching for BL to FAIL response pattern...")
        for i in range(0, len(text_data) - 4, 4):
            insn = struct.unpack('<I', text_data[i:i+4])[0]
            if (insn & 0xFC000000) == 0x94000000:  # BL
                offset26 = insn & 0x03FFFFFF
                if offset26 & (1 << 25):  # Sign extend
                    offset26 -= (1 << 26)
                target = (text_va + i) + (offset26 * 4)
                # Look for calls to very low addresses (common utility functions)
                # The FAIL response function should be a commonly called function

    # 5. Search for "0x200" constant (used in p114 test4 to detect alternate code path)
    # CMP W1, #0x200 = 3f 00 08 71
    pattern_cmp_200 = bytes([0x3f, 0x00, 0x08, 0x71])
    print(f"\n  Searching for 'CMP w1, #0x200' pattern...")
    if text_section:
        pos = 0
        while True:
            idx = text_data.find(pattern_cmp_200, pos)
            if idx == -1:
                break
            code_rva = text_va + idx
            print(f"    Found at RVA 0x{code_rva:06x}")
            pos = idx + 4

    # 6. Search for LDR patterns that look like buffer pointer loads
    # In p114: ldr x0, [x22, #0x38] loads the download buffer ptr
    # Pattern: C0 1E 40 F9 = ldr x0, [x22, #0x38]
    print(f"\n  Searching for 'LDR x0, [x22, #0x38]' (download buf ptr pattern)...")
    pattern_ldr_x22_38 = bytes([0xC0, 0x1E, 0x40, 0xF9])
    if text_section:
        pos = 0
        while True:
            idx = text_data.find(pattern_ldr_x22_38, pos)
            if idx == -1:
                break
            code_rva = text_va + idx
            print(f"    Found at RVA 0x{code_rva:06x}")
            pos = idx + 4

    # 7. Search for MOV W0, #1 pattern (common in unlock handlers)
    # 20 00 80 52 = mov w0, #1
    print(f"\n  Searching for 'MOV W0, #1' pattern (common in lock state set)...")
    pattern_mov_w0_1 = bytes([0x20, 0x00, 0x80, 0x52])
    count = 0
    if text_section:
        pos = 0
        while True:
            idx = text_data.find(pattern_mov_w0_1, pos)
            if idx == -1:
                break
            count += 1
            pos = idx + 4
        print(f"    Found {count} occurrences")

    # 8. Search for STRB pattern near "is_unlocked" state writes
    # strb w2, [x1, #13] = 22 34 00 39 (used in p114 oem unlock)
    print(f"\n  Searching for 'STRB w2, [x1, #13]' (lock state write pattern)...")
    pattern_strb_w2_x1_13 = bytes([0x22, 0x34, 0x00, 0x39])
    if text_section:
        pos = 0
        while True:
            idx = text_data.find(pattern_strb_w2_x1_13, pos)
            if idx == -1:
                break
            code_rva = text_va + idx
            print(f"    Found at RVA 0x{code_rva:06x}")
            pos = idx + 4

    # ==================== RELOCATION TABLE ANALYSIS ====================
    print("\n" + "=" * 80)
    print("RELOCATION TABLE ANALYSIS")
    print("=" * 80)

    if hasattr(pe, 'DIRECTORY_ENTRY_BASERELOC'):
        total_relocs = 0
        for entry in pe.DIRECTORY_ENTRY_BASERELOC:
            total_relocs += len(entry.entries)
        print(f"  Total relocations: {total_relocs}")
        print(f"  Reloc blocks: {len(pe.DIRECTORY_ENTRY_BASERELOC)}")
    else:
        print("  No base relocations found")

    # ==================== DATA SECTION POINTER ANALYSIS ====================
    print("\n" + "=" * 80)
    print("DATA SECTION POINTER ANALYSIS")
    print("=" * 80)

    if data_section:
        # Scan .data for pointers that fall within .text section
        text_start = text_section.VirtualAddress if text_section else 0
        text_end = text_start + text_section.Misc_VirtualSize if text_section else 0

        code_ptrs = []
        for i in range(0, len(data_sect_data) - 8, 8):
            val = struct.unpack('<Q', data_sect_data[i:i+8])[0]
            if text_start <= val < text_end:
                ptr_rva = data_va + i
                code_ptrs.append((ptr_rva, val))

        print(f"  Found {len(code_ptrs)} pointers into .text from .data")

        # Look for clusters of code pointers (likely dispatch tables)
        if code_ptrs:
            print("\n  Pointer clusters (potential dispatch tables):")
            cluster_start = code_ptrs[0]
            cluster = [code_ptrs[0]]
            for j in range(1, len(code_ptrs)):
                if code_ptrs[j][0] - code_ptrs[j-1][0] <= 32:  # Within 32 bytes
                    cluster.append(code_ptrs[j])
                else:
                    if len(cluster) >= 3:
                        print(f"\n    Cluster at 0x{cluster[0][0]:06x} ({len(cluster)} entries):")
                        for ptr_rva, target_rva in cluster[:20]:
                            print(f"      [0x{ptr_rva:06x}] -> 0x{target_rva:06x}")
                        if len(cluster) > 20:
                            print(f"      ... and {len(cluster) - 20} more")
                    cluster = [code_ptrs[j]]
            # Last cluster
            if len(cluster) >= 3:
                print(f"\n    Cluster at 0x{cluster[0][0]:06x} ({len(cluster)} entries):")
                for ptr_rva, target_rva in cluster[:20]:
                    print(f"      [0x{ptr_rva:06x}] -> 0x{target_rva:06x}")

    # ==================== INTERESTING CONSTANT SEARCH ====================
    print("\n" + "=" * 80)
    print("INTERESTING CONSTANTS")
    print("=" * 80)

    # Search for 0x20000000 (512MB download buffer size)
    for name, pattern in [
        ("0x20000000 (512MB)", struct.pack('<I', 0x20000000)),
        ("0x10000000 (256MB)", struct.pack('<I', 0x10000000)),
        ("512MB as 64-bit", struct.pack('<Q', 0x20000000)),
    ]:
        pos = 0
        while True:
            idx = data.find(pattern, pos)
            if idx == -1:
                break
            rva = pe.get_rva_from_offset(idx) if idx < len(data) else None
            rva_str = f"0x{rva:06x}" if rva else "N/A"
            print(f"  {name} at FileOff=0x{idx:06x} RVA={rva_str}")
            pos = idx + len(pattern)

    # ==================== SAVE RESULTS ====================
    with open(os.path.join(OUT_DIR, "analysis_results.json"), 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n\nResults saved to {OUT_DIR}/analysis_results.json")
    print(f"Full strings saved to {OUT_DIR}/all_strings.txt")
    print("\n" + "=" * 80)
    print("ANALYSIS COMPLETE")
    print("=" * 80)

if __name__ == '__main__':
    main()
