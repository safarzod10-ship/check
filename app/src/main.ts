import "./style.css";
import QRCode from "qrcode";
import jsQR from "jsqr";
import {
  createAccount, importAccount, loadAssets, sendTon, sendJetton, getTransactions,
  fmtAddress, JETTONS, BTC_ICON, TREASURY, isTreasuryOwner, getTreasuryInfo,
  treasurySetRate, treasuryWithdraw, treasuryTopUp, NETWORK,
  type Account, type AssetBalance, type TxItem,
} from "./ton";
import {
  saveVault, hasVault, unlock, wipe, vaultAddress,
} from "./storage";
import { fetchPrices, fetchChart, fmtSmn, type PriceInfo } from "./prices";

const app = document.getElementById("app")!;

// ---- in-memory session state (secret lives here only while unlocked) ----
let session: { mnemonic: string[]; address: string } | null = null;
let pendingAccount: Account | null = null; // during onboarding
let assetsCache: AssetBalance[] = [];

const el = (html: string): HTMLElement => {
  const d = document.createElement("div");
  d.innerHTML = html.trim();
  return d.firstElementChild as HTMLElement;
};
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

function toast(msg: string) {
  const t = el(`<div class="toast">${esc(msg)}</div>`);
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 2600);
}

// Parse a scanned QR into a TON address (+ optional amount).
function parseTonQR(data: string): { address: string; amount?: string } {
  let d = data.trim();
  // ton://transfer/<addr>?amount=<nano>
  const m = d.match(/ton:\/\/transfer\/([A-Za-z0-9_\-]+)(\?.*)?/i);
  if (m) {
    const addr = m[1];
    let amount: string | undefined;
    const q = m[2] ? new URLSearchParams(m[2].slice(1)) : null;
    const a = q?.get("amount");
    if (a && /^\d+$/.test(a)) amount = (Number(a) / 1e9).toString();
    return { address: addr, amount };
  }
  return { address: d };
}

// Open the camera and scan a QR code; resolves with the decoded string or null.
function openScanner(): Promise<string | null> {
  return new Promise(async (resolve) => {
    let stream: MediaStream | null = null;
    const ov = el(`<div class="scan-ov">
      <div class="scan-top"><div style="font-weight:700">Сканкунии QR</div><div class="x" id="sx">✕</div></div>
      <video id="sv" playsinline muted></video>
      <div class="scan-frame"><div class="box"></div></div>
      <div class="scan-hint">QR-и адресро дар чорчӯба нигоҳ доред</div>
    </div>`);
    document.body.appendChild(ov);
    const video = ov.querySelector("#sv") as HTMLVideoElement;
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d", { willReadFrequently: true })!;
    let raf = 0, done = false;
    const cleanup = (res: string | null) => {
      if (done) return; done = true;
      if (raf) cancelAnimationFrame(raf);
      if (stream) stream.getTracks().forEach((t) => t.stop());
      ov.remove(); resolve(res);
    };
    ov.querySelector("#sx")!.addEventListener("click", () => cleanup(null));
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
      video.srcObject = stream;
      await video.play();
      const tick = () => {
        if (done) return;
        if (video.readyState >= 2 && video.videoWidth) {
          canvas.width = video.videoWidth; canvas.height = video.videoHeight;
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
          const code = jsQR(img.data, img.width, img.height, { inversionAttempts: "dontInvert" });
          if (code && code.data) { cleanup(code.data.trim()); return; }
        }
        raf = requestAnimationFrame(tick);
      };
      raf = requestAnimationFrame(tick);
    } catch {
      toast("Камера дастрас нест");
      cleanup(null);
    }
  });
}

