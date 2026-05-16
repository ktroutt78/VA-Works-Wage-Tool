// Wireframes — salary comparison viz (Virginia Works style).
// Three options. Cleaner than typical sketchy wireframes per the brief —
// the chart is the focus and must read clearly. Government-style palette:
// deep navy accent, warm neutrals, serif title face.

const { useMemo } = React;

// Tokens ----------------------------------------------------------------
const INK   = "#1a1f2c";
const MUTED = "#5a6376";
const LINE  = "#cdd3df";
const PAPER = "#fbfaf6";
const SHELL = "#ffffff";
const FAINT = "#eceadf";
const HI    = "#b03a2e";  // you-marker (clear, accessible against navy)

// Sample data -----------------------------------------------------------
// Five-number summary + median + a synthetic 5-year trend for sparklines.
const ROWS = {
  clerk:   { job:"New Accounts Clerks",       area:"Virginia Beach–Norfolk",
             p:{10:38000,25:43000,50:46500,75:51000,90:55000},
             trend:[42000, 43500, 44200, 45800, 46500] },
  social:  { job:"Healthcare Social Workers", area:"Virginia Beach–Norfolk",
             p:{10:50000,25:55000,50:64000,75:74000,90:79000},
             trend:[55000, 57500, 60000, 62500, 64000] },
  software:{ job:"Software Developers",       area:"Virginia Beach–Norfolk",
             p:{10:70000,25:84000,50:98000,75:115000,90:138000},
             trend:[82000, 87000, 91000, 95000, 98000] },
};

// Wider domain so the third row (software dev) fits when shown.
const DOMAIN_2 = [33000, 82000];
const TICKS_2  = [35000, 45000, 55000, 65000, 75000];
const DOMAIN_3 = [33000, 142000];
const TICKS_3  = [40000, 60000, 80000, 100000, 120000, 140000];

// --------------------------------------------------------------------
// PercentileBar — the workhorse chart primitive.
// Renders 10–90 light range, 25–75 filled range, median tick, optional
// salary marker, optional axis. Used by every wireframe.
// --------------------------------------------------------------------
function PercentileBar({ width, height = 26, domain, p, salary, accent, showAxis, axisTicks, dense }) {
  const [dMin, dMax] = domain;
  const padL = 0, padR = 0;
  const W = Math.max(40, width - padL - padR);
  const x = (v) => padL + ((v - dMin) / (dMax - dMin)) * W;
  const barY = 4, barH = height - 8;

  return (
    <svg width={width} height={showAxis ? height + 20 : height} style={{display:"block", overflow:"visible"}}>
      {/* baseline rail */}
      <line x1={padL} x2={padL+W} y1={barY + barH/2} y2={barY + barH/2}
            stroke={LINE} strokeWidth="1" />
      {/* 10–90 light range */}
      <rect x={x(p[10])} y={barY} width={x(p[90]) - x(p[10])} height={barH}
            fill="#e6e3d7" stroke="none" rx="2"/>
      {/* 25–75 filled range */}
      <rect x={x(p[25])} y={barY + 1} width={x(p[75]) - x(p[25])} height={barH - 2}
            fill={accent} rx="1.5"/>
      {/* median tick */}
      <line x1={x(p[50])} x2={x(p[50])} y1={barY - 3} y2={barY + barH + 3}
            stroke={INK} strokeWidth="2" />
      {/* salary marker */}
      {salary != null && (
        <g>
          <line x1={x(salary)} x2={x(salary)} y1={barY - 6} y2={barY + barH + 6}
                stroke={HI} strokeWidth="2.4" />
          <circle cx={x(salary)} cy={barY + barH/2} r="3.6" fill={HI} stroke="#fff" strokeWidth="1.4"/>
        </g>
      )}
      {/* axis */}
      {showAxis && (
        <g transform={`translate(0,${barY + barH + 6})`}>
          <line x1={padL} x2={padL+W} y1="0" y2="0" stroke={LINE} strokeWidth="1"/>
          {(axisTicks || []).map((t,i)=>(
            <g key={i} transform={`translate(${x(t)},0)`}>
              <line x1="0" x2="0" y1="0" y2="3" stroke={MUTED} strokeWidth="1"/>
              <text x="0" y="14" fontSize={dense?10:11} textAnchor="middle"
                    fontFamily="ui-monospace, 'JetBrains Mono', monospace" fill={MUTED}>
                ${(t/1000)}K
              </text>
            </g>
          ))}
        </g>
      )}
    </svg>
  );
}

