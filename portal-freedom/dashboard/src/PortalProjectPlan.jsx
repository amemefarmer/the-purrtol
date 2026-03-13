import { useState } from "react";

const APPROACHES = [
  {
    id: "edl-firehose",
    rank: 1,
    name: "EDL + Firehose Flash",
    target: "Portal 10\" Gen 2 (atlas)",
    probability: 72,
    effort: "Medium",
    risk: "Medium-High",
    prereqs: ["Firehose .mbn file (shared Dec 2025)", "QPST/QFIL installed", "USB-C cable + drivers"],
    reasoning: "A firehose programmer for the atlas model was shared publicly in December 2025. If it's valid and properly signed for EDL, it bypasses the locked bootloader entirely by writing directly to eMMC at the hardware level. This is the only approach with a concrete, publicly available tool.",
    status: "active",
    phases: [
      { name: "Setup & Backup", duration: "1–2 days", tasks: [
        { text: "Install QPST, QFIL, and Qualcomm USB drivers", done: false },
        { text: "Enter EDL mode (hold all 3 buttons + USB-C)", done: false },
        { text: "Verify device shows as QDLoader 9008", done: false },
        { text: "Dump ALL partitions as backup using firehose", done: false },
      ]},
      { name: "Boot Image Modification", duration: "1–3 days", tasks: [
        { text: "Extract boot.img from firmware dump", done: false },
        { text: "Unpack boot.img (mkbootimg / magiskboot)", done: false },
        { text: "Locate and flip ADB enabled flag in default.prop", done: false },
        { text: "Repack modified boot.img", done: false },
      ]},
      { name: "Flash & Test", duration: "1 day", tasks: [
        { text: "Flash modified boot.img via QPST", done: false },
        { text: "Boot device — check for ADB visibility", done: false },
        { text: "If boot loop → reflash original backup", done: false },
        { text: "If ADB works → proceed to system modification", done: false },
      ]},
      { name: "System Unlock", duration: "2–5 days", tasks: [
        { text: "Use ADB to disable dm-verity", done: false },
        { text: "Attempt to flash vbmeta with --disable-verification", done: false },
        { text: "Install custom recovery (TWRP if available)", done: false },
        { text: "Flash GSI (Android 12L+ arm64 A/B)", done: false },
      ]},
    ],
  },
  {
    id: "bootloader-exploit",
    rank: 2,
    name: "QCS605 Bootloader Buffer Overflow",
    target: "Portal+ Gen 1 (firmware ≤ 1.9.2)",
    probability: 55,
    effort: "Very High",
    risk: "Medium",
    prereqs: ["Gen 1 unit on old firmware", "ARM64 RE skills", "Bootloader dump for exact FW version"],
    reasoning: "First-gen Portals are stuck on August 2019 security patches. Known Qualcomm QCS605 buffer overflows (similar to Quest 1/2 exploits) are applicable. However, exploitation requires a bootloader dump for the specific firmware version and advanced ARM64 reverse engineering to build a ROP chain. High skill barrier but well-understood attack class.",
    status: "research",
    phases: [
      { name: "Acquire Target Hardware", duration: "1–2 weeks", tasks: [
        { text: "Source Portal+ Gen 1 on firmware ≤ 1.9.2", done: false },
        { text: "Verify firmware version before WiFi connection (avoid OTA)", done: false },
        { text: "Confirm security patch level: August 1, 2019", done: false },
      ]},
      { name: "Bootloader Analysis", duration: "2–4 weeks", tasks: [
        { text: "Extract XBL (eXtensible Boot Loader) from firmware dump", done: false },
        { text: "Unpack XBL with binwalk — identify ELF components", done: false },
        { text: "Load into Ghidra/IDA — map Sahara protocol handlers", done: false },
        { text: "Identify vulnerable buffer in fastboot command handler", done: false },
      ]},
      { name: "Exploit Development", duration: "2–6 weeks", tasks: [
        { text: "Map memory layout and find ROP gadgets in XBL", done: false },
        { text: "Build ROP chain to: disable secure boot check OR enable ADB", done: false },
        { text: "Develop delivery mechanism (fastboot OEM command / USB)", done: false },
        { text: "Test exploit — iterate on failures", done: false },
      ]},
      { name: "Post-Exploit", duration: "1–2 weeks", tasks: [
        { text: "Use exploit to unlock bootloader or gain root shell", done: false },
        { text: "Disable dm-verity and AVB", done: false },
        { text: "Flash GSI or custom ROM", done: false },
        { text: "Document and release exploit for community", done: false },
      ]},
    ],
  },
  {
    id: "dev-unit-re",
    rank: 3,
    name: "Developer Unit Reverse Engineering",
    target: "All Portal models (via key extraction)",
    probability: 45,
    effort: "High",
    risk: "Low",
    prereqs: ["Access to a developer/unsealed Portal unit", "Crypto analysis skills"],
    reasoning: "Multiple researchers have developer units with unlocked bootloaders and ADB. These can be used to reverse-engineer the unlock challenge-response mechanism. If the signing key or algorithm can be extracted or the challenge can be replayed/forged, a universal unlock tool could be built. Low risk because analysis is done on the dev unit, not the target retail unit.",
    status: "research",
    phases: [
      { name: "Developer Unit Analysis", duration: "1–2 weeks", tasks: [
        { text: "Acquire or partner with someone who has a dev unit", done: false },
        { text: "Dump full system, boot, vendor, vbmeta partitions", done: false },
        { text: "Extract all APKs — analyze bootloader unlock entitlement logic", done: false },
        { text: "Diff developer vs retail firmware images", done: false },
      ]},
      { name: "Unlock Mechanism RE", duration: "3–8 weeks", tasks: [
        { text: "Analyze fastboot flashing unlock_bootloader command handler", done: false },
        { text: "Identify challenge generation algorithm in bootloader", done: false },
        { text: "Determine signing key storage (fused in SoC? in partition?)", done: false },
        { text: "Check if dev unit key is reusable or device-specific", done: false },
      ]},
      { name: "Tool Development", duration: "2–4 weeks", tasks: [
        { text: "If key is extractable → build signing tool", done: false },
        { text: "If algorithm is bypassable → build fastboot unlock script", done: false },
        { text: "Test on a sacrificial retail unit", done: false },
        { text: "Release tool + documentation publicly", done: false },
      ]},
    ],
  },
  {
    id: "hardware-isp",
    rank: 4,
    name: "Hardware ISP / Direct Flash Access",
    target: "Any Portal model",
    probability: 80,
    effort: "Extreme",
    risk: "Very High",
    prereqs: ["Micro-soldering equipment", "eMMC/UFS reader", "ISP adapter or chip-off tools"],
    reasoning: "Physically accessing the storage chip (eMMC or UFS) via In-System Programming (ISP) or chip-off completely bypasses all software security. You can read/write any partition including boot, system, and vbmeta. Probability is high because it's a known working technique, but the effort and risk are extreme — requires destroying the case, precision soldering, and any mistake bricks the device permanently.",
    status: "theoretical",
    phases: [
      { name: "Teardown & Mapping", duration: "1–3 days", tasks: [
        { text: "Open device (destructive for Portal+ Gen 1)", done: false },
        { text: "Identify eMMC/UFS chip and ISP test points on PCB", done: false },
        { text: "Map pinout for ISP connection", done: false },
      ]},
      { name: "Direct Flash Read", duration: "1–2 days", tasks: [
        { text: "Connect ISP adapter / eMMC reader to test points", done: false },
        { text: "Dump full flash contents as raw image", done: false },
        { text: "Parse partition table and extract individual partitions", done: false },
      ]},
      { name: "Modification & Write-back", duration: "2–5 days", tasks: [
        { text: "Modify boot.img (enable ADB, disable verity)", done: false },
        { text: "Patch vbmeta to disable AVB verification", done: false },
        { text: "Write modified image back to flash", done: false },
        { text: "Reassemble device and test boot", done: false },
      ]},
    ],
  },
  {
    id: "gsi-post-unlock",
    rank: 5,
    name: "GSI Flashing (Post-Unlock Phase)",
    target: "Any unlocked Portal",
    probability: 90,
    effort: "Low",
    risk: "Low",
    prereqs: ["Unlocked bootloader (from any above method)", "ADB + fastboot access"],
    reasoning: "Once the bootloader is unlocked, this is straightforward. Android 9 with Project Treble means GSI images work. An Android 12L GSI was already demonstrated on a prototype. This is the endgame — the step that actually turns the Portal into a usable generic device.",
    status: "blocked",
    phases: [
      { name: "Preparation", duration: "1–2 hours", tasks: [
        { text: "Download arm64 A/B GSI image (phhusson AOSP, LineageOS, etc.)", done: false },
        { text: "Verify Treble compatibility with Treble Info (if accessible)", done: false },
        { text: "Backup current system partition", done: false },
      ]},
      { name: "Flash & Configure", duration: "2–4 hours", tasks: [
        { text: "fastboot flash vbmeta vbmeta.img --disable-verification --disable-verity", done: false },
        { text: "fastboot flash system system.img", done: false },
        { text: "fastboot -w (wipe userdata)", done: false },
        { text: "Boot into new OS — complete Android setup", done: false },
      ]},
      { name: "Post-Install", duration: "1–3 days", tasks: [
        { text: "Test touchscreen, camera, microphones, WiFi, speakers", done: false },
        { text: "Install GApps or MicroG if needed", done: false },
        { text: "Install target apps (Home Assistant, Zoom, etc.)", done: false },
        { text: "Configure as kiosk / dashboard / tablet as desired", done: false },
      ]},
    ],
  },
];

