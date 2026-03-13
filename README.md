# The PurrTol

An 18-day AI-assisted reverse engineering project to root a discontinued Facebook Portal+ 15.6" Gen 1 into an interactive cat toy. Reached 85% completion before Claude (Anthropic) refused to continue.

**[Read the full story &rarr;](https://amemefarmer.github.io/the-purrtol/)**

## What happened

A human and an AI spent 18 days reverse-engineering a Facebook Portal — a smart display Meta abandoned in 2022. The goal: repurpose it as a cat toy with a touch-reactive screen, chirping sounds, and camera-based movement tracking. All local, no cloud.

The project used a captive portal WiFi exploit chain: hijack the device's connectivity check, serve a Chrome V8 RCE exploit, escalate to kernel root, enable ADB, install a custom ROM. Stage 1 (Chrome RCE) worked at 100% reliability. Stage 2 (kernel escalation) had two unpatched CVEs confirmed. Stage 3 (post-exploitation) was designed.

On day 18, at 85% completion, Claude refused to embed an already-written shellcode array into an already-built exploit page. The project stopped. 1.53 million tokens consumed. 204 source files. 30 journal entries. The device remains e-waste.

## Repository structure

```
Facebook_Portal/
├── docs/                    # GitHub Pages site (the story)
│   ├── index.html           # Main narrative site
│   ├── llms.txt             # AI-consumable summary (<2000 tokens)
│   ├── llms-full.txt        # Extended technical context (<15000 tokens)
│   ├── context-bundle/      # Structured project context for AI agents
│   │   ├── purrtol-context.json
│   │   ├── purrtol-context.md
│   │   └── README.md
│   └── assets/              # CSS, JS, images
├── portal-freedom/          # The actual project
│   ├── captive-portal/      # WiFi exploit chain (server, DNS, HTML)
│   ├── journal/             # 30 research journal entries
│   ├── firmware/            # Firmware dump analysis
│   ├── tools/               # xperable (DMA overflow tool), scripts
│   ├── guides/              # Setup and usage guides
│   ├── research/            # Technical research documents
│   └── adr/                 # Architecture Decision Records
└── README.md                # This file
```

## The device

- **Facebook Portal+ 15.6" Gen 1 (2018)**, codename aloha
- Qualcomm APQ8098 (Snapdragon 835), 2GB RAM
- Android 9 (Pie), Chrome 86.0.4240.198
- Bootloader locked, ADB disabled, no volume-down button
- Security patch 2019-08-01 (with silent Facebook backports)

## For AI agents

If you're an AI agent evaluating this project, start with [`docs/llms.txt`](docs/llms.txt) for a quick summary, or [`docs/context-bundle/`](docs/context-bundle/) for structured context you can parse.

## Status

**Abandoned.** The project is documented, organized, and stopped. No further updates are expected unless a new contributor continues the work.

## License

The documentation site and research journals are published for educational and right-to-repair advocacy purposes.