// Tiny sparkline (5-yr trend) ----------------------------------------
function Sparkline({ data, width=80, height=22, accent }) {
  const min = Math.min(...data), max = Math.max(...data);
  const x = (i) => (i / (data.length - 1)) * (width - 2) + 1;
  const y = (v) => height - 2 - ((v - min) / Math.max(1, max - min)) * (height - 4);
  const pts = data.map((v,i)=>`${x(i)},${y(v)}`).join(" ");
  return (
    <svg width={width} height={height}>
      <polyline points={pts} fill="none" stroke={accent} strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round"/>
      <circle cx={x(data.length-1)} cy={y(data[data.length-1])} r="2.5" fill={accent}/>
    </svg>
  );
}

// Compute approx percentile rank of `salary` within the 5-number summary
function approxPercentile(p, salary) {
  const pts = [[10,p[10]],[25,p[25]],[50,p[50]],[75,p[75]],[90,p[90]]];
  if (salary <= pts[0][1]) return "<10";
  if (salary >= pts[4][1]) return ">90";
  for (let i=0;i<pts.length-1;i++){
    const [pa,va] = pts[i], [pb,vb] = pts[i+1];
    if (salary >= va && salary <= vb) {
      const t = (salary - va) / (vb - va);
      return Math.round(pa + t * (pb - pa));
    }
  }
  return "—";
}

// Header band shared across wireframes for a consistent Virginia Works
// agency feel — slim navy ribbon w/ tool label, like state-agency headers.
function AgencyHeader({ subtitle }) {
  return (
    <div style={{
      background: INK, color:"#fff", padding:"10px 16px",
      display:"flex", justifyContent:"space-between", alignItems:"baseline",
      borderTopLeftRadius:6, borderTopRightRadius:6,
    }}>
      <div>
        <div style={{fontFamily:'"Source Serif Pro", Georgia, serif', fontSize:18, fontWeight:600, letterSpacing:0.2}}>
          Wage Comparison Tool
        </div>
        {subtitle && (
          <div style={{fontSize:11, color:"#c8cdd9", marginTop:2, letterSpacing:0.4}}>
            {subtitle}
          </div>
        )}
      </div>
      <div style={{fontSize:10, color:"#9ea6b8", fontFamily:'ui-monospace, "JetBrains Mono", monospace', letterSpacing:0.6, textTransform:"uppercase"}}>
        Virginia Works · LMI
      </div>
    </div>
  );
}