const STATUS_CONFIG = {
  active: { label: "Active", color: "#22c55e", bg: "rgba(34,197,94,0.12)" },
  research: { label: "Research", color: "#f59e0b", bg: "rgba(245,158,11,0.12)" },
  theoretical: { label: "Theoretical", color: "#8b5cf6", bg: "rgba(139,92,246,0.12)" },
  blocked: { label: "Blocked", color: "#ef4444", bg: "rgba(239,68,68,0.12)" },
};

function ProbabilityBar({ value }) {
  const color = value >= 70 ? "#22c55e" : value >= 50 ? "#f59e0b" : value >= 30 ? "#ef4444" : "#6b7280";
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
      <div style={{ flex: 1, height: 6, background: "rgba(255,255,255,0.06)", borderRadius: 3, overflow: "hidden" }}>
        <div style={{ width: `${value}%`, height: "100%", background: color, borderRadius: 3, transition: "width 0.6s cubic-bezier(.4,0,.2,1)" }} />
      </div>
      <span style={{ fontFamily: "'JetBrains Mono', 'Fira Code', monospace", fontSize: 13, color, fontWeight: 700, minWidth: 38, textAlign: "right" }}>{value}%</span>
    </div>
  );
}

function PhaseBlock({ phase, phaseIdx, approachId, toggleTask }) {
  const done = phase.tasks.filter(t => t.done).length;
  const total = phase.tasks.length;
  const pct = Math.round((done / total) * 100);
  return (
    <div style={{ background: "rgba(255,255,255,0.02)", borderRadius: 8, padding: "14px 16px", border: "1px solid rgba(255,255,255,0.06)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#64748b", background: "rgba(255,255,255,0.05)", padding: "2px 6px", borderRadius: 4 }}>PHASE {phaseIdx + 1}</span>
          <span style={{ fontSize: 14, fontWeight: 600, color: "#e2e8f0" }}>{phase.name}</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: "#64748b" }}>{phase.duration}</span>
          <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: pct === 100 ? "#22c55e" : "#94a3b8" }}>{done}/{total}</span>
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        {phase.tasks.map((task, ti) => (
          <label key={ti} style={{ display: "flex", alignItems: "flex-start", gap: 8, cursor: "pointer", padding: "4px 0", userSelect: "none" }}
            onClick={() => toggleTask(approachId, phaseIdx, ti)}>
            <div style={{
              width: 16, height: 16, minWidth: 16, borderRadius: 4, marginTop: 1,
              border: task.done ? "none" : "1.5px solid rgba(255,255,255,0.15)",
              background: task.done ? "#22c55e" : "transparent",
              display: "flex", alignItems: "center", justifyContent: "center",
              transition: "all 0.2s"
            }}>
              {task.done && <span style={{ color: "#000", fontSize: 11, fontWeight: 800 }}>✓</span>}
            </div>
            <span style={{
              fontSize: 13, lineHeight: "18px",
              color: task.done ? "#64748b" : "#cbd5e1",
              textDecoration: task.done ? "line-through" : "none",
              transition: "all 0.2s"
            }}>{task.text}</span>
          </label>
        ))}
      </div>
    </div>
  );
}

