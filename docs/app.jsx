// App shell — three wireframes on a DesignCanvas, plus a Tweaks panel
// for toggling 2 vs 3 comparison rows and the accent color.

const { useState, useEffect } = React;

function App() {
  const [accent, setAccent] = useState("#2a4470");   // Virginia agency navy
  const [rows, setRows]     = useState(2);

  useEffect(() => {
    document.documentElement.style.setProperty("--accent", accent);
  }, [accent]);

  // Wire up the tweaks DOM (kept outside React so the panel is overlaid
  // on top of the design canvas without fighting its transforms).
  useEffect(() => {
    const panel = document.getElementById("tweaks");
    const onMsg = (e) => {
      const t = e.data && e.data.type;
      if (t === "__activate_edit_mode")   panel.classList.add("on");
      if (t === "__deactivate_edit_mode") panel.classList.remove("on");
    };
    window.addEventListener("message", onMsg);
    window.parent.postMessage({ type: "__edit_mode_available" }, "*");

    const swatches = panel.querySelectorAll(".swatch");
    swatches.forEach(sw => {
      sw.onclick = () => {
        swatches.forEach(s => s.classList.remove("on"));
        sw.classList.add("on");
        setAccent(sw.dataset.color);
      };
    });
    const rowBtns = panel.querySelectorAll("button.rowsbtn");
    rowBtns.forEach(b => {
      b.onclick = () => {
        rowBtns.forEach(t => t.classList.remove("on"));
        b.classList.add("on");
        setRows(parseInt(b.dataset.rows, 10));
      };
    });
    return () => window.removeEventListener("message", onMsg);
  }, []);

  // Artboards are sized close to the typical Tableau embed footprint —
  // ~760 px wide. Heights chosen per layout so each fits without overflow.
  const artboards = [
    { id:"w1", label:"W1 · Faithful · reference-like layout, sharpened",  w:760, h: rows===3 ? 470 : 410, El:W1 },
    { id:"w2", label:"W2 · Unified axis · novel · single 'You' line",      w:760, h: rows===3 ? 380 : 330, El:W2 },
    { id:"w3", label:"W3 · Stat-first cards · mobile-ready · trend-aware", w:760, h: rows===3 ? 510 : 400, El:W3 },
  ];

  return (
    <DesignCanvas>
      <DCSection
        id="wires"
        title="Salary comparison · wireframes"
        subtitle="Embedded viz for a Virginia Works page · 3 directions · ~760 px wide"
      >
        {artboards.map(a => (
          <DCArtboard key={a.id} id={a.id} label={a.label} width={a.w} height={a.h}>
            <a.El accent={accent} rows={rows} />
          </DCArtboard>
        ))}
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
