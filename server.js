const express = require("express");
const fetch = require("node-fetch");
const app = express();
app.use(express.json());

const BOT_TOKEN = process.env.BOT_TOKEN;

app.post("/check-subscription", async (req, res) => {
  const { user_id, channel } = req.body;
  if (!user_id || !channel) return res.status(400).json({ error: "Missing parameters" });

  try {
    const tgRes = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getChatMember?chat_id=@${channel}&user_id=${user_id}`);
    const json = await tgRes.json();
    if (json.ok) {
      const status = json.result.status;
      return res.json({ status });
    } else {
      return res.status(500).json({ error: "Telegram error", details: json });
    }
  } catch (err) {
    return res.status(500).json({ error: "Request failed", details: err.message });
  }
});

app.listen(3000, () => console.log("Server running"));