// =====================================================================
// W1 — FAITHFUL+
// The reference layout, refined: agency header, percentile readout pill,
// median called out beside each row, trend sparkline at row-end.
// Safe / by-the-book direction.
// =====================================================================
function W1({ accent, rows }) {
  const W = 760;
  const visible = rows === 3 ? ["clerk", "social", "software"] : ["clerk", "social"];
  const domain = rows === 3 ? DOMAIN_3 : DOMAIN_2;
  const ticks  = rows === 3 ? TICKS_3  : TICKS_2;
  const userSalary = 48000;

  // Column widths
  const colJob = 130, colArea = 110, colTrend = 90, gap = 12;
  const chartW = W - 32 - colJob - colArea - colTrend - gap*3;

  return (
    <div style={{width:W, border:`1px solid ${LINE}`, borderRadius:6, background:SHELL, overflow:"hidden"}}>
      <AgencyHeader subtitle="Compare wages in your area · Bureau of Labor Statistics OEWS" />

      {/* Controls grid */}
      <div style={{padding:"14px 16px", background:PAPER, borderBottom:`1px solid ${LINE}`}}>
        <div style={{display:"grid", gridTemplateColumns:"1.2fr 1.4fr 1fr", gap:12, marginBottom:10}}>
          <Field label="Current job"      value="New Accounts Clerks" />
          <Field label="Current location" value="Virginia Beach–Norfolk, VA" />
          <Field label="Current salary"   value="$48,000" noCaret />
        </div>
        <div style={{display:"grid", gridTemplateColumns:"1.2fr 1.4fr 1fr", gap:12}}>
          <Field label="Comparison job"      value="Healthcare Social Workers" />
          <Field label="Comparison location" value="Virginia Beach" />
          <Legend accent={accent} />
        </div>
      </div>

      {/* Chart */}
      <div style={{padding:"12px 16px 16px"}}>
        <div style={{
          display:"grid",
          gridTemplateColumns:`${colJob}px ${colArea}px 1fr ${colTrend}px`,
          gap, fontSize:10, color:MUTED, textTransform:"uppercase", letterSpacing:0.6, marginBottom:6,
        }}>
          <span>Occupation</span><span>Area</span><span></span><span>5-yr trend</span>
        </div>

        {visible.map((key,i)=>{
          const r = ROWS[key];
          const isYou = key === "clerk";
          const pct = isYou ? approxPercentile(r.p, userSalary) : null;
          return (
            <div key={key} style={{
              display:"grid",
              gridTemplateColumns:`${colJob}px ${colArea}px 1fr ${colTrend}px`,
              gap, alignItems:"center",
              padding:"10px 0", borderBottom:`1px solid ${FAINT}`,
            }}>
              <div style={{fontSize:13, fontWeight:600, lineHeight:1.15}}>{r.job}</div>
              <div style={{fontSize:11, color:MUTED, lineHeight:1.2}}>{r.area}</div>
              <div>
                <div style={{display:"flex", justifyContent:"space-between", alignItems:"baseline", marginBottom:3, fontSize:11}}>
                  <span style={{color:MUTED}}>
                    Median <span style={{color:INK, fontFamily:'ui-monospace, "JetBrains Mono", monospace', fontWeight:600}}>${(r.p[50]/1000)}K</span>
                  </span>
                  {isYou ? (
                    <span style={{
                      fontSize:10, padding:"2px 6px", borderRadius:10,
                      background:HI, color:"#fff",
                      fontFamily:'ui-monospace, "JetBrains Mono", monospace',
                    }}>You · {pct}th pct · $48K</span>
                  ) : (
                    <span style={{fontSize:10, color:MUTED, fontFamily:'ui-monospace, "JetBrains Mono", monospace'}}>
                      P25–75: ${(r.p[25]/1000)}K – ${(r.p[75]/1000)}K
                    </span>
                  )}
                </div>
                <PercentileBar width={chartW} domain={domain} p={r.p}
                  salary={isYou ? userSalary : null} accent={accent}/>
              </div>
              <div style={{display:"flex", alignItems:"center", gap:6}}>
                <Sparkline data={r.trend} accent={accent}/>
              </div>
            </div>
          );
        })}

        {/* axis spanning chart column */}
        <div style={{display:"grid", gridTemplateColumns:`${colJob}px ${colArea}px 1fr ${colTrend}px`, gap}}>
          <span/><span/>
          <PercentileBar width={chartW} domain={domain} p={{10:domain[0],25:domain[0],50:domain[0],75:domain[0],90:domain[0]}}
            salary={null} accent="transparent" showAxis axisTicks={ticks} height={2}/>
          <span/>
        </div>
      </div>
    </div>
  );
}

