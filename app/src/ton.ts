import { mnemonicNew, mnemonicToPrivateKey, mnemonicValidate } from "@ton/crypto";
import { TonClient, WalletContractV4, internal, JettonMaster, JettonWallet } from "@ton/ton";
import { Address, toNano, fromNano, beginCell, internal as _i } from "@ton/core";

export type Net = "testnet" | "mainnet";

// Single fixed network for the whole app (no in-app switching).
// Flip to "mainnet" after the mainnet deploy (see MAINNET.md).
export const NETWORK: Net = "testnet";

const ENDPOINTS: Record<Net, string> = {
  testnet: "https://testnet.toncenter.com/api/v2/jsonRPC",
  mainnet: "https://toncenter.com/api/v2/jsonRPC",
};

// Jetton master addresses. USDT on mainnet is the official Tether jetton.
// On testnet we leave USDT/SOMONI configurable (deploy your own via scripts/deploy-somoni).
export interface JettonDef {
  id: string;
  name: string;
  symbol: string;
  decimals: number;
  color: string;
  icon: string;
  master: Partial<Record<Net, string>>;
}

// Native TON icon (official token image, loaded at runtime like a real wallet)
export const TON_ICON = "https://assets.coingecko.com/coins/images/17980/small/ton_symbol.png";
export const BTC_ICON = "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons/svg/color/btc.svg";

export const JETTONS: JettonDef[] = [
  {
    id: "usdt",
    name: "Tether USD",
    symbol: "USDT",
    decimals: 6,
    color: "#26A17B",
    icon: "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons/svg/color/usdt.svg",
    master: {
      mainnet: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs",
      // set your testnet USDT jetton master here if you deploy a test one
    },
  },
  {
    id: "somoni",
    name: "Somoni",
    symbol: "SOMONI",
    decimals: 9,
    color: "#C98A12",
    icon: "./somoni-coin.png", // user-provided SOMONI coin image
    master: {
      testnet: "kQAFnmFcJaOWjBuggPb3W1g9udA2R2JsAjScMDNO52kqMRki",
      // mainnet master goes here after a mainnet deploy
    },
  },
];

// SOMORA Treasury: buy SOMONI by sending TON here; owner receives the TON.
export const TREASURY: Partial<Record<Net, { address: string; owner: string; rate: number; min: number }>> = {
  testnet: {
    address: "kQAcz4dSx33sb4QstskSOUxG-7CFJc-ay6tm_YqVIAMqW6ps",
    owner: "UQBGDeKNSjaNw_FShJIPHgc6_Wtg1WlLBCJ6DeRydqSop9S7",
    rate: 10, min: 0.2,
  },
  // mainnet treasury goes here after a mainnet deploy
};

// Treasury contract message opcodes (from the compiled ABI)
const OP_SET_RATE = 3507611872;
const OP_WITHDRAW_TON = 4206811366;

export function sameAddress(a: string, b: string): boolean {
  try { return Address.parse(a).equals(Address.parse(b)); } catch { return false; }
}
export function isTreasuryOwner(net: Net, address: string): boolean {
  const t = TREASURY[net];
  return !!t && sameAddress(t.owner, address);
}

export interface Account {
  mnemonic: string[];
  address: string;         // user-friendly, bounceable=false
  publicKeyHex: string;
}

export interface AssetBalance {
  id: string;
  name: string;
  symbol: string;
  color: string;
  icon: string;
  amount: string;          // human readable
  decimals: number;
}

function client(net: Net) {
  return new TonClient({ endpoint: ENDPOINTS[net] });
}

// Public toncenter is rate-limited (HTTP 429). Retry with backoff so a
// transient limit never shows up as a false "0" balance.
async function withRetry<T>(fn: () => Promise<T>, tries = 5, base = 700): Promise<T> {
  let last: unknown;
  for (let i = 0; i < tries; i++) {
    try { return await fn(); }
    catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, base * (i + 1)));
    }
  }
  throw last;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function createAccount(): Promise<Account> {
  const mnemonic = await mnemonicNew(24);
  return accountFromMnemonic(mnemonic);
}

export async function importAccount(words: string[]): Promise<Account> {
  const valid = await mnemonicValidate(words);
  if (!valid) throw new Error("Нодуруст: санҷед, ки 24 калима дуруст навишта шудаанд.");
  return accountFromMnemonic(words);
}

async function accountFromMnemonic(mnemonic: string[]): Promise<Account> {
  const key = await mnemonicToPrivateKey(mnemonic);
  const wallet = WalletContractV4.create({ workchain: 0, publicKey: key.publicKey });
  return {
    mnemonic,
    address: wallet.address.toString({ bounceable: false, testOnly: false }),
    publicKeyHex: key.publicKey.toString("hex"),
  };
}