// Confirmation modal: returns true if the user confirms.
function confirmModal(title: string, rows: Array<[string, string]>, cta = "Тасдиқ"): Promise<boolean> {
  return new Promise((resolve) => {
    const m = el(`<div class="modal-ov">
      <div class="modal">
        <h3>${esc(title)}</h3>
        <div class="modal-rows">${rows.map(([k, v]) => `<div class="mrow"><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join("")}</div>
        <div class="btn-row"><button class="btn btn-ghost" id="mc">Бекор</button><button class="btn btn-primary" id="mok">${esc(cta)}</button></div>
      </div>
    </div>`);
    document.body.appendChild(m);
    const close = (res: boolean) => { m.remove(); resolve(res); };
    m.querySelector("#mc")!.addEventListener("click", () => close(false));
    m.querySelector("#mok")!.addEventListener("click", () => close(true));
    m.addEventListener("click", (e) => { if (e.target === m) close(false); });
  });
}

function brandHeader(sub = "Ҳамёни рақамии Тоҷикистон") {
  return `<div class="brand"><img src="./brand-logo.png" alt=""/><div><div class="name">SOMORA</div><div class="sub">${esc(sub)}</div></div></div>`;
}
function netBadge() {
  return NETWORK === "testnet"
    ? `<span class="testnet-badge"><span class="dot"></span>TESTNET — пулҳои санҷишӣ</span>`
    : `<span class="testnet-badge" style="color:#17b06b;border-color:rgba(23,176,107,.4);background:rgba(23,176,107,.12)"><span class="dot" style="background:#17b06b"></span>MAINNET</span>`;
}

// ---------------- Router ----------------
type Route =
  | { name: "welcome" } | { name: "create" } | { name: "backup" } | { name: "setpin" }
  | { name: "import" } | { name: "lock" } | { name: "home" } | { name: "receive" }
  | { name: "send"; asset?: string } | { name: "buy" } | { name: "settings" }
  | { name: "asset"; asset: string } | { name: "treasury" };

// ---- auto-lock after inactivity ----
let idleTimer: ReturnType<typeof setTimeout> | null = null;
const AUTO_LOCK_MS = 180000; // 3 minutes
function resetIdle() {
  if (!session) return;
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (session && hasVault()) { session = null; go({ name: "lock" }); }
  }, AUTO_LOCK_MS);
}
["touchstart", "click", "keydown"].forEach((ev) =>
  document.addEventListener(ev, resetIdle, { passive: true }));

function go(r: Route) {
  if (r.name !== "lock" && r.name !== "welcome") resetIdle();
  render(r);
}

function render(r: Route) {
  app.innerHTML = "";
  switch (r.name) {
    case "welcome": return app.appendChild(ScreenWelcome());
    case "create": return void onCreate();
    case "backup": return app.appendChild(ScreenBackup());
    case "setpin": return app.appendChild(ScreenSetPin());
    case "import": return app.appendChild(ScreenImport());
    case "lock": return app.appendChild(ScreenLock());
    case "home": return app.appendChild(ScreenHome());
    case "receive": return app.appendChild(ScreenReceive());
    case "send": return app.appendChild(ScreenSend(r.asset));
    case "buy": return app.appendChild(ScreenBuy());
    case "settings": return app.appendChild(ScreenSettings());
    case "asset": return app.appendChild(ScreenAsset(r.asset));
    case "treasury": return app.appendChild(ScreenTreasury());
  }
}

// ---------------- Onboarding ----------------
function ScreenWelcome(): HTMLElement {
  const s = el(`<div class="screen center">
    <div>
      <div class="logo-glow"><img class="logo-hero" src="./brand-logo.png" alt="SOMORA"/></div>
      <h1>SOMORA</h1>
      <p class="lead">Ҳамёни рақамии Тоҷикистон барои TON, USDT ва SOMONI. Калидҳо танҳо дар дасти шумо.</p>
    </div>
    ${netBadge()}
    <div class="center-col" style="margin-top:8px">
      <button class="btn btn-primary" id="create">Ҳамёни нав сохтан</button>
      <button class="btn btn-ghost" id="import">Воридоти ҳамён (24 калима)</button>
    </div>
    <p class="lead" style="font-size:12px;margin-top:8px">Пешфарз: TESTNET. Инро дар Танзимот иваз кардан мумкин аст.</p>
  </div>`);
  s.querySelector("#create")!.addEventListener("click", () => go({ name: "create" }));
  s.querySelector("#import")!.addEventListener("click", () => go({ name: "import" }));
  return s;
}

async function onCreate() {
  const loading = el(`<div class="screen center"><div class="center-col"><span class="spinner" style="margin:0 auto"></span><p class="lead">Сохтани ҳамён…</p></div></div>`);
  app.appendChild(loading);
  pendingAccount = await createAccount();
  go({ name: "backup" });
}

function ScreenBackup(): HTMLElement {
  const words = pendingAccount!.mnemonic;
  const grid = words.map((w, i) => `<div class="w"><b>${i + 1}.</b>${esc(w)}</div>`).join("");
  const s = el(`<div class="screen">
    ${brandHeader("Нусхаи захиравӣ")}
    <h2>24 калимаи захиравӣ</h2>
    <div class="warn">Инро рӯйнавис карда, дар ҷои бехатар нигоҳ доред. Ҳар касе ки ин калимаҳоро донад — ба маблағи шумо дастрасӣ пайдо мекунад. Онро ба касе нафиристед.</div>
    <div class="mnemonic">${grid}</div>
    <div class="btn-row">
      <button class="btn btn-ghost" id="copy">Нусха</button>
      <button class="btn btn-primary" id="next">Навиштам — идома</button>
    </div>
  </div>`);
  s.querySelector("#copy")!.addEventListener("click", async () => {
    await navigator.clipboard.writeText(words.join(" ")).catch(() => {});
    toast("Нусхабардорӣ шуд");
  });
  s.querySelector("#next")!.addEventListener("click", () => go({ name: "setpin" }));
  return s;
}

// Reusable 4-digit PIN pad: dots + numeric keypad, auto-submits at 4 digits.
interface PinPad extends HTMLElement { shake(): void; reset(): void }
function PinKeypad(onComplete: (pin: string) => void): PinPad {
  let pin = "";
  const keys = [1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => `<div class="key" data-k="${n}">${n}</div>`).join("");
  const wrap = el(`<div class="pinpad">
    <div class="pin-dots">${[0,1,2,3].map(() => '<div class="pin-dot"></div>').join("")}</div>
    <div class="keypad">
      ${keys}
      <div class="key fn" data-k="back">⌫</div>
      <div class="key" data-k="0">0</div>
      <div class="key fn" data-k="clear">✕</div>
    </div>
  </div>`) as PinPad;
  const dotsRow = wrap.querySelector(".pin-dots") as HTMLElement;
  const dots = wrap.querySelectorAll(".pin-dot");
  const render = () => dots.forEach((d, i) => d.classList.toggle("on", i < pin.length));
  wrap.querySelectorAll(".key").forEach((k) => k.addEventListener("click", () => {
    const v = k.getAttribute("data-k")!;
    if (v === "back") pin = pin.slice(0, -1);
    else if (v === "clear") pin = "";
    else if (pin.length < 4) pin += v;
    render();
    if (pin.length === 4) { const p = pin; setTimeout(() => onComplete(p), 130); }
  }));
  wrap.shake = () => { dotsRow.classList.add("shake"); setTimeout(() => { pin = ""; render(); dotsRow.classList.remove("shake"); }, 460); };
  wrap.reset = () => { pin = ""; render(); };
  return wrap;
}

function ScreenSetPin(): HTMLElement {
  let first = "";
  const s = el(`<div class="screen center pin-screen">
    <div class="pin-head">
      <div class="logo-glow"><img class="logo-hero sm" src="./brand-logo.png" alt=""/></div>
      <h2 id="t">PIN-код гузоред</h2>
      <p class="lead" id="sub">4 рақам ворид кунед — бо он калидҳо рамзгузорӣ мешаванд</p>
    </div>
    <div id="padhost"></div>
  </div>`);
  const host = s.querySelector("#padhost")!;
  const setStep = (t: string, sub: string) => {
    (s.querySelector("#t") as HTMLElement).textContent = t;
    (s.querySelector("#sub") as HTMLElement).textContent = sub;
  };
  const pad = PinKeypad(async (pin) => {
    if (!first) {
      first = pin;
      setStep("Такрори PIN", "PIN-ро боз як бор ворид кунед");
      pad.reset();
    } else if (pin === first) {
      await saveVault(pendingAccount!, pin);
      session = { mnemonic: pendingAccount!.mnemonic, address: pendingAccount!.address };
      pendingAccount = null;
      go({ name: "home" });
    } else {
      first = "";
      setStep("PIN-код гузоред", "PIN мувофиқат накард — боз кӯшиш кунед");
      pad.shake();
    }
  });
  host.appendChild(pad);
  return s;
}

function ScreenImport(): HTMLElement {
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Воридоти ҳамён</h2></div>
    <p class="lead" style="margin:0">24 калимаи захиравии худро ворид кунед (бо фосила).</p>
    <label class="field"><div class="lbl">Калимаҳои захиравӣ</div><textarea id="words" placeholder="word1 word2 …"></textarea></label>
    <button class="btn btn-primary" id="go">Идома</button>
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "welcome" }));
  s.querySelector("#go")!.addEventListener("click", async () => {
    const raw = (s.querySelector("#words") as HTMLTextAreaElement).value.trim().toLowerCase();
    const words = raw.split(/\s+/).filter(Boolean);
    if (words.length !== 24) return toast("Бояд маҳз 24 калима бошад");
    try {
      pendingAccount = await importAccount(words);
      go({ name: "setpin" });
    } catch (e: any) { toast(e.message || "Хатогӣ"); }
  });
  return s;
}

function ScreenLock(): HTMLElement {
  const addr = vaultAddress() || "";
  const s = el(`<div class="screen center pin-screen">
    <div class="pin-head">
      <div class="logo-glow"><img class="logo-hero sm" src="./brand-logo.png" alt=""/></div>
      <h2>SOMORA</h2>
      <p class="lead mono-sm">${esc(fmtAddress(addr, 6, 6))}</p>
      <p class="lead" id="hint">PIN-кодро ворид кунед</p>
    </div>
    <div id="padhost"></div>
    <button class="btn-link danger" id="reset">Ҳамёнро нест кардан</button>
  </div>`);
  const pad = PinKeypad(async (pin) => {
    try {
      const mnemonic = await unlock(pin);
      session = { mnemonic, address: addr };
      go({ name: "home" });
    } catch {
      (s.querySelector("#hint") as HTMLElement).textContent = "PIN нодуруст — боз кӯшиш кунед";
      pad.shake();
    }
  });
  s.querySelector("#padhost")!.appendChild(pad);
  s.querySelector("#reset")!.addEventListener("click", () => {
    if (confirm("Ҳамёнро нест кунам? Бе калимаҳои захиравӣ онро барқарор карда наметавонед.")) {
      wipe(); session = null; go({ name: "welcome" });
    }
  });
  return s;
}

// ---------------- Main app ----------------
function changeHtml(ch: number): string {
  if (!ch) return "";
  const up = ch >= 0;
  return `<span class="chg ${up ? "up" : "down"}">${up ? "▲" : "▼"} ${Math.abs(ch).toFixed(2)}%</span>`;
}

function _unusedFmtSomoni(n: number): string {
  const s = n.toFixed(2).replace(".", ",");
  // group thousands with thin spaces
  const [whole, frac] = s.split(",");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  return `${grouped},${frac} смн`;
}

// Coin icon: loads the token's own published image, with a graceful
// colored-initial fallback if the network/image is unavailable.
function assetSymbolBadge(a: { symbol: string; color: string; icon?: string }) {
  const letter = esc(a.symbol[0]);
  const fallback = `this.replaceWith(Object.assign(document.createElement('div'),{className:'sym',style:'background:${a.color}',textContent:'${letter}'}))`;
  if (a.icon) {
    return `<img class="sym coin-img" src="${esc(a.icon)}" alt="${esc(a.symbol)}" onerror="${fallback}"/>`;
  }
  return `<div class="sym" style="background:${a.color}">${letter}</div>`;
}

function ScreenHome(): HTMLElement {
  const addr = session!.address;
  const s = el(`<div class="screen home">
    <div class="ptr" id="ptr"><span class="spinner"></span></div>

    <div class="home-hero">
      <div class="home-top">${brandHeader()} ${netBadge()}</div>
      <div class="balance-block">
        <div class="label">Баланси умумӣ</div>
        <div class="amount" id="total">—</div>
        <div class="addr-chip" id="copyaddr"><span>${esc(fmtAddress(addr, 6, 6))}</span><span class="copy-ic">⧉</span></div>
      </div>
    </div>

    <div class="act-row">
      <div class="act" id="a-send"><div class="act-ic">↑</div><div class="act-t">Ирсол</div></div>
      <div class="act" id="a-recv"><div class="act-ic">↓</div><div class="act-t">Қабул</div></div>
      <div class="act" id="a-buy"><div class="act-ic">⇄</div><div class="act-t">Своп</div></div>
      <div class="act" id="a-set"><div class="act-ic">⚙</div><div class="act-t">Танзим</div></div>
    </div>

    <div class="section-title">Дороиҳо</div>
    <div class="list" id="assets">
      ${[0,1,2,3].map(()=>`<div class="asset"><div class="sym skeleton" style="background:none"></div><div class="meta"><div class="skeleton" style="height:13px;width:70%"></div><div class="skeleton" style="height:10px;width:40%;margin-top:8px"></div></div><div class="skeleton" style="height:14px;width:42px"></div></div>`).join("")}
    </div>
  </div>`);

  s.querySelector("#copyaddr")!.addEventListener("click", async () => {
    await navigator.clipboard.writeText(addr).catch(() => {}); toast("Адрес нусхабардорӣ шуд");
  });
  s.querySelector("#a-send")!.addEventListener("click", () => go({ name: "send" }));
  s.querySelector("#a-recv")!.addEventListener("click", () => go({ name: "receive" }));
  s.querySelector("#a-buy")!.addEventListener("click", () => go({ name: "buy" }));
  s.querySelector("#a-set")!.addEventListener("click", () => go({ name: "settings" }));

  attachPullToRefresh(s, () => refreshAssets(s));
  refreshAssets(s);
  s.appendChild(TabBar("home"));
  return s;
}

// Swipe down from the top to refresh — like native wallets.
function attachPullToRefresh(screen: HTMLElement, onRefresh: () => Promise<void>) {
  const ptr = screen.querySelector("#ptr") as HTMLElement;
  const THRESH = 72;
  let startY = 0, pulling = false, dy = 0, busy = false;
  screen.addEventListener("touchstart", (e) => {
    if (busy || window.scrollY > 4) return;
    startY = e.touches[0].clientY; pulling = true; dy = 0;
    screen.style.transition = "";
  }, { passive: true });
  screen.addEventListener("touchmove", (e) => {
    if (!pulling) return;
    dy = e.touches[0].clientY - startY;
    if (dy > 0) {
      const pull = Math.min(dy * 0.5, 96);
      screen.style.transform = `translateY(${pull}px)`;
      ptr.style.opacity = String(Math.min(pull / THRESH, 1));
      ptr.classList.toggle("ready", pull >= THRESH);
    }
  }, { passive: true });
  screen.addEventListener("touchend", async () => {
    if (!pulling) return; pulling = false;
    const trigger = dy * 0.5 >= THRESH;
    screen.style.transition = "transform .28s cubic-bezier(.22,1,.36,1)";
    if (trigger) {
      busy = true;
      screen.style.transform = "translateY(52px)";
      ptr.classList.add("spin");
      try { await onRefresh(); } catch {}
    }
    screen.style.transform = "translateY(0)";
    setTimeout(() => {
      ptr.classList.remove("spin", "ready");
      ptr.style.opacity = "0";
      screen.style.transition = "";
      busy = false;
    }, 300);
  });
}

async function refreshAssets(scope: HTMLElement) {
  const list = scope.querySelector("#assets")!;
  const totalEl = scope.querySelector("#total")!;
  try {
    const [assets, prices] = await Promise.all([
      loadAssets(NETWORK, session!.address),
      fetchPrices(),
    ]);
    assetsCache = assets;
    let totalSmn = 0;
    list.innerHTML = "";
    const rows: Array<AssetBalance & { watch?: boolean }> = [
      ...assets,
      { id: "btc", name: "Bitcoin", symbol: "BTC", color: "#F7931A", icon: BTC_ICON, amount: "0", decimals: 8, watch: true },
    ];
    for (const a of rows) {
      const p: PriceInfo | undefined = prices[a.symbol];
      const smn = parseFloat(a.amount) * (p?.smn ?? 0);
      if (!a.watch) totalSmn += smn;
      const notDeployed = a.id === "somoni" && !JETTONS.find(j => j.id === "somoni")!.master[NETWORK];
      const sub = p && p.smn
        ? `<span class="px">${fmtSmn(p.smn, p.smn < 1 ? 4 : 2)}</span> ${changeHtml(p.change24)}`
        : (a.watch ? '<span class="muted">cross-chain</span>' : (notDeployed ? '<span class="muted">деплой кунед</span>' : `<span class="muted">${esc(a.symbol)}</span>`));
      const valueLine = a.watch ? '<div class="f muted">дигар шабака</div>' : (smn ? `<div class="f">${fmtSmn(smn)}</div>` : "");
      const row = el(`<div class="asset">
        ${assetSymbolBadge(a)}
        <div class="meta"><div class="n">${esc(a.name)}</div><div class="s">${sub}</div></div>
        <div class="val"><div class="a">${esc(a.amount)}</div>${valueLine}</div>
      </div>`);
      if (!a.watch) row.addEventListener("click", () => go({ name: "asset", asset: a.id }));
      list.appendChild(row);
    }
    totalEl.textContent = fmtSmn(totalSmn);
  } catch {
    list.innerHTML = `<div class="warn">Шабака дастнорас. Поён кашед, то нав кунед.</div>`;
    totalEl.textContent = "—";
  }
}

// Simple SVG line chart from a price series.
function lineChart(points: number[], up: boolean): string {
  if (!points || points.length < 2) return `<div class="chart-empty muted">Маълумоти график нест</div>`;
  const w = 320, h = 120, pad = 6;
  const min = Math.min(...points), max = Math.max(...points);
  const range = (max - min) || 1;
  const stepX = (w - pad * 2) / (points.length - 1);
  const coords = points.map((p, i) => [pad + i * stepX, h - pad - ((p - min) / range) * (h - pad * 2)]);
  const d = coords.map((c, i) => (i ? "L" : "M") + c[0].toFixed(1) + " " + c[1].toFixed(1)).join(" ");
  const area = `${d} L ${w - pad} ${h - pad} L ${pad} ${h - pad} Z`;
  const color = up ? "#27e39b" : "#ff5e7a";
  const id = "cg" + Math.random().toString(36).slice(2, 7);
  return `<svg viewBox="0 0 ${w} ${h}" class="chart" preserveAspectRatio="none">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${color}" stop-opacity="0.35"/>
      <stop offset="1" stop-color="${color}" stop-opacity="0"/>
    </linearGradient></defs>
    <path d="${area}" fill="url(#${id})"/>
    <path d="${d}" fill="none" stroke="${color}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>
  </svg>`;
}

// Show a transaction comment only when it is human-readable text (not binary/base64).
function cleanComment(c: string): string {
  if (!c) return "";
  const s = c.trim();
  if (!s || /=\s*$/.test(s)) return "";
  const weird = s.replace(/[\p{L}\p{N}\s.,!?@#%:;*()/_+\-]/gu, "");
  if (weird.length > 0) return "";
  return s.slice(0, 18);
}

function timeAgo(sec: number): string {
  const diff = Math.max(0, Date.now() / 1000 - sec);
  if (diff < 60) return "ҳозир";
  if (diff < 3600) return `${Math.floor(diff / 60)} дақ пеш`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} соат пеш`;
  return `${Math.floor(diff / 86400)} рӯз пеш`;
}

function ScreenAsset(assetId: string): HTMLElement {
  const a = assetsCache.find((x) => x.id === assetId)
    || { id: assetId, name: assetId, symbol: assetId.toUpperCase(), color: "#888", icon: "", amount: "0", decimals: 9 };
  const explorer = NETWORK === "testnet" ? "https://testnet.tonviewer.com" : "https://tonviewer.com";
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>${esc(a.name)}</h2></div>

    <div class="card asset-head">
      ${assetSymbolBadge(a)}
      <div class="ah-amount"><div class="a" id="bal">${esc(a.amount)} ${esc(a.symbol)}</div>
        <div class="f" id="val">—</div></div>
    </div>

    <div class="card">
      <div class="row-between" style="margin-bottom:8px">
        <div><div class="muted" style="font-size:12px">Нарх</div><div id="price" style="font-weight:700;font-family:'Space Grotesk'">—</div></div>
        <div id="chg"></div>
      </div>
      <div id="chart"><div class="chart-empty muted"><span class="spinner"></span></div></div>
      <div class="muted" style="font-size:11px;text-align:right;margin-top:4px">7 рӯзи охир</div>
    </div>

    <div class="btn-row">
      <button class="btn btn-primary" id="send">↑ Ирсол</button>
      <button class="btn btn-ghost" id="recv">↓ Қабул</button>
    </div>

    <div class="section-title">Амалиёти охир</div>
    <div class="list" id="tx"><div class="muted" style="padding:10px 4px"><span class="spinner"></span> Боркунӣ…</div></div>
  </div>`);

  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  s.querySelector("#send")!.addEventListener("click", () => go({ name: "send", asset: assetId }));
  s.querySelector("#recv")!.addEventListener("click", () => go({ name: "receive" }));

  // prices + value + chart
  (async () => {
    const prices = await fetchPrices();
    const p = prices[a.symbol];
    if (p) {
      (s.querySelector("#price") as HTMLElement).textContent = fmtSmn(p.smn, p.smn < 1 ? 4 : 2);
      (s.querySelector("#chg") as HTMLElement).innerHTML = changeHtml(p.change24);
      const smn = parseFloat(a.amount) * p.smn;
      (s.querySelector("#val") as HTMLElement).textContent = smn ? "≈ " + fmtSmn(smn) : "";
    }
    const chartEl = s.querySelector("#chart") as HTMLElement;
    if (a.symbol === "SOMONI") {
      chartEl.innerHTML = `<div class="chart-empty muted">SOMONI — курс устувор: 1,00 смн</div>`;
    } else {
      const series = await fetchChart(a.symbol, 7);
      chartEl.innerHTML = lineChart(series, (p?.change24 ?? 0) >= 0);
    }
  })();

  // transaction history (account level, TON)
  (async () => {
    const txs = await getTransactions(NETWORK, session!.address, 20);
    const list = s.querySelector("#tx") as HTMLElement;
    if (!txs.length) { list.innerHTML = `<div class="muted" style="padding:10px 4px">Амалиёт нест</div>`; return; }
    list.innerHTML = "";
    for (const t of txs.slice(0, 15)) {
      const inc = t.dir === "in";
      const amt = parseFloat(t.amount);
      const cmt = cleanComment(t.comment);
      const row = el(`<div class="tx-row">
        <div class="tx-ic ${inc ? "in" : "out"}">${inc ? "↓" : "↑"}</div>
        <div class="tx-meta"><div class="n">${inc ? "Қабул" : "Ирсол"}${cmt ? ' · ' + esc(cmt) : ""}</div>
          <div class="s">${esc(fmtAddress(t.peer, 6, 4))} · ${timeAgo(t.time)}</div></div>
        <div class="tx-amt ${inc ? "in" : "out"}">${inc ? "+" : "−"}${amt.toFixed(amt < 1 ? 4 : 2)} TON</div>
      </div>`);
      row.addEventListener("click", () => window.open(`${explorer}/transaction/${t.hash}`, "_blank"));
      list.appendChild(row);
    }
    const note = el(`<div class="muted" style="font-size:11px;padding:6px 4px">Таърих — амалиёти TON-и ҳамён. Барои тафсилот explorer-ро кушоед.</div>`);
    list.appendChild(note);
  })();

  s.appendChild(TabBar("home"));
  return s;
}

function ScreenReceive(): HTMLElement {
  const addr = session!.address;
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Қабули маблағ</h2></div>
    <div class="card center-col" style="align-items:center">
      <div class="qr"><img id="qr" alt="QR"/></div>
      <div class="mono" style="text-align:center">${esc(addr)}</div>
      <button class="btn btn-gold" id="copy">Нусхабардории адрес</button>
    </div>
    <p class="lead">Танҳо дороиҳои шабакаи <b>TON (${NETWORK})</b> ба ин адрес фиристед.</p>
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  s.querySelector("#copy")!.addEventListener("click", async () => {
    await navigator.clipboard.writeText(addr).catch(() => {}); toast("Нусхабардорӣ шуд");
  });
  QRCode.toDataURL(addr, { margin: 1, width: 240 }).then((url) => {
    (s.querySelector("#qr") as HTMLImageElement).src = url;
  });
  s.appendChild(TabBar("home"));
  return s;
}

function ScreenSend(assetId = "ton"): HTMLElement {
  const assets = assetsCache.length ? assetsCache : [{ id: "ton", symbol: "TON", name: "Toncoin", color: "#0098EA", amount: "0", decimals: 9 }];
  const options = assets.filter(a => a.id !== "btc").map(a => `<option value="${a.id}" ${a.id === assetId ? "selected" : ""}>${esc(a.symbol)} — ${esc(a.amount)}</option>`).join("");
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Ирсоли маблағ</h2></div>
    <label class="field"><div class="lbl">Дороӣ</div><select id="asset">${options}</select></label>
    <label class="field"><div class="lbl">Адреси қабулкунанда</div><div class="field-with-btn"><input id="to" placeholder="EQ… / UQ…"/><div class="scan-btn" id="scan" title="Сканкунии QR">⛶</div></div></label>
    <label class="field"><div class="lbl">Миқдор</div><input id="amt" inputmode="decimal" placeholder="0.0"/></label>
    <label class="field"><div class="lbl">Эзоҳ (ихтиёрӣ)</div><input id="memo" placeholder=""/></label>
    <div class="warn">Амалиёт бебозгашт аст. Адрес ва миқдорро санҷед.</div>
    <button class="btn btn-primary" id="send">Фиристодан</button>
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  s.querySelector("#send")!.addEventListener("click", async () => {
    const id = (s.querySelector("#asset") as HTMLSelectElement).value;
    const to = (s.querySelector("#to") as HTMLInputElement).value.trim();
    const amt = (s.querySelector("#amt") as HTMLInputElement).value.trim();
    const memo = (s.querySelector("#memo") as HTMLInputElement).value.trim();
    if (!to) return toast("Адресро ворид кунед");
    if (!(parseFloat(amt) > 0)) return toast("Миқдори дуруст ворид кунед");
    const sym = id === "ton" ? "TON" : (JETTONS.find(j => j.id === id)?.symbol || id.toUpperCase());
    const ok = await confirmModal("Тасдиқи ирсол", [
      ["Дороӣ", sym],
      ["Ба", fmtAddress(to, 8, 8)],
      ["Миқдор", `${amt} ${sym}`],
      ["Эзоҳ", memo || "—"],
      ["Шабака", NETWORK],
    ], "Фиристодан");
    if (!ok) return;
    const btn = s.querySelector("#send") as HTMLButtonElement;
    btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    try {
      if (id === "ton") {
        await sendTon(NETWORK, session!.mnemonic, to, amt, memo);
      } else {
        const def = JETTONS.find(j => j.id === id)!;
        await sendJetton(NETWORK, def, session!.mnemonic, to, amt, memo);
      }
      toast("Фиристода шуд ✓");
      setTimeout(() => go({ name: "home" }), 800);
    } catch (e: any) {
      toast(e.message || "Хатогии ирсол");
      btn.disabled = false; btn.textContent = "Фиристодан";
    }
  });
  s.querySelector("#scan")!.addEventListener("click", async () => {
    const data = await openScanner();
    if (!data) return;
    const { address, amount } = parseTonQR(data);
    (s.querySelector("#to") as HTMLInputElement).value = address;
    if (amount) (s.querySelector("#amt") as HTMLInputElement).value = amount;
    toast("Адрес аз QR ворид шуд");
  });
  s.appendChild(TabBar("home"));
  return s;
}

function ScreenBuy(): HTMLElement {
  const t = TREASURY[NETWORK];
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Хариди SOMONI</h2></div>
    <div class="card center-col">
      <label class="field"><div class="lbl">Пардохт</div><input value="TON" disabled/></label>
      <div class="swap-arrow">⇅</div>
      <label class="field"><div class="lbl">Мегиред (SOMONI)</div><input id="get" value="0" disabled/></label>
      <label class="field"><div class="lbl">Миқдори TON${t ? ` (мин. ${t.min})` : ""}</div><input id="amt" inputmode="decimal" placeholder="0.0"/></label>
      <div class="muted" id="rate" style="font-size:13px">${t ? `Қурб: 1 TON = ${t.rate} SOMONI` : ""}</div>
      <button class="btn btn-gold" id="swap">Харидани SOMONI</button>
    </div>
    ${t
      ? `<p class="lead" style="font-size:12px">TON ба казначейии SOMORA меравад, SOMONI худкор ба ҳамёни шумо бармегардад (чанд сония). Шабака: ${NETWORK}.</p>`
      : `<div class="warn">Дар ин шабака казначейство ҳанӯз насб нашудааст.</div>`}
  </div>`);
  const getEl = s.querySelector("#get") as HTMLInputElement;
  const amtEl = s.querySelector("#amt") as HTMLInputElement;
  const recalc = () => {
    const amt = parseFloat(amtEl.value.replace(",", ".")) || 0;
    getEl.value = (amt * (t?.rate ?? 0)).toLocaleString("ru-RU", { maximumFractionDigits: 2 });
  };
  amtEl.addEventListener("input", recalc);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  s.querySelector("#swap")!.addEventListener("click", async () => {
    if (!t) return toast("Казначейство дар ин шабака нест");
    const amt = parseFloat(amtEl.value.replace(",", ".")) || 0;
    if (amt < t.min) return toast(`Миқдори ҳадди ақал ${t.min} TON`);
    const btn = s.querySelector("#swap") as HTMLButtonElement;
    btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    try {
      await sendTon(NETWORK, session!.mnemonic, t.address, String(amt)); // empty body → buy
      toast("Фиристода шуд ✓ SOMONI дар чанд сония меояд");
      setTimeout(() => go({ name: "home" }), 1400);
    } catch (e: any) {
      toast(e.message || "Хатогии харид");
      btn.disabled = false; btn.textContent = "Харидани SOMONI";
    }
  });
  s.appendChild(TabBar("home"));
  return s;
}

function ScreenTreasury(): HTMLElement {
  const owner = isTreasuryOwner(NETWORK, session!.address);
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Казначейство</h2></div>
    ${!owner ? `<div class="warn">Танҳо соҳиби казначейство дастрасӣ дорад.</div>` : `
    <div class="card">
      <div class="row-between"><div class="muted" style="font-size:13px">Баланси казна (TON)</div><div id="tbal" style="font-weight:700;font-family:'Space Grotesk'">—</div></div>
      <div class="row-between" style="margin-top:8px"><div class="muted" style="font-size:13px">Захираи SOMONI</div><div id="tsom" style="font-weight:700;font-family:'Space Grotesk'">—</div></div>
      <div class="row-between" style="margin-top:8px"><div class="muted" style="font-size:13px">Курс (SOMONI/TON)</div><div id="trate" style="font-weight:700;font-family:'Space Grotesk'">—</div></div>
    </div>

    <div class="section-title">Иваз кардани курс</div>
    <div class="card center-col">
      <label class="field"><div class="lbl">Курси нав (SOMONI барои 1 TON)</div><input id="rate" inputmode="decimal" placeholder="10"/></label>
      <button class="btn btn-primary" id="setrate">Курсро нав кардан</button>
    </div>

    <div class="section-title">Бардоштани TON</div>
    <div class="card center-col">
      <label class="field"><div class="lbl">Миқдори TON ба ҳамёни шумо</div><input id="wd" inputmode="decimal" placeholder="0.0"/></label>
      <button class="btn btn-gold" id="withdraw">Бардоштан</button>
    </div>

    <div class="section-title">Пополнени захираи SOMONI</div>
    <div class="card center-col">
      <label class="field"><div class="lbl">Миқдори SOMONI ба казна</div><input id="top" inputmode="decimal" placeholder="0"/></label>
      <button class="btn btn-ghost" id="topup">Илова кардан</button>
    </div>
    <p class="lead" style="font-size:12px">Ҳамаи амалиётро шумо ҳамчун соҳиб имзо мекунед. Шабака: ${NETWORK}.</p>
    `}
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "settings" }));
  if (!owner) { s.appendChild(TabBar("settings")); return s; }

  const refresh = async () => {
    const info = await getTreasuryInfo(NETWORK);
    if (!info) return;
    (s.querySelector("#tbal") as HTMLElement).textContent = parseFloat(info.ton).toFixed(3) + " TON";
    (s.querySelector("#tsom") as HTMLElement).textContent = parseFloat(info.somoni).toLocaleString("ru-RU");
    (s.querySelector("#trate") as HTMLElement).textContent = String(info.rate);
  };
  refresh();

  const run = async (btnSel: string, fn: () => Promise<void>, okMsg: string) => {
    const btn = s.querySelector(btnSel) as HTMLButtonElement;
    const txt = btn.textContent;
    btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    try { await fn(); toast(okMsg); setTimeout(refresh, 6000); }
    catch (e: any) { toast(e.message || "Хатогӣ"); }
    finally { btn.disabled = false; btn.textContent = txt; }
  };

  s.querySelector("#setrate")!.addEventListener("click", () => {
    const v = (s.querySelector("#rate") as HTMLInputElement).value.trim().replace(",", ".");
    if (!(parseFloat(v) > 0)) return toast("Курси дуруст ворид кунед");
    run("#setrate", () => treasurySetRate(NETWORK, session!.mnemonic, v), "Курс нав шуд ✓");
  });
  s.querySelector("#withdraw")!.addEventListener("click", () => {
    const v = (s.querySelector("#wd") as HTMLInputElement).value.trim().replace(",", ".");
    if (!(parseFloat(v) > 0)) return toast("Миқдори дуруст ворид кунед");
    run("#withdraw", () => treasuryWithdraw(NETWORK, session!.mnemonic, v), "Бардошта шуд ✓");
  });
  s.querySelector("#topup")!.addEventListener("click", () => {
    const v = (s.querySelector("#top") as HTMLInputElement).value.trim().replace(",", ".");
    if (!(parseFloat(v) > 0)) return toast("Миқдори дуруст ворид кунед");
    run("#topup", () => treasuryTopUp(NETWORK, session!.mnemonic, v), "Илова шуд ✓");
  });

  s.appendChild(TabBar("settings"));
  return s;
}