export default function PortalProjectPlan() {
  const [approaches, setApproaches] = useState(APPROACHES);
  const [expanded, setExpanded] = useState("edl-firehose");
  const [view, setView] = useState("plan");

  const toggleTask = (approachId, phaseIdx, taskIdx) => {
    setApproaches(prev => prev.map(a => {
      if (a.id !== approachId) return a;
      const newPhases = a.phases.map((p, pi) => {
        if (pi !== phaseIdx) return p;
        const newTasks = p.tasks.map((t, ti) => ti === taskIdx ? { ...t, done: !t.done } : t);
        return { ...p, tasks: newTasks };
      });
      return { ...a, phases: newPhases };
    }));
  };

  const totalTasks = approaches.reduce((s, a) => s + a.phases.reduce((s2, p) => s2 + p.tasks.length, 0), 0);
  const doneTasks = approaches.reduce((s, a) => s + a.phases.reduce((s2, p) => s2 + p.tasks.filter(t => t.done).length, 0), 0);

  return (
    <div style={{
      minHeight: "100vh", background: "#0a0e17",
      fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, sans-serif",
      color: "#e2e8f0", padding: "0 0 40px"
    }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&family=Inter:wght@400;500;600;700;800&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.1); border-radius: 3px; }
      `}</style>

      {/* Header */}
      <div style={{
        background: "linear-gradient(180deg, rgba(34,197,94,0.06) 0%, transparent 100%)",
        borderBottom: "1px solid rgba(255,255,255,0.06)",
        padding: "28px 24px 20px"
      }}>
        <div style={{ maxWidth: 900, margin: "0 auto" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 4 }}>
            <div style={{
              width: 8, height: 8, borderRadius: "50%", background: "#22c55e",
              boxShadow: "0 0 8px rgba(34,197,94,0.5)",
              animation: "pulse 2s infinite"
            }} />
            <style>{`@keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.4; } }`}</style>
            <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: "#22c55e", letterSpacing: 2, textTransform: "uppercase" }}>Project Portal Freedom</span>
          </div>
          <h1 style={{ fontSize: 26, fontWeight: 800, color: "#f1f5f9", margin: "6px 0 6px", letterSpacing: -0.5 }}>
            Facebook Portal → Generic Device
          </h1>
          <p style={{ fontSize: 14, color: "#64748b", maxWidth: 600, lineHeight: 1.5 }}>
            Ranked attack vectors for unlocking retail Meta Portal hardware. Approaches ordered by feasibility × impact.
          </p>

          {/* Stats bar */}
          <div style={{ display: "flex", gap: 24, marginTop: 16, flexWrap: "wrap" }}>
            <div>
              <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: "#64748b", marginBottom: 2 }}>APPROACHES</div>
              <div style={{ fontSize: 22, fontWeight: 800, color: "#e2e8f0" }}>{approaches.length}</div>
            </div>
            <div>
              <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: "#64748b", marginBottom: 2 }}>TOTAL TASKS</div>
              <div style={{ fontSize: 22, fontWeight: 800, color: "#e2e8f0" }}>{totalTasks}</div>
            </div>
            <div>
              <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: "#64748b", marginBottom: 2 }}>COMPLETED</div>
              <div style={{ fontSize: 22, fontWeight: 800, color: doneTasks > 0 ? "#22c55e" : "#475569" }}>{doneTasks}</div>
            </div>
            <div style={{ marginLeft: "auto", display: "flex", gap: 4, alignSelf: "flex-end" }}>
              {["plan", "matrix"].map(v => (
                <button key={v} onClick={() => setView(v)} style={{
                  padding: "6px 14px", borderRadius: 6, border: "1px solid rgba(255,255,255,0.1)",
                  background: view === v ? "rgba(255,255,255,0.08)" : "transparent",
                  color: view === v ? "#e2e8f0" : "#64748b",
                  fontSize: 12, fontWeight: 600, cursor: "pointer", fontFamily: "inherit",
                  transition: "all 0.2s"
                }}>{v === "plan" ? "📋 Plan" : "📊 Matrix"}</button>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div style={{ maxWidth: 900, margin: "0 auto", padding: "20px 24px" }}>

        {view === "matrix" && (
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
              <thead>
                <tr>
                  {["Rank", "Approach", "Target", "Success %", "Effort", "Risk", "Status"].map(h => (
                    <th key={h} style={{
                      textAlign: "left", padding: "10px 12px",
                      fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#64748b",
                      letterSpacing: 1, textTransform: "uppercase",
                      borderBottom: "1px solid rgba(255,255,255,0.08)"
                    }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {approaches.map(a => {
                  const sc = STATUS_CONFIG[a.status];
                  return (
                    <tr key={a.id} style={{ borderBottom: "1px solid rgba(255,255,255,0.04)" }}
                      onClick={() => { setExpanded(a.id); setView("plan"); }}
                    >
                      <td style={{ padding: "12px", cursor: "pointer" }}>
                        <span style={{
                          fontFamily: "'JetBrains Mono', monospace", fontSize: 18, fontWeight: 800,
                          color: a.rank === 1 ? "#22c55e" : a.rank === 2 ? "#f59e0b" : "#64748b"
                        }}>#{a.rank}</span>
                      </td>
                      <td style={{ padding: "12px", fontWeight: 600, color: "#e2e8f0", cursor: "pointer" }}>{a.name}</td>
                      <td style={{ padding: "12px", color: "#94a3b8", fontSize: 12 }}>{a.target}</td>
                      <td style={{ padding: "12px", minWidth: 140 }}><ProbabilityBar value={a.probability} /></td>
                      <td style={{ padding: "12px" }}>
                        <span style={{
                          padding: "3px 8px", borderRadius: 4, fontSize: 11, fontWeight: 600,
                          background: a.effort === "Low" ? "rgba(34,197,94,0.12)" : a.effort === "Medium" ? "rgba(245,158,11,0.12)" : a.effort.includes("High") ? "rgba(239,68,68,0.12)" : "rgba(139,92,246,0.12)",
                          color: a.effort === "Low" ? "#22c55e" : a.effort === "Medium" ? "#f59e0b" : a.effort.includes("High") ? "#ef4444" : "#8b5cf6"
                        }}>{a.effort}</span>
                      </td>
                      <td style={{ padding: "12px" }}>
                        <span style={{
                          padding: "3px 8px", borderRadius: 4, fontSize: 11, fontWeight: 600,
                          background: a.risk === "Low" ? "rgba(34,197,94,0.12)" : a.risk.includes("Medium") ? "rgba(245,158,11,0.12)" : "rgba(239,68,68,0.12)",
                          color: a.risk === "Low" ? "#22c55e" : a.risk.includes("Medium") ? "#f59e0b" : "#ef4444"
                        }}>{a.risk}</span>
                      </td>
                      <td style={{ padding: "12px" }}>
                        <span style={{
                          padding: "3px 8px", borderRadius: 4, fontSize: 11, fontWeight: 600,
                          background: sc.bg, color: sc.color
                        }}>{sc.label}</span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {view === "plan" && (
          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            {approaches.map(a => {
              const isOpen = expanded === a.id;
              const sc = STATUS_CONFIG[a.status];
              const aDone = a.phases.reduce((s, p) => s + p.tasks.filter(t => t.done).length, 0);
              const aTotal = a.phases.reduce((s, p) => s + p.tasks.length, 0);
              const aPct = Math.round((aDone / aTotal) * 100);

              return (
                <div key={a.id} style={{
                  background: isOpen ? "rgba(255,255,255,0.025)" : "rgba(255,255,255,0.015)",
                  borderRadius: 12,
                  border: `1px solid ${isOpen ? "rgba(255,255,255,0.1)" : "rgba(255,255,255,0.05)"}`,
                  overflow: "hidden",
                  transition: "all 0.3s"
                }}>
                  {/* Approach header */}
                  <div onClick={() => setExpanded(isOpen ? null : a.id)}
                    style={{ padding: "16px 20px", cursor: "pointer", display: "flex", flexDirection: "column", gap: 10 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
                      <span style={{
                        fontFamily: "'JetBrains Mono', monospace", fontSize: 13, fontWeight: 800,
                        color: a.rank === 1 ? "#22c55e" : a.rank === 2 ? "#f59e0b" : a.rank <= 4 ? "#8b5cf6" : "#64748b",
                        minWidth: 28
                      }}>#{a.rank}</span>
                      <span style={{ fontSize: 16, fontWeight: 700, color: "#f1f5f9", flex: 1 }}>{a.name}</span>
                      <span style={{ padding: "3px 8px", borderRadius: 4, fontSize: 10, fontWeight: 600, background: sc.bg, color: sc.color, letterSpacing: 0.5, textTransform: "uppercase" }}>{sc.label}</span>
                      <span style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 12, color: "#64748b" }}>{aDone}/{aTotal}</span>
                      <span style={{ fontSize: 14, color: "#64748b", transform: isOpen ? "rotate(180deg)" : "rotate(0)", transition: "transform 0.2s" }}>▼</span>
                    </div>

                    <div style={{ display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
                      <div style={{ flex: "1 1 200px", minWidth: 150 }}>
                        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#475569", marginBottom: 3 }}>SUCCESS PROBABILITY</div>
                        <ProbabilityBar value={a.probability} />
                      </div>
                      <div>
                        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#475569", marginBottom: 3 }}>TARGET</div>
                        <span style={{ fontSize: 12, color: "#94a3b8" }}>{a.target}</span>
                      </div>
                      <div>
                        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#475569", marginBottom: 3 }}>EFFORT</div>
                        <span style={{ fontSize: 12, color: "#94a3b8" }}>{a.effort}</span>
                      </div>
                      <div>
                        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#475569", marginBottom: 3 }}>RISK</div>
                        <span style={{ fontSize: 12, color: "#94a3b8" }}>{a.risk}</span>
                      </div>
                    </div>

                    {/* Progress bar */}
                    <div style={{ height: 3, background: "rgba(255,255,255,0.04)", borderRadius: 2, overflow: "hidden" }}>
                      <div style={{ width: `${aPct}%`, height: "100%", background: aPct === 100 ? "#22c55e" : "#3b82f6", borderRadius: 2, transition: "width 0.4s" }} />
                    </div>
                  </div>

                  {/* Expanded content */}
                  {isOpen && (
                    <div style={{ padding: "0 20px 20px", borderTop: "1px solid rgba(255,255,255,0.05)" }}>
                      {/* Reasoning */}
                      <div style={{ margin: "16px 0", padding: "12px 14px", background: "rgba(255,255,255,0.02)", borderRadius: 8, borderLeft: "3px solid rgba(255,255,255,0.1)" }}>
                        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#64748b", letterSpacing: 1, marginBottom: 6 }}>RATIONALE</div>
                        <p style={{ fontSize: 13, color: "#94a3b8", lineHeight: 1.6 }}>{a.reasoning}</p>
                      </div>

                      {/* Prerequisites */}
                      <div style={{ marginBottom: 16 }}>
                        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: "#64748b", letterSpacing: 1, marginBottom: 8 }}>PREREQUISITES</div>
                        <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                          {a.prereqs.map((p, i) => (
                            <span key={i} style={{
                              padding: "4px 10px", borderRadius: 6, fontSize: 12,
                              background: "rgba(59,130,246,0.08)", color: "#60a5fa",
                              border: "1px solid rgba(59,130,246,0.15)"
                            }}>{p}</span>
                          ))}
                        </div>
                      </div>

                      {/* Phases */}
                      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                        {a.phases.map((phase, pi) => (
                          <PhaseBlock key={pi} phase={phase} phaseIdx={pi} approachId={a.id} toggleTask={toggleTask} />
                        ))}
                      </div>

                      {/* Dependency note for blocked items */}
                      {a.status === "blocked" && (
                        <div style={{
                          marginTop: 12, padding: "10px 14px", borderRadius: 8,
                          background: "rgba(239,68,68,0.06)", border: "1px solid rgba(239,68,68,0.15)",
                          fontSize: 12, color: "#f87171", display: "flex", alignItems: "center", gap: 8
                        }}>
                          <span style={{ fontSize: 16 }}>⛓</span>
                          <span><strong>Blocked:</strong> Requires successful completion of Approach #1, #2, #3, or #4 first (any path that unlocks the bootloader).</span>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* Critical path summary */}
        <div style={{
          marginTop: 24, padding: "20px", borderRadius: 12,
          background: "linear-gradient(135deg, rgba(34,197,94,0.04), rgba(59,130,246,0.04))",
          border: "1px solid rgba(255,255,255,0.06)"
        }}>
          <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: "#22c55e", letterSpacing: 1.5, marginBottom: 10 }}>◆ RECOMMENDED CRITICAL PATH</div>
          <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap", fontSize: 13 }}>
            {[
              { label: "#1 EDL Flash", color: "#22c55e" },
              { label: "→" },
              { label: "Enable ADB", color: "#3b82f6" },
              { label: "→" },
              { label: "Disable Verity", color: "#3b82f6" },
              { label: "→" },
              { label: "#5 Flash GSI", color: "#22c55e" },
              { label: "→" },
              { label: "Generic Android Device ✓", color: "#22c55e" },
            ].map((step, i) => (
              step.color ? (
                <span key={i} style={{
                  padding: "4px 10px", borderRadius: 6, fontWeight: 600,
                  background: `${step.color}15`, color: step.color,
                  border: `1px solid ${step.color}30`, fontSize: 12
                }}>{step.label}</span>
              ) : (
                <span key={i} style={{ color: "#475569", fontFamily: "'JetBrains Mono', monospace" }}>{step.label}</span>
              )
            ))}
          </div>
          <p style={{ fontSize: 12, color: "#64748b", marginTop: 10, lineHeight: 1.5 }}>
            Fastest path: Use the December 2025 firehose to modify boot.img via EDL, then flash a GSI once ADB is available. Fallback: bootloader exploit on Gen 1 hardware. The community's most urgent need is someone with ARM64 reverse engineering skills to analyze the XBL unlock mechanism.
          </p>
        </div>
      </div>
    </div>
  );
}