export function fmtAddress(addr: string, head = 6, tail = 6): string {
  if (addr.length <= head + tail + 1) return addr;
  return `${addr.slice(0, head)}…${addr.slice(-tail)}`;
}

export async function getTonBalance(net: Net, address: string): Promise<string> {
  try {
    const c = client(net);
    const bal = await withRetry(() => c.getBalance(Address.parse(address)));
    return fromNano(bal);
  } catch {
    return "0";
  }
}

async function jettonWalletAddress(net: Net, master: string, owner: string): Promise<Address | null> {
  try {
    const c = client(net);
    const jm = c.open(JettonMaster.create(Address.parse(master)));
    return await withRetry(() => jm.getWalletAddress(Address.parse(owner)));
  } catch {
    return null;
  }
}

export async function getJettonBalance(net: Net, def: JettonDef, owner: string): Promise<string> {
  const master = def.master[net];
  if (!master) return "0";
  try {
    const jwAddr = await jettonWalletAddress(net, master, owner);
    if (!jwAddr) return "0";
    const c = client(net);
    const jw = c.open(JettonWallet.create(jwAddr));
    const bal = await withRetry(() => jw.getBalance());
    return scaleDown(bal, def.decimals);
  } catch {
    return "0";
  }
}

function scaleDown(v: bigint, decimals: number): string {
  const neg = v < 0n;
  let s = (neg ? -v : v).toString().padStart(decimals + 1, "0");
  const i = s.length - decimals;
  let out = `${s.slice(0, i)}.${s.slice(i)}`.replace(/\.?0+$/, "");
  if (out === "") out = "0";
  return (neg ? "-" : "") + out;
}

function scaleUp(human: string, decimals: number): bigint {
  const [whole, frac = ""] = human.replace(",", ".").split(".");
  const fracPadded = (frac + "0".repeat(decimals)).slice(0, decimals);
  return BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(fracPadded || "0");
}

export async function loadAssets(net: Net, address: string): Promise<AssetBalance[]> {
  const ton = await getTonBalance(net, address);
  const out: AssetBalance[] = [
    { id: "ton", name: "Toncoin", symbol: "TON", color: "#0098EA", icon: TON_ICON, amount: ton, decimals: 9 },
  ];
  for (const j of JETTONS) {
    await sleep(350); // ease off the public rate limit
    const amt = await getJettonBalance(net, j, address);
    out.push({ id: j.id, name: j.name, symbol: j.symbol, color: j.color, icon: j.icon, amount: amt, decimals: j.decimals });
  }
  return out;
}

export async function sendTon(
  net: Net, mnemonic: string[], to: string, amountTon: string, comment?: string
): Promise<void> {
  const c = client(net);
  const key = await mnemonicToPrivateKey(mnemonic);
  const wallet = c.open(WalletContractV4.create({ workchain: 0, publicKey: key.publicKey }));
  const seqno = await wallet.getSeqno();
  await wallet.sendTransfer({
    secretKey: key.secretKey,
    seqno,
    messages: [
      internal({
        to: Address.parse(to),
        value: toNano(amountTon),
        body: comment && comment.length ? comment : undefined,
        bounce: false,
      }),
    ],
  });
}

export async function sendJetton(
  net: Net, def: JettonDef, mnemonic: string[], to: string, amountHuman: string, comment?: string
): Promise<void> {
  const master = def.master[net];
  if (!master) throw new Error(`${def.symbol} ҳанӯз дар ин шабака насб нашудааст.`);
  const c = client(net);
  const key = await mnemonicToPrivateKey(mnemonic);
  const wallet = c.open(WalletContractV4.create({ workchain: 0, publicKey: key.publicKey }));
  const owner = wallet.address.toString({ bounceable: false });
  const jwAddr = await jettonWalletAddress(net, master, owner);
  if (!jwAddr) throw new Error("Jetton wallet ёфт нашуд.");

  const amount = scaleUp(amountHuman, def.decimals);
  const forwardPayload = comment && comment.length
    ? beginCell().storeUint(0, 32).storeStringTail(comment).endCell()
    : null;

  const body = beginCell()
    .storeUint(0x0f8a7ea5, 32)                 // op: jetton transfer
    .storeUint(0n, 64)                          // query id
    .storeCoins(amount)                         // amount
    .storeAddress(Address.parse(to))            // destination
    .storeAddress(Address.parse(owner))         // response destination
    .storeBit(false)                            // no custom payload
    .storeCoins(forwardPayload ? toNano("0.000000001") : 0n) // forward amount
    .storeMaybeRef(forwardPayload)              // forward payload
    .endCell();

  const seqno = await wallet.getSeqno();
  await wallet.sendTransfer({
    secretKey: key.secretKey,
    seqno,
    messages: [internal({ to: jwAddr, value: toNano("0.05"), body, bounce: true })],
  });
}

