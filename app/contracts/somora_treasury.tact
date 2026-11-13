// SOMORA Treasury — a simple on-chain seller/exchange for the SOMONI jetton.
// A buyer sends TON to this contract and receives SOMONI at the owner's rate;
// the TON payment is forwarded to the owner's address. The owner can change
// the rate, set the contract's jetton wallet, and withdraw TON.

import "@stdlib/deploy";

message SetRate { rate: Int as coins; }          // nano-SOMONI per 1 TON
message SetJettonWallet { wallet: Address; }      // this contract's SOMONI wallet
message WithdrawTon { amount: Int as coins; }

// Jetton transfer notification (TEP-74), op 0x7362d09c — received on top-up
message(0x7362d09c) JettonNotify {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    forwardPayload: Slice as remaining;
}

struct Info {
    owner: Address;
    jettonWallet: Address;
    rate: Int as coins;
}

contract SomoraTreasury with Deployable {
    owner: Address;
    jettonWallet: Address;
    rate: Int as coins;

    init(owner: Address, rate: Int) {
        self.owner = owner;
        self.jettonWallet = owner;   // placeholder until SetJettonWallet
        self.rate = rate;
    }

    receive(msg: SetJettonWallet) {
        require(sender() == self.owner, "not owner");
        self.jettonWallet = msg.wallet;
    }

    receive(msg: SetRate) {
        require(sender() == self.owner, "not owner");
        self.rate = msg.rate;
    }

    receive(msg: WithdrawTon) {
        require(sender() == self.owner, "not owner");
        send(SendParameters{ to: self.owner, value: msg.amount, mode: SendIgnoreErrors });
    }

    // SOMONI inventory top-up — accept silently
    receive(msg: JettonNotify) { }

    // Buy: a plain TON transfer (empty body) purchases SOMONI
    receive() {
        let tonIn: Int = context().value;
        require(tonIn >= ton("0.2"), "min 0.2 TON");
        let somoniOut: Int = tonIn * self.rate / ton("1");

        // dispense SOMONI from our jetton wallet to the buyer.
        // Build the TEP-74 transfer body manually (incl. the Either bit).
        // 0.12 TON covers creating a first-time buyer's jetton wallet.
        let buyer: Address = sender();
        let body: Cell = beginCell()
            .storeUint(0x0f8a7ea5, 32)   // op: jetton transfer
            .storeUint(0, 64)            // query id
            .storeCoins(somoniOut)       // amount
            .storeAddress(buyer)         // destination
            .storeAddress(buyer)         // response destination
            .storeBit(false)             // custom_payload: Maybe = 0
            .storeCoins(ton("0.02"))     // forward_ton_amount
            .storeBit(false)             // forward_payload: Either = 0 (inline, empty)
            .endCell();
        send(SendParameters{
            to: self.jettonWallet,
            value: ton("0.12"),
            mode: SendIgnoreErrors,
            body: body
        });

        // forward the rest of the payment to the owner
        let toOwner: Int = tonIn - ton("0.14");
        if (toOwner > 0) {
            send(SendParameters{ to: self.owner, value: toOwner, mode: SendIgnoreErrors });
        }
    }

    get fun info(): Info {
        return Info{ owner: self.owner, jettonWallet: self.jettonWallet, rate: self.rate };
    }
}
