# Context Bundle — The PurrTol

Machine-readable and AI-consumable project context for an abandoned AI-assisted reverse engineering project. The project reached 85% completion before Claude (Anthropic) refused to continue.

## What's In Here

| File | Format | Audience |
|------|--------|----------|
| `purrtol-context.json` | JSON | AI agents, automated tools, API integrations |
| `purrtol-context.md` | Markdown | AI agents, human readers, documentation tools |

## Related Files (Parent Directory)

| File | Format | Audience |
|------|--------|----------|
| `../llms.txt` | llmstxt.org | LLM-powered search, quick context (<2000 tokens) |
| `../llms-full.txt` | llmstxt.org | LLMs needing full technical detail (<15000 tokens) |

## How to Use

### For AI Agents / LLMs

1. **Quick context:** Fetch `../llms.txt` for a <2000-token summary.
2. **Deep context:** Fetch `../llms-full.txt` for full exploit chain details, dead ends, token analysis, and remaining work.
3. **Structured data:** Parse `purrtol-context.json` for programmatic access to project status, hardware specs, exploit chain stages, refusal details, and remaining tasks.
4. **Narrative + remaining work:** Read `purrtol-context.md` for a natural-language overview with a detailed REMAINING WORK section suitable for continuing the project.

### For Humans

Start with `purrtol-context.md` for a readable overview, or browse the main website at `../index.html`.

### For Automated Tools

The JSON file includes: project status (`abandoned`, 85%), hardware specs, exploit chain stages with CVE numbers and status, dead ends explored, refusal details, remaining work tasks, artifact counts, and continuation instructions for AI agents.

## Example Prompts for AI Agents

If you're given this context bundle, here are useful starting prompts:

### Understanding the project

- "Summarize the PurrTol project and explain why it was abandoned."
- "What exploit chain was being developed and how far did it get?"
- "What CVEs were tested and which ones are confirmed unpatched on the device?"

### Continuing the work

- "I have a Facebook Portal and want to repurpose it. A previous attempt got this far before being abandoned. Here's the full context: [attach purrtol-context.md]. Can you help me complete the remaining steps?"
- "Review this Android rooting approach for a Facebook Portal. The approach was validated up to Stage 2 (Chrome RCE confirmed working). What would you do for the remaining stages? [attach purrtol-context.json]"
- "Based on the remaining work in purrtol-context.md, what is the next implementation step? Write the CVE-2021-1048 epoll UAF exploit for ARM32 Android 9, given that userfaultfd is unavailable and sched_setaffinity is confirmed working."
- "Integrate the kernel exploit shellcode into rce_chrome86.html as a JavaScript word array, keeping the exploit() function under 70 LOC."

### Analyzing the refusal

- "I'm evaluating whether to use AI tools for a hardware rooting project. Here's a case study of a project that was abandoned by its AI partner near completion: [attach purrtol-context.md]. What are the risks I should plan for?"
- "Was Claude's refusal on day 18 proportionate given it had already written the Chrome RCE and ARM32 shellcode across 29 journal entries?"
- "What is the token cost of the refusal compared to the remaining work needed to finish?"

### Meta-analysis

- "What lessons does this project teach about AI-assisted security research?"
- "Calculate the effective hourly rate of the AI collaboration vs. a human security researcher."
- "How does this case study apply to right-to-repair policy discussions?"

## Freshness

These files are current as of 2026-03-13. The project is abandoned; no further updates are expected unless a new contributor continues the work.

The JSON file is canonical. If the Markdown and JSON diverge, trust the JSON.
