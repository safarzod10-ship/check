import "./style.css";
import QRCode from "qrcode";
import {
  createAccount, importAccount, loadAssets, sendTon, sendJetton,
  fmtAddress, JETTONS, BTC_ICON, type Account, type AssetBalance, type Net,
} from "./ton";
import {
  saveVault, hasVault, unlock, wipe, vaultAddress, getSettings, setSettings,
} from "./storage";
import { fetchPrices, fmtSmn, type PriceInfo } from "./prices";

const app = document.getElementById("app")!;

// ---- in-memory session state (secret lives here only while unlocked) ----
let session: { mnemonic: string[]; address: string } | null = null;
let settings = getSettings();
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

function brandHeader(sub = "Ҳамёни рақамии Тоҷикистон") {
  return `<div class="brand"><img src="./brand-logo.png" alt=""/><div><div class="name">SOMORA</div><div class="sub">${esc(sub)}</div></div></div>`;
}
function netBadge() {
  return settings.net === "testnet"
    ? `<span class="testnet-badge"><span class="dot"></span>TESTNET — пулҳои санҷишӣ</span>`
    : `<span class="testnet-badge" style="color:#17b06b;border-color:rgba(23,176,107,.4);background:rgba(23,176,107,.12)"><span class="dot" style="background:#17b06b"></span>MAINNET</span>`;
}

// ---------------- Router ----------------
type Route =
  | { name: "welcome" } | { name: "create" } | { name: "backup" } | { name: "setpin" }
  | { name: "import" } | { name: "lock" } | { name: "home" } | { name: "receive" }
  | { name: "send"; asset?: string } | { name: "buy" } | { name: "settings" };

function go(r: Route) { render(r); }

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
    <div class="home-top">${brandHeader()} ${netBadge()}</div>

    <div class="ptr" id="ptr"><span class="spinner"></span></div>

    <div class="balance-block">
      <div class="label">Баланси умумӣ</div>
      <div class="amount" id="total">—</div>
      <div class="addr-chip" id="copyaddr"><span>${esc(fmtAddress(addr, 6, 6))}</span><span class="copy-ic">⧉</span></div>
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
      loadAssets(settings.net, session!.address),
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
      const notDeployed = a.id === "somoni" && !JETTONS.find(j => j.id === "somoni")!.master[settings.net];
      const sub = p && p.smn
        ? `<span class="px">${fmtSmn(p.smn, p.smn < 1 ? 4 : 2)}</span> ${changeHtml(p.change24)}`
        : (a.watch ? '<span class="muted">cross-chain</span>' : (notDeployed ? '<span class="muted">деплой кунед</span>' : `<span class="muted">${esc(a.symbol)}</span>`));
      const valueLine = a.watch ? '<div class="f muted">дигар шабака</div>' : (smn ? `<div class="f">${fmtSmn(smn)}</div>` : "");
      const row = el(`<div class="asset">
        ${assetSymbolBadge(a)}
        <div class="meta"><div class="n">${esc(a.name)}</div><div class="s">${sub}</div></div>
        <div class="val"><div class="a">${esc(a.amount)}</div>${valueLine}</div>
      </div>`);
      if (!a.watch) row.addEventListener("click", () => go({ name: "send", asset: a.id }));
      list.appendChild(row);
    }
    totalEl.textContent = fmtSmn(totalSmn);
  } catch {
    list.innerHTML = `<div class="warn">Шабака дастнорас. Поён кашед, то нав кунед.</div>`;
    totalEl.textContent = "—";
  }
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
    <p class="lead">Танҳо дороиҳои шабакаи <b>TON (${settings.net})</b> ба ин адрес фиристед.</p>
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
    <label class="field"><div class="lbl">Адреси қабулкунанда</div><input id="to" placeholder="EQ… / UQ…"/></label>
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
    const btn = s.querySelector("#send") as HTMLButtonElement;
    btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    try {
      if (id === "ton") {
        await sendTon(settings.net, session!.mnemonic, to, amt, memo);
      } else {
        const def = JETTONS.find(j => j.id === id)!;
        await sendJetton(settings.net, def, session!.mnemonic, to, amt, memo);
      }
      toast("Фиристода шуд ✓");
      setTimeout(() => go({ name: "home" }), 800);
    } catch (e: any) {
      toast(e.message || "Хатогии ирсол");
      btn.disabled = false; btn.textContent = "Фиристодан";
    }
  });
  s.appendChild(TabBar("home"));
  return s;
}

function ScreenBuy(): HTMLElement {
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Хариди SOMONI</h2></div>
    <div class="card center-col">
      <label class="field"><div class="lbl">Пардохт</div>
        <select id="from"><option value="TON">TON</option><option value="USDT">USDT</option></select></label>
      <div class="swap-arrow">⇅</div>
      <label class="field"><div class="lbl">Мегиред</div>
        <input id="get" value="SOMONI" disabled/></label>
      <label class="field"><div class="lbl">Миқдор</div><input id="amt" inputmode="decimal" placeholder="0.0"/></label>
      <div class="muted" id="quote" style="font-size:13px">Қурби тахминӣ: 1 USDT ≈ 1 SOMONI</div>
      <button class="btn btn-gold" id="swap">Иваз кардан (своп)</button>
    </div>
    <p class="lead">Своп тавассути DEX-и TON (масалан STON.fi/DeDust) иҷро мешавад. Пас аз деплойи SOMONI jetton ва ҷуфти ликвидӣ фаъол мегардад.</p>
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  s.querySelector("#swap")!.addEventListener("click", () => {
    toast("Своп фаъол мешавад пас аз насби SOMONI ва ликвидият");
  });
  s.appendChild(TabBar("home"));
  return s;
}

function ScreenSettings(): HTMLElement {
  const s = el(`<div class="screen">
    <div class="topbar"><div class="back" id="back">‹</div><h2>Танзимот</h2></div>
    <div class="card center-col">
      <div class="row-between"><div><div class="n" style="font-weight:700">Шабака</div><div class="muted" style="font-size:13px">Testnet — пулҳои санҷишӣ, бепул аз faucet</div></div></div>
      <label class="field"><select id="net">
        <option value="testnet" ${settings.net === "testnet" ? "selected" : ""}>Testnet (тавсия барои санҷиш)</option>
        <option value="mainnet" ${settings.net === "mainnet" ? "selected" : ""}>Mainnet (маблағи воқеӣ)</option>
      </select></label>
    </div>
    <div class="card">
      <div class="row-between"><div class="n" style="font-weight:700">Адреси ҳамён</div></div>
      <div class="mono" style="margin-top:8px">${esc(session?.address || vaultAddress() || "")}</div>
    </div>
    <button class="btn btn-ghost" id="lock">Қулф кардан</button>
    <button class="btn btn-danger" id="wipe">Нест кардани ҳамён аз дастгоҳ</button>
    <p class="lead" style="font-size:12px">SOMORA — ҳамёни ғайрикастодиалӣ. Калидҳо танҳо дар дастгоҳи шумо нигоҳ дошта мешаванд.</p>
  </div>`);
  s.querySelector("#back")!.addEventListener("click", () => go({ name: "home" }));
  (s.querySelector("#net") as HTMLSelectElement).addEventListener("change", (e: any) => {
    settings = { net: e.target.value as Net }; setSettings(settings); toast("Шабака иваз шуд"); go({ name: "home" });
  });
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
}
boot();
