// Non-custodial key storage. The 24-word secret is encrypted with a PIN
// (PBKDF2 -> AES-GCM) before it ever touches localStorage. The PIN is never stored.
import type { Account, Net } from "./ton";

const KEY = "somon.vault.v1";
const SETTINGS = "somon.settings.v1";

interface Vault {
  address: string;
  publicKeyHex: string;
  cipher: string; // base64 iv + ciphertext
  salt: string;   // base64
}

export interface Settings { net: Net }

const enc = new TextEncoder();
const dec = new TextDecoder();

function b64(buf: ArrayBuffer): string { return btoa(String.fromCharCode(...new Uint8Array(buf))); }
function unb64(s: string): Uint8Array { return Uint8Array.from(atob(s), (c) => c.charCodeAt(0)); }

async function deriveKey(pin: string, salt: Uint8Array): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey("raw", enc.encode(pin), "PBKDF2", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: 150000, hash: "SHA-256" },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
}

export async function saveVault(account: Account, pin: string): Promise<void> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(pin, salt);
  const data = enc.encode(JSON.stringify(account.mnemonic));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, data);
  const packed = new Uint8Array(iv.length + ct.byteLength);
  packed.set(iv, 0); packed.set(new Uint8Array(ct), iv.length);
  const vault: Vault = {
    address: account.address,
    publicKeyHex: account.publicKeyHex,
    cipher: b64(packed.buffer),
    salt: b64(salt.buffer),
  };
  localStorage.setItem(KEY, JSON.stringify(vault));
}

export function hasVault(): boolean { return !!localStorage.getItem(KEY); }

export function vaultAddress(): string | null {
  const raw = localStorage.getItem(KEY);
  if (!raw) return null;
  try { return (JSON.parse(raw) as Vault).address; } catch { return null; }
}

export async function unlock(pin: string): Promise<string[]> {
  const raw = localStorage.getItem(KEY);
  if (!raw) throw new Error("Ҳамён ёфт нашуд.");
  const vault = JSON.parse(raw) as Vault;
  const salt = unb64(vault.salt);
  const packed = unb64(vault.cipher);
  const iv = packed.slice(0, 12);
  const ct = packed.slice(12);
  const key = await deriveKey(pin, salt);
  try {
    const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct);
    return JSON.parse(dec.decode(pt));
  } catch {
    throw new Error("PIN нодуруст.");
  }
}

export function wipe(): void { localStorage.removeItem(KEY); }

export function getSettings(): Settings {
  try {
    const raw = localStorage.getItem(SETTINGS);
    if (raw) return JSON.parse(raw);
  } catch {}
  return { net: "testnet" };
}

export function setSettings(s: Settings): void {
  localStorage.setItem(SETTINGS, JSON.stringify(s));
}
