// Live prices: crypto in USD from CoinGecko, converted to Tajik somoni (TJS)
// via a USD->TJS FX rate. SOMONI is pegged 1:1 to somoni by design.
export interface PriceInfo { usd: number; smn: number; change24: number }

const USD_TJS_FALLBACK = 10.95;
const CG = "https://api.coingecko.com/api/v3/simple/price?ids=the-open-network,tether,bitcoin&vs_currencies=usd&include_24hr_change=true";
const FX = "https://open.er-api.com/v6/latest/USD";

let cache: Record<string, PriceInfo> | null = null;
let cacheTs = 0;

export async function fetchPrices(force = false): Promise<Record<string, PriceInfo>> {
  if (!force && cache && Date.now() - cacheTs < 60_000) return cache;
  try {
    const [cg, fx] = await Promise.all([
      fetch(CG).then((r) => r.json()),
      fetch(FX).then((r) => r.json()).catch(() => null),
    ]);
    const usdTjs = fx?.rates?.TJS ?? USD_TJS_FALLBACK;
    const mk = (o: any): PriceInfo => ({ usd: o.usd, smn: o.usd * usdTjs, change24: o.usd_24h_change ?? 0 });
    cache = {
      TON: mk(cg["the-open-network"]),
      USDT: mk(cg["tether"]),
      BTC: mk(cg["bitcoin"]),
      SOMONI: { usd: 1 / usdTjs, smn: 1, change24: 0 },
    };
    cacheTs = Date.now();
    return cache;
  } catch {
    if (cache) return cache;
    const u = USD_TJS_FALLBACK;
    return {
      TON: { usd: 0, smn: 0, change24: 0 },
      USDT: { usd: 1, smn: u, change24: 0 },
      BTC: { usd: 0, smn: 0, change24: 0 },
      SOMONI: { usd: 1 / u, smn: 1, change24: 0 },
    };
  }
}

export function fmtSmn(n: number, digits = 2): string {
  const s = n.toLocaleString("ru-RU", { minimumFractionDigits: digits, maximumFractionDigits: digits });
  return `${s} смн`;
}

// CoinGecko ids for assets that have a market
export const CG_ID: Record<string, string> = {
  TON: "the-open-network",
  BTC: "bitcoin",
  USDT: "tether",
};

const chartCache: Record<string, { ts: number; pts: number[] }> = {};

// 7-day price series (USD) for a symbol; returns [] if no market (e.g. SOMONI).
export async function fetchChart(symbol: string, days = 7): Promise<number[]> {
  const id = CG_ID[symbol];
  if (!id) return [];
  const key = `${id}:${days}`;
  const c = chartCache[key];
  if (c && Date.now() - c.ts < 120_000) return c.pts;
  try {
    const r = await fetch(`https://api.coingecko.com/api/v3/coins/${id}/market_chart?vs_currency=usd&days=${days}`);
    const j = await r.json();
    const pts: number[] = (j.prices || []).map((p: [number, number]) => p[1]);
    chartCache[key] = { ts: Date.now(), pts };
    return pts;
  } catch {
    return c?.pts ?? [];
  }
}
