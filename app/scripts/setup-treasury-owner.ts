// Owner-signed setup for the treasury: set its SOMONI jetton wallet (and rate).
// Run with the OWNER wallet mnemonic in USER_MNEMONIC (space-separated).
import { readFileSync } from "node:fs";
import { mnemonicToPrivateKey } from "@ton/crypto";
import { TonClient, WalletContractV4 } from "@ton/ton";
import { Address, toNano, fromNano } from "@ton/core";
import { SomoraTreasury } from "../contracts/output/somora_treasury_SomoraTreasury";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const words = (process.env.USER_MNEMONIC || "").trim().split(/\s+/);
  if (words.length !== 24) { console.error("set USER_MNEMONIC (24 words)"); process.exit(1); }
  const info = JSON.parse(readFileSync("scripts/treasury.testnet.json", "utf8"));

  const key = await mnemonicToPrivateKey(words);
  const client = new TonClient({ endpoint: "https://testnet.toncenter.com/api/v2/jsonRPC" });
  const wallet = client.open(WalletContractV4.create({ workchain: 0, publicKey: key.publicKey }));
  console.log("Owner:", wallet.address.toString({ bounceable: false, testOnly: true }),
    "bal:", fromNano(await client.getBalance(wallet.address)), "TON");
  const sender = wallet.sender(key.secretKey);

  const opened = client.open(SomoraTreasury.fromAddress(Address.parse(info.treasury)));
  const jw = Address.parse(info.jettonWallet);

  console.log("Setting treasury jetton wallet ->", info.jettonWallet);
  await opened.send(sender, { value: toNano("0.06") }, { $$type: "SetJettonWallet", wallet: jw });
  await sleep(28000);

  const out = await opened.getInfo();
  console.log("Info -> owner:", out.owner.toString({ testOnly: true }));
  console.log("      jettonWallet:", out.jettonWallet.toString({ testOnly: true }));
  console.log("      rate:", out.rate.toString());
  const ok = out.jettonWallet.toString() === jw.toString();
  console.log(ok ? "OK: jetton wallet set correctly" : "WARN: jetton wallet not set yet (retry)");
}
main().catch((e) => { console.error(e); process.exit(1); });