function ScreenSettings(): HTMLElement {
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Танзимот</h2></div>
    <div class="card">
      <div class="row-between"><div class="n" style="font-weight:700">Адреси ҳамён</div></div>
      <div class="mono" style="margin-top:8px">${esc(session?.address || vaultAddress() || "")}</div>
    </div>
    ${isTreasuryOwner(NETWORK, session?.address || "") ? `<button class="btn btn-primary" id="treasury">⚙ Идоракунии казначейство</button>` : ""}
    <button class="btn btn-ghost" id="lock">Қулф кардан</button>
    <button class="btn btn-danger" id="wipe">Нест кардани ҳамён аз дастгоҳ</button>
    <p class="lead" style="font-size:12px">SOMORA — ҳамёни ғайрикастодиалӣ. Калидҳо танҳо дар дастгоҳи шумо нигоҳ дошта мешаванд.</p>
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  const tbtn = s.querySelector("#treasury");
  if (tbtn) tbtn.addEventListener("click", () => go({ name: "treasury" }));
  s.querySelector("#lock")!.addEventListener("click", () => { session = null; go({ name: "lock" }); });
  s.querySelector("#wipe")!.addEventListener("click", () => {
    if (confirm("Ҳамёнро аз ин дастгоҳ нест кунам?")) { wipe(); session = null; go({ name: "welcome" }); }
  });
  s.appendChild(TabBar("settings"));
  return s;
}