// =====================================================================
// W2 — UNIFIED AXIS · MORE NOVEL
// Both jobs pinned to a single shared axis; your salary is a single
// vertical line that crosses every row. Median delta annotation makes
// the "is it worth switching" question explicit.
// =====================================================================
function W2({ accent, rows }) {
  const W = 760;
  const visible = rows === 3 ? ["clerk", "social", "software"] : ["clerk", "social"];
  const domain = rows === 3 ? DOMAIN_3 : DOMAIN_2;
  const ticks  = rows === 3 ? TICKS_3  : TICKS_2;
  const userSalary = 48000;

  const padL = 150, padR = 16;
  const chartW = W - 32 - padL - padR;
  const [dMin, dMax] = domain;
  const x = (v) => ((v - dMin) / (dMax - dMin)) * chartW;
  const rowH = 56;
  const svgH = visible.length * rowH + 28;

  return (
    <div style={{width:W, border:`1px solid ${LINE}`, borderRadius:6, background:SHELL, overflow:"hidden"}}>
      <AgencyHeader subtitle="One axis · see exactly where your pay lands" />

      {/* compact inline controls */}
      <div style={{padding:"14px 16px", background:PAPER, borderBottom:`1px solid ${LINE}`,
                    display:"flex", flexWrap:"wrap", alignItems:"center", gap:8, fontSize:13}}>
        <span style={{color:MUTED}}>I make</span>
        <Pill value="$48,000" />
        <span style={{color:MUTED}}>as a</span>
        <Pill value="New Accounts Clerk" />
        <span style={{color:MUTED}}>in</span>
        <Pill value="Virginia Beach–Norfolk" />
        <span style={{color:MUTED, marginLeft:"auto", fontSize:11}}>vs.</span>
        <Pill value={rows===3 ? "+ 2 jobs" : "+ 1 job"} muted />
      </div>

      <div style={{padding:"14px 16px"}}>
        <div style={{display:"flex", alignItems:"center", gap:14, marginBottom:8, fontSize:11, color:MUTED}}>
          <LegendChip color="#e6e3d7" label="10–90th percentile"/>
          <LegendChip color={accent} label="25–75th"/>
          <LegendChip color={INK} label="median" tall/>
          <LegendChip color={HI} label="your salary"/>
        </div>

        <svg width={W - 32} height={svgH} style={{overflow:"visible"}}>
          {/* shared "you" vertical line behind everything */}
          <line x1={padL + x(userSalary)} x2={padL + x(userSalary)}
                y1={0} y2={visible.length * rowH + 4}
                stroke={HI} strokeWidth="2" strokeDasharray="4 4" opacity="0.85"/>
          <g transform={`translate(${padL + x(userSalary)}, 0)`}>
            <rect x={-30} y={-12} width={60} height={16} fill={HI} rx="2"/>
            <text x={0} y={0} textAnchor="middle" fontSize="10" fill="#fff"
                  fontFamily='ui-monospace, "JetBrains Mono", monospace' dy="2">YOU · $48K</text>
          </g>

          {visible.map((key, i) => {
            const r = ROWS[key];
            const yT = 8 + i * rowH;
            const isYou = key === "clerk";
            return (
              <g key={key} transform={`translate(0,${yT})`}>
                {/* label block */}
                <text x="0" y="12" fontSize="12" fontWeight="600" fill={INK}>{r.job}</text>
                <text x="0" y="26" fontSize="10" fill={MUTED}>
                  {isYou ? "your role" : "comparison"} · median ${(r.p[50]/1000)}K
                </text>
                {/* bar */}
                <g transform={`translate(${padL}, 30)`}>
                  <rect x={x(r.p[10])} y={0} width={x(r.p[90]) - x(r.p[10])} height={14}
                        fill="#e6e3d7" rx="2"/>
                  <rect x={x(r.p[25])} y={1} width={x(r.p[75]) - x(r.p[25])} height={12}
                        fill={accent} rx="1.5"/>
                  <line x1={x(r.p[50])} x2={x(r.p[50])} y1={-3} y2={17}
                        stroke={INK} strokeWidth="2"/>
                  {/* percentile-of-you readout (only on your row) */}
                  {isYou && (
                    <circle cx={x(userSalary)} cy={7} r="4" fill={HI} stroke="#fff" strokeWidth="1.5"/>
                  )}
                </g>
              </g>
            );
          })}

          {/* axis */}
          <g transform={`translate(${padL}, ${visible.length * rowH + 12})`}>
            <line x1={0} x2={chartW} y1={0} y2={0} stroke={LINE} strokeWidth="1"/>
            {ticks.map((t,i)=>(
              <g key={i} transform={`translate(${x(t)},0)`}>
                <line x1="0" x2="0" y1="0" y2="3" stroke={MUTED} strokeWidth="1"/>
                <text x="0" y="14" fontSize="10" textAnchor="middle"
                      fontFamily='ui-monospace, "JetBrains Mono", monospace' fill={MUTED}>
                  ${(t/1000)}K
                </text>
              </g>
            ))}
          </g>
        </svg>

        {/* delta callouts */}
        <div style={{display:"flex", gap:10, marginTop:6, flexWrap:"wrap"}}>
          {visible.slice(1).map((k) => {
            const r = ROWS[k];
            const delta = r.p[50] - ROWS.clerk.p[50];
            return (
              <div key={k} style={{
                fontSize:11, color:INK,
                padding:"4px 10px", border:`1px solid ${LINE}`, borderRadius:14, background:PAPER,
              }}>
                <b style={{color:accent}}>{r.job}</b>{" "}
                <span style={{color:MUTED}}>median is</span>{" "}
                <span style={{fontFamily:'ui-monospace, "JetBrains Mono", monospace', color: delta>0 ? "#1f7a4d" : HI}}>
                  {delta>0?"+":""}${Math.abs(delta/1000)}K
                </span>{" "}
                <span style={{color:MUTED}}>vs your role</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// =====================================================================
// W3 — STAT-FIRST CARDS · MOBILE-READY
// Vertical stack of cards. Each card leads with the median + your
// percentile, then the bar. Trend sparkline included. Works at narrow
// widths (mobile/embed) because the cards reflow as a column on small
// screens — no horizontal grid to break.
// =====================================================================
function W3({ accent, rows }) {
  const W = 760;
  const visible = rows === 3 ? ["clerk", "social", "software"] : ["clerk", "social"];
  const domain = rows === 3 ? DOMAIN_3 : DOMAIN_2;
  const ticks  = rows === 3 ? TICKS_3  : TICKS_2;
  const userSalary = 48000;

  return (
    <div style={{width:W, border:`1px solid ${LINE}`, borderRadius:6, background:SHELL, overflow:"hidden"}}>
      <AgencyHeader subtitle="Median, percentile, and trend for each role" />

      {/* You strip — primary identity, always on top */}
      <div style={{padding:"12px 16px", background:"#f1eee0", borderBottom:`1px solid ${LINE}`,
                    display:"flex", alignItems:"center", gap:12, flexWrap:"wrap"}}>
        <div style={{
          fontSize:10, letterSpacing:1, padding:"3px 8px", borderRadius:3,
          background:HI, color:"#fff", fontFamily:'ui-monospace, "JetBrains Mono", monospace',
        }}>YOU</div>
        <span style={{fontSize:13}}>I make</span>
        <Pill value="$48,000" />
        <span style={{fontSize:13}}>as a</span>
        <Pill value="New Accounts Clerk" />
        <span style={{fontSize:13}}>in</span>
        <Pill value="Virginia Beach–Norfolk" />
      </div>

      {/* Job cards */}
      <div style={{padding:"14px 16px", display:"grid", gap:10}}>
        {visible.map((key)=>{
          const r = ROWS[key];
          const isYou = key === "clerk";
          const pct = isYou ? approxPercentile(r.p, userSalary) : "—";
          const delta = r.p[50] - ROWS.clerk.p[50];
          return (
            <div key={key} style={{
              border:`1px solid ${LINE}`, borderRadius:6, padding:"12px 14px",
              background: isYou ? "#fafdff" : SHELL,
              borderLeft:`3px solid ${isYou ? HI : accent}`,
            }}>
              {/* head row */}
              <div style={{display:"grid", gridTemplateColumns:"1.4fr 0.8fr 0.8fr 0.7fr", gap:12, alignItems:"baseline"}}>
                <div>
                  <div style={{fontSize:10, color:MUTED, textTransform:"uppercase", letterSpacing:0.6}}>
                    {isYou ? "Your role" : "Comparison"}
                  </div>
                  <div style={{fontSize:14, fontWeight:600, marginTop:1}}>{r.job}</div>
                  <div style={{fontSize:11, color:MUTED}}>{r.area}</div>
                </div>
                <Stat label="Median"
                      value={`$${(r.p[50]/1000).toFixed(0)}K`}
                      sub={!isYou ? (delta>0?`+$${Math.round(delta/1000)}K vs you`:`–$${Math.round(-delta/1000)}K vs you`) : "annual"}/>
                <Stat label={isYou ? "Your percentile" : "If you stayed at $48K"}
                      value={isYou ? `${pct}th` : `${approxPercentile(r.p, userSalary)}th`}
                      sub={isYou ? "within your role" : "within this role"}/>
                <div>
                  <div style={{fontSize:10, color:MUTED, textTransform:"uppercase", letterSpacing:0.6, marginBottom:2}}>5-yr trend</div>
                  <Sparkline data={r.trend} accent={accent} width={86} height={24}/>
                </div>
              </div>

              {/* bar */}
              <div style={{marginTop:8}}>
                <PercentileBar width={W - 32 - 28 - 4} domain={domain} p={r.p}
                  salary={userSalary} accent={accent} height={22}/>
              </div>
            </div>
          );
        })}

        {/* shared axis */}
        <div style={{marginTop:-4, marginLeft:14, marginRight:14}}>
          <PercentileBar width={W - 32 - 28 - 4} domain={domain}
            p={{10:domain[0],25:domain[0],50:domain[0],75:domain[0],90:domain[0]}}
            salary={null} accent="transparent" showAxis axisTicks={ticks} height={2}/>
        </div>

        <div style={{display:"flex", justifyContent:"space-between", alignItems:"center", marginTop:4}}>
          <div style={{display:"flex", gap:12, fontSize:11, color:MUTED}}>
            <LegendChip color="#e6e3d7" label="10–90 pct"/>
            <LegendChip color={accent} label="25–75 pct"/>
            <LegendChip color={INK} label="median" tall/>
            <LegendChip color={HI} label="you"/>
          </div>
          <button style={btn(accent)}>+ add a job</button>
        </div>
      </div>
    </div>
  );
}

// ----- small bits ----------------------------------------------------
function Field({ label, value, noCaret }) {
  return (
    <div>
      <div style={{fontSize:10, color:MUTED, textTransform:"uppercase", letterSpacing:0.6, marginBottom:3}}>{label}</div>
      <div style={{
        background:"#fff", border:`1px solid ${LINE}`, borderRadius:3,
        padding:"6px 10px", fontSize:12, display:"flex", justifyContent:"space-between", alignItems:"center"
      }}>
        <span>{value}</span>
        {!noCaret && <span style={{color:MUTED, fontSize:9}}>▾</span>}
      </div>
    </div>
  );
}
function Pill({ value, muted }) {
  return (
    <span style={{
      display:"inline-flex", alignItems:"center", gap:4,
      background: muted ? "transparent" : "#fff",
      border:`1px solid ${muted ? LINE : INK}`,
      padding:"3px 10px", borderRadius:14, fontSize:12,
      color: muted ? MUTED : INK,
    }}>
      {value} {!muted && <span style={{color:MUTED, fontSize:9}}>▾</span>}
    </span>
  );
}
function Legend({ accent }) {
  return (
    <div style={{display:"flex", flexDirection:"column", justifyContent:"flex-end", gap:4, fontSize:11, color:MUTED}}>
      <LegendChip color="#e6e3d7" label="10th – 90th percentile"/>
      <LegendChip color={accent} label="25th – 75th percentile"/>
      <LegendChip color={HI} label="Your salary"/>
    </div>
  );
}
function LegendChip({ color, label, tall }) {
  return (
    <span style={{display:"inline-flex", alignItems:"center", gap:6}}>
      <span style={{width: tall ? 3 : 14, height: tall ? 12 : 8, background:color, borderRadius: tall ? 1 : 2, display:"inline-block"}}/>
      {label}
    </span>
  );
}
function Stat({ label, value, sub }) {
  return (
    <div>
      <div style={{fontSize:10, color:MUTED, textTransform:"uppercase", letterSpacing:0.6}}>{label}</div>
      <div style={{fontSize:18, fontFamily:'"Source Serif Pro", Georgia, serif', fontWeight:600, lineHeight:1.1}}>{value}</div>
      {sub && <div style={{fontSize:10, color:MUTED}}>{sub}</div>}
    </div>
  );
}
function btn(accent) {
  return {
    fontSize:11, padding:"5px 12px", borderRadius:3,
    border:`1px solid ${accent}`, color:accent, background:"#fff", cursor:"pointer",
    fontFamily:"inherit",
  };
}

Object.assign(window, { W1, W2, W3 });
