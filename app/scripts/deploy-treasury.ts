// Deploy the SOMORA Treasury (SOMONI seller) on TON testnet.
// Owner = the user's address (receives all TON payments).
import { readFileSync, writeFileSync } from "node:fs";
import { mnemonicToPrivateKey } from "@ton/crypto";
import { TonClient, JettonMaster } from "@ton/ton";
import { Address, toNano, fromNano } from "@ton/core";
import { createSender, createHighloadV2, AssetsSDK, NoopStorage } from "@ton-community/assets-sdk";
import { SomoraTreasury } from "../contracts/output/somora_treasury_SomoraTreasury";

const OWNER = "UQBGDeKNSjaNw_FShJIPHgc6_Wtg1WlLBCJ6DeRydqSop9S7";
const SOMONI_MASTER = "kQAFnmFcJaOWjBuggPb3W1g9udA2R2JsAjScMDNO52kqMRki";
const RATE_SOMONI_PER_TON = "10";     // owner can change later
const INVENTORY = "500000";           // SOMONI minted into the treasury
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const words = JSON.parse(readFileSync("scripts/.deployer.testnet.json", "utf8")).mnemonic;
  const key = await mnemonicToPrivateKey(words);
  const client = new TonClient({ endpoint: "https://testnet.toncenter.com/api/v2/jsonRPC" });
  const dep = createHighloadV2(key.publicKey);
  console.log("Deployer:", dep.address.toString({ bounceable: false, testOnly: true }),
    "bal:", fromNano(await client.getBalance(dep.address)), "TON");
  const sender = await createSender("highload-v2", key, client);

  const owner = Address.parse(OWNER);
  const rate = toNano(RATE_SOMONI_PER_TON);
  const treasury = await SomoraTreasury.fromInit(owner, rate);
  const opened = client.open(treasury);
  const addr = treasury.address;
  console.log("Treasury address:", addr.toString({ bounceable: true, testOnly: true }));

  // 1) deploy
  console.log("Deploying treasury...");
  await opened.send(sender, { value: toNano("0.35") }, { $$type: "Deploy", queryId: 0n });
  await sleep(28000);

  // 2) compute + set the treasury's SOMONI jetton wallet
  const jm = client.open(JettonMaster.create(Address.parse(SOMONI_MASTER)));
  const jw = await jm.getWalletAddress(addr);
  console.log("Treasury jetton wallet:", jw.toString({ testOnly: true }));
  await opened.send(sender, { value: toNano("0.05") }, { $$type: "SetJettonWallet", wallet: jw });
  await sleep(20000);

  // 3) mint SOMONI inventory into the treasury (we are the jetton admin)
  const sdk = AssetsSDK.create({ api: client, storage: new NoopStorage(), sender });
  const minter = sdk.openJetton(Address.parse(SOMONI_MASTER));
  console.log(`Minting ${INVENTORY} SOMONI into the treasury...`);
  await minter.sendMint(sender, addr, toNano(INVENTORY), { value: toNano("0.25") });
  await sleep(25000);

  // 4) read back info
  try {
    const info = await opened.getInfo();
    console.log("Info -> owner:", info.owner.toString({ testOnly: true }),
      "| jettonWallet:", info.jettonWallet.toString({ testOnly: true }),
      "| rate:", info.rate.toString());
  } catch (e: any) { console.log("getInfo skipped:", e.message); }

  writeFileSync("scripts/treasury.testnet.json", JSON.stringify({
    treasury: addr.toString({ bounceable: true, testOnly: true }),
    jettonWallet: jw.toString({ testOnly: true }),
    owner: OWNER, somoniMaster: SOMONI_MASTER, rateSomoniPerTon: RATE_SOMONI_PER_TON,
  }, null, 2));
  console.log("\nSAVED. Treasury:", addr.toString({ bounceable: true, testOnly: true }));
}
main().catch((e) => { console.error(e); process.exit(1); });