function TabBar(active: string): HTMLElement {
  const tab = el(`<div class="tabbar">
    <div class="tab ${active === "home" ? "active" : ""}" id="t-home"><span class="ti">◇</span>Асосӣ</div>
    <div class="tab" id="t-recv"><span class="ti">↓</span>Қабул</div>
    <div class="tab" id="t-buy"><span class="ti">⇄</span>Хариди</div>
    <div class="tab ${active === "settings" ? "active" : ""}" id="t-set"><span class="ti">⚙</span>Танзим</div>
  </div>`);
  tab.querySelector("#t-home")!.addEventListener("click", () => go({ name: "home" }));
  tab.querySelector("#t-recv")!.addEventListener("click", () => go({ name: "receive" }));
  tab.querySelector("#t-buy")!.addEventListener("click", () => go({ name: "buy" }));
  tab.querySelector("#t-set")!.addEventListener("click", () => go({ name: "settings" }));
  return tab;
}

// ---------------- boot ----------------
function boot() {
  if (hasVault()) go({ name: "lock" });
  else go({ name: "welcome" });
  // dismiss the splash once the first screen is painted
  const splash = document.getElementById("splash");
  if (splash) {
    const hide = () => splash.classList.add("hide");
    setTimeout(hide, 1100);
    setTimeout(() => splash.remove(), 1700);
  }
}
boot();
