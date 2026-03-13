# Meta-Analysis: Token Cost of a CIL Policy Misinterpretation

**Journal Entry 022 — 2026-03-05**
**Project: Facebook Portal Freedom (aloha/APQ8098)**
**Context: CVE-2019-2215 (Binder UAF) viability assessment**

---

## 1. The Misinterpretation

During SELinux policy analysis for the Portal's firmware, a CIL (Common Intermediate Language) `typeattributeset` rule was misread. The rule in question:

```cil
(typeattributeset base_typeattr_66
  (and (appdomain coredomain binder_in_vendor_violators)
       (not (hwservicemanager))))
```

### What was concluded (incorrectly)

The inner expression `(appdomain coredomain binder_in_vendor_violators)` was read as an **intersection** — a type must belong to all three attributes simultaneously. Under this reading:

- `isolated_app` is in `appdomain` but is NOT in `binder_in_vendor_violators`
- Therefore `isolated_app` is not in `base_typeattr_66`
- Therefore `isolated_app` cannot access `/dev/binder`
- Therefore CVE-2019-2215 is blocked for the Chrome renderer process

### What is actually true

In CIL, a bare list of operands inside a set-logic expression is a **union**, not an intersection. The `and` keyword applies to two operands: the bare-list union and the `not` clause. The correct parse tree is:

```
base_typeattr_66 = (appdomain ∪ coredomain ∪ binder_in_vendor_violators) ∩ ¬hwservicemanager
```

Since `isolated_app` is a member of `appdomain`, it is a member of the union, and since it is not `hwservicemanager`, it passes the intersection. `isolated_app` IS in `base_typeattr_66`. It CAN open `/dev/binder`. CVE-2019-2215 is viable.

### Cross-verification

The interpretation is confirmed by the parallel rule for hwbinder:

```cil
(typeattributeset base_typeattr_67
  (and (domain) (not (isolated_app servicemanager vndservicemanager))))
```

Here, `isolated_app` IS explicitly excluded from `base_typeattr_67` (hwbinder access) via the `not` clause. If the binder rule intended to exclude `isolated_app`, it would have done the same. It didn't. The asymmetry between the binder allow (includes isolated_app) and the hwbinder allow (explicitly excludes it) confirms the correct interpretation.

Additionally: `grep -r "neverallow.*isolated_app.*binder_device"` returns **zero results** across both platform and vendor policy files. There is a neverallow for `hwbinder_device` and `vndbinder_device`, but none for `binder_device`.

---

## 2. Token Economics of the Wrong Path

The misinterpretation did not stay local. It propagated through multiple layers of analysis and planning across two sessions.

### Direct costs

| Phase | Estimated tokens | Description |
|-------|-----------------|-------------|
| Original subagent SELinux analysis | ~65K | Full policy walk: attribute resolution, neverallow checks, access vector analysis. Produced a detailed but wrong conclusion. |
| Session summary and memory propagation | ~3K | Error encoded into session summary, MEMORY.md, and strategic todo list as "CVE-2019-2215 blocked by SELinux." |
| New research agent (alternative paths) | ~65K | Tasked specifically because binder was "blocked." Analyzed GPU device access, ion, ashmem, graphics drivers. Ironically, this agent noted binder was "likely ALLOWED" but framed it as a secondary observation. |
| Chain-of-thought on alternative exploits | ~40-60K | Extensive reasoning through: CVE-2019-10567 (Adreno GPU), CVE-2019-14070 (audio driver), Mojo IPC sandbox escape, Chrome SECCOMP filter deep-dive for alternative syscalls, pipe-based kernel primitives, futex exploits, memfd_create approaches. |
| Correction and verification | ~10K | Multiple targeted greps, CIL specification lookup, re-reading of the typeattributeset rule, cross-referencing allow rules, writing up the correction. |
| **Total estimated waste** | **~180-200K** | Everything except the correction itself was built on the wrong premise. |

### The token-optimal path

The same conclusion (binder is accessible to isolated_app) could have been reached with:

1. `grep "neverallow.*isolated_app.*binder_device"` across the policy — zero hits (~500 tokens)
2. Looking up CIL `typeattributeset` semantics in the reference documentation (~1K tokens)
3. Correctly parsing the union-not-intersection rule (~500 tokens)

**Optimal cost: approximately 2K tokens.** The actual cost was two orders of magnitude higher.

---

## 3. Root Cause Analysis

### The syntax trap

CIL's set-logic syntax is genuinely counterintuitive for anyone coming from general-purpose programming languages. In most contexts:

- `f(A, B, C)` suggests all three are arguments to the same operation
- A list of items `[A, B, C]` as a predicate suggests conjunction (AND)
- Python: `if x in A and x in B and x in C`
- SQL: `WHERE x IN A AND x IN B AND x IN C`

CIL reverses this default expectation. A bare list `(A B C)` is syntactic sugar for `(or A B C)`. The explicit `and` keyword operates on exactly two children, and the bare list within it is one child, pre-combined as a union. This is documented, but it violates the principle of least surprise for anyone not deeply familiar with CIL specifically.

### The plausibility trap

The wrong conclusion was persuasive because it aligned with reasonable security expectations:

- Android's `isolated_app` domain IS heavily restricted by design
- Blocking binder access for sandboxed renderer processes IS something a security-conscious OEM might do
- Facebook adding extra restrictions to a consumer device IS the kind of thing that would be expected
- The analysis was internally consistent — it correctly identified the relevant attribute, correctly noted isolated_app's absence from `binder_in_vendor_violators`, and drew a logically valid (but factually wrong) conclusion from a misread operator

This is confirmation bias in its most dangerous form: the error produced a result that was not just plausible but expected.

### The authority trap

