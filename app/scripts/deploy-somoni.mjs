// Deploy the SOMONI jetton (TEP-74) on TON testnet and mint supply.
//
// Usage:
//   MINT_TO=<user UQ.../EQ... address>  SUPPLY=1000000  node scripts/deploy-somoni.mjs
//
// The deployer wallet mnemonic is read from scripts/.deployer.testnet.json
// (generated earlier). The deployer must hold a little testnet TON for gas.
import { readFileSync, writeFileSync } from "node:fs";
import { mnemonicToPrivateKey } from "@ton/crypto";
import { TonClient } from "@ton/ton";
import { Address, toNano, fromNano } from "@ton/core";
import {
  AssetsSDK, createApi, createSender, createHighloadV2, NoopStorage,
} from "@ton-community/assets-sdk";

const NETWORK = "testnet";
const SUPPLY = process.env.SUPPLY || "1000000";
const MINT_TO = process.env.MINT_TO;
if (!MINT_TO) { console.error("ERROR: set MINT_TO=<your wallet address>"); process.exit(1); }

const words = JSON.parse(readFileSync("scripts/.deployer.testnet.json", "utf8")).mnemonic;
const key = await mnemonicToPrivateKey(words);
const deployer = createHighloadV2(key.publicKey);
const deployerAddr = deployer.address;
console.log("Deployer:", deployerAddr.toString({ bounceable: false, testOnly: true }));

// --- gas check ---
const client = new TonClient({ endpoint: "https://testnet.toncenter.com/api/v2/jsonRPC" });
const bal = await client.getBalance(deployerAddr);
console.log("Deployer balance:", fromNano(bal), "TON");
if (bal < toNano("0.4")) {
  console.error(`\nNOT ENOUGH GAS. Fund the deployer with testnet TON (>=0.5):`);
  console.error(deployerAddr.toString({ bounceable: false, testOnly: true }));
  console.error("Faucet: @testgiver_ton_bot in Telegram. Then re-run this script.");
  process.exit(2);
}

// --- deploy ---
const api = await createApi(NETWORK);
const sender = await createSender("highload-v2", key, NETWORK);
const sdk = AssetsSDK.create({ api, storage: new NoopStorage(), sender });

const imageData = readFileSync("scripts/token-logo-128.png");
console.log("Deploying SOMONI jetton (on-chain metadata)...");
const jetton = await sdk.deployJetton(
  {
    name: "Somoni",
    description: "Somoni (SOMONI) — цифровой жетон кошелька Somon. Testnet.",
    symbol: "SOMONI",
    decimals: 9,
    imageData,
    renderType: "currency",
    amountStyle: "n",
  },
  { onchainContent: true, value: toNano("0.35") }
);

const master = jetton.address.toString({ bounceable: true, testOnly: true });
console.log("SOMONI master:", master);

// --- wait for deploy to settle, then mint to the user ---
await new Promise((r) => setTimeout(r, 25000));
console.log(`Minting ${SUPPLY} SOMONI to ${MINT_TO} ...`);
await jetton.sendMint(sender, Address.parse(MINT_TO), toNano(SUPPLY), {
  value: toNano("0.25"),
});

// --- send a little gas TON to the user so they can later transfer SOMONI ---
try {
  await sender.send({ to: Address.parse(MINT_TO), value: toNano("0.25") });
  console.log("Sent 0.25 TON gas to", MINT_TO);
} catch (e) { console.log("gas send skipped:", e.message); }

// --- save result ---
writeFileSync("scripts/somoni.testnet.json", JSON.stringify({
  network: NETWORK, master, mintedTo: MINT_TO, supply: SUPPLY,
}, null, 2));
console.log("\nDONE. Put this master address into app/src/ton.ts (JETTONS -> somoni -> master.testnet):");
console.log(master);
