import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "tj.somon.wallet",
  appName: "Somon",
  webDir: "dist",
  android: {
    allowMixedContent: false,
  },
  server: {
    androidScheme: "https",
  },
};

export default config;