export interface TxItem {
  dir: "in" | "out";
  amount: string;   // TON
  peer: string;     // counterparty address (raw/friendly)
  comment: string;
  time: number;     // unix seconds
  hash: string;
}

const API_BASE: Record<Net, string> = {
  testnet: "https://testnet.toncenter.com/api/v2",
  mainnet: "https://toncenter.com/api/v2",
};

// Recent TON account transactions (incoming/outgoing), parsed for the UI.
export async function getTransactions(net: Net, address: string, limit = 20): Promise<TxItem[]> {
  try {
    const url = `${API_BASE[net]}/getTransactions?address=${encodeURIComponent(address)}&limit=${limit}&archival=false`;
    const j = await withRetry(async () => {
      const r = await fetch(url);
      if (!r.ok) throw new Error(String(r.status));
      return r.json();
    });
    if (!j.ok || !Array.isArray(j.result)) return [];
    const out: TxItem[] = [];
    for (const tx of j.result) {
      const time = tx.utime || 0;
      const hash = tx.transaction_id?.hash || "";
      const inMsg = tx.in_msg;
      const inVal = inMsg ? Number(inMsg.value || 0) : 0;
      if (inMsg && inMsg.source && inVal > 0) {
        out.push({ dir: "in", amount: (inVal / 1e9).toString(), peer: inMsg.source, comment: inMsg.message || "", time, hash });
      }
      for (const m of tx.out_msgs || []) {
        const v = Number(m.value || 0);
        if (v > 0 && m.destination) {
          out.push({ dir: "out", amount: (v / 1e9).toString(), peer: m.destination, comment: m.message || "", time, hash });
        }
      }
    }
    return out;
  } catch {
    return [];
  }
}

// Send an internal message with a custom body from the user's wallet.
async function sendInternal(net: Net, mnemonic: string[], to: string, valueTon: string, body: any, bounce: boolean): Promise<void> {
  const c = client(net);
  const key = await mnemonicToPrivateKey(mnemonic);
  const wallet = c.open(WalletContractV4.create({ workchain: 0, publicKey: key.publicKey }));
  const seqno = await withRetry(() => wallet.getSeqno());
  await wallet.sendTransfer({
    secretKey: key.secretKey,
    seqno,
    messages: [internal({ to: Address.parse(to), value: toNano(valueTon), body, bounce })],
  });
}

// Owner: change the SOMONI price (SOMONI per 1 TON).
export async function treasurySetRate(net: Net, mnemonic: string[], rateSomoniPerTon: string): Promise<void> {
  const t = TREASURY[net];
  if (!t) throw new Error("Казначейство дар ин шабака нест");
  const body = beginCell().storeUint(OP_SET_RATE, 32).storeCoins(toNano(rateSomoniPerTon)).endCell();
  await sendInternal(net, mnemonic, t.address, "0.05", body, true);
}

// Owner: withdraw TON from the treasury to the owner address.
export async function treasuryWithdraw(net: Net, mnemonic: string[], amountTon: string): Promise<void> {
  const t = TREASURY[net];
  if (!t) throw new Error("Казначейство дар ин шабака нест");
  const body = beginCell().storeUint(OP_WITHDRAW_TON, 32).storeCoins(toNano(amountTon)).endCell();
  await sendInternal(net, mnemonic, t.address, "0.05", body, true);
}

// Owner: top up SOMONI inventory (send SOMONI from your wallet to the treasury).
export async function treasuryTopUp(net: Net, mnemonic: string[], somoniAmount: string): Promise<void> {
  const t = TREASURY[net];
  if (!t) throw new Error("Казначейство дар ин шабака нест");
  const def = JETTONS.find((j) => j.id === "somoni")!;
  await sendJetton(net, def, mnemonic, t.address, somoniAmount);
}

export interface TreasuryInfo { ton: string; somoni: string; rate: number }
export async function getTreasuryInfo(net: Net): Promise<TreasuryInfo | null> {
  const t = TREASURY[net];
  if (!t) return null;
  const c = client(net);
  const addr = Address.parse(t.address);
  let ton = "0", somoni = "0", rate = t.rate;
  try { ton = fromNano(await withRetry(() => c.getBalance(addr))); } catch {}
  try { somoni = await getJettonBalance(net, JETTONS.find((j) => j.id === "somoni")!, t.address); } catch {}
  try {
    const res = await withRetry(() => c.runMethod(addr, "info"));
    const tup = res.stack.readTuple();
    tup.readAddress(); tup.readAddress();
    rate = Number(tup.readBigNumber()) / 1e9;
  } catch {}
  return { ton, somoni, rate };
}

export { toNano, fromNano };