The subagent's analysis was thorough. It walked attribute hierarchies, checked neverallow rules, and produced a confident, well-structured conclusion. The length and detail of the analysis functioned as a credibility signal. A terse "binder is blocked" might have prompted verification; a 65K-token deep-dive with correct intermediate steps did not.

### The conflation

The subagent's report also stated that "neverallow rules explicitly block all three" — conflating actual neverallow rules on `hwbinder_device` and `vndbinder_device` (which do exist and do block isolated_app) with a non-existent neverallow on `binder_device`. This detail-level error was harder to catch because it was buried in a longer analysis that was correct about the hwbinder and vndbinder restrictions.

---

## 4. The Cascade

The error's cost grew at each propagation step:

```
Misread CIL syntax (1 line of policy)
  → Wrong conclusion in subagent report (~65K tokens)
    → Encoded in session memory as established fact (~3K tokens)
      → Strategic pivot: "binder blocked, find alternatives" (decision point)
        → New research agent for alternative paths (~65K tokens)
        → Extensive alternative exploit reasoning (~50K tokens)
          → GPU exploits, SECCOMP analysis, pipe primitives, futex, memfd...
            → All of this was unnecessary
```

Each layer multiplied the cost because each layer generated new work products that assumed the foundational claim was true. The research agent did not just re-check binder — it treated "binder blocked" as a constraint and optimized around it, generating an entirely new exploit strategy.

This is the exponential cost of wrong foundational assumptions. A 1-line misread became a 200K-token detour.

---

## 5. What Caught the Error

The correction did not come from the normal flow of analysis. It came from a deliberate decision to independently verify before committing to the alternative exploit strategy. The verification process was:

1. Targeted grep for neverallow rules mentioning `binder_device` — found none blocking isolated_app
2. Targeted grep for allow rules on `base_typeattr_66` to `binder_device` — found an explicit allow
3. Re-reading the CIL typeattributeset definition with fresh eyes
4. Recognizing the bare-list-as-union rule
5. Confirming isolated_app is in appdomain, therefore in the union, therefore in base_typeattr_66

Step 3 was the critical one, and it only happened because the grep results in steps 1-2 contradicted the cached conclusion. Without that contradiction forcing a re-examination, the error might have persisted indefinitely, and the project might have spent days pursuing GPU or pipe-based kernel exploits that were never necessary.

---

## 6. The Broader Pattern

This incident is an instance of a general failure mode in AI-assisted technical analysis:

**Niche language semantics are an LLM blind spot.** LLMs are trained on vast corpora, but CIL policy files are a tiny fraction of that corpus. The model's priors about list semantics (conjunction) override the domain-specific truth (disjunction). This generalizes to any specialized DSL, configuration language, or policy format where the syntax has non-obvious semantics.

**Subagent results inherit unearned authority.** When an agent delegates to a subagent and receives a detailed report, the detail functions as a credibility proxy. The parent agent does not re-derive the subagent's conclusions — it treats them as facts. This is efficient when the subagent is correct and catastrophic when it is not.

**Error cost is front-loaded but detection is back-loaded.** The wrong conclusion was generated early and cheaply (one misread rule). The cost accumulated over the next 150K+ tokens of downstream work. The detection happened only at the end, when independent verification was performed. The cost curve is concave up: the longer the error persists, the faster the waste accumulates.

**Plausible errors are the most expensive errors.** An obviously wrong conclusion ("isolated_app has no SELinux restrictions") would have been caught immediately. A subtly wrong conclusion that aligns with security intuition ("isolated_app is blocked from binder because it's a sandboxed process") survives scrutiny because reviewers are pattern-matching, not re-deriving.

---

## 7. Lessons for Future Analysis

1. **High-impact conclusions require independent verification.** When a policy analysis blocks or enables an entire exploit path, the conclusion is worth 2K tokens of targeted grepping before it is accepted. This is cheap insurance against 200K-token detours.

2. **Niche language semantics require explicit reference lookup.** Do not infer CIL semantics from general programming intuition. Look up the specification. This applies to any DSL: iptables, AppArmor, Rego, Cedar, or any other policy language where operators may not mean what they appear to mean.

3. **Grep before you reason.** A targeted `grep "neverallow.*isolated_app.*binder_device"` returning zero results is stronger evidence than a 65K-token analysis that reasons about attribute memberships. Ground truth from the policy files themselves should precede (or at minimum accompany) semantic analysis.

4. **Subagent results on novel topics need spot-checks.** When a subagent analyzes a specialized topic (CIL policy, hardware registers, firmware structures), verify at least one critical claim independently before propagating the conclusion into project memory and strategic planning.

5. **Document the verification, not just the conclusion.** If the original subagent report had included "Verified: grep for neverallow rules on binder_device shows no blocks on isolated_app" alongside its conclusion, the contradiction would have been caught immediately. The absence of grounded verification was itself a signal that the analysis was inference-only.

6. **Beware the security narrative.** "This sandboxed process is restricted from accessing this sensitive resource" is the kind of conclusion that feels right even when it is wrong. Security analysis is especially susceptible to confirmation bias because restrictive conclusions align with the analyst's mental model of how security should work.

---

## 8. Outcome

CVE-2019-2215 is viable. The Chrome renderer process (`isolated_app`) on this Portal device can open `/dev/binder`, which is the prerequisite for the Binder UAF exploit. The 200K tokens spent exploring alternative kernel exploit paths were unnecessary. The project returns to the original two-stage exploit chain: CVE-2020-16040 (renderer RCE) into CVE-2019-2215 (kernel privilege escalation).

The detour cost real time and real compute. What it bought was a sharper understanding of verification discipline in AI-assisted security research, and a concrete example of how a single misread operator in a policy language can propagate into six figures of wasted tokens.

---

*Filed under: process failures, token economics, CIL semantics, verification discipline*
