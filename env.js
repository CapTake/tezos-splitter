import accounts from "./scripts/sandbox/accounts"
import dotenv from "dotenv"
dotenv.config()

export default {
  confirmationPollingTimeoutSecond: 1500000,
  syncInterval: 0, // 0 for tests, 5000 for deploying
  confirmTimeout: 190000, // 90000 for tests, 180000 for deploying
  buildDir: "build",
  migrationsDir: "migrations",
  contractsDir: "contracts/main",
  ligoVersion: "0.64.3",
  network: "development",
  networks: {
    development: {
      rpc: "https://rpc.ghostnet.teztnets.xyz",
      port: 443,
      network_id: "*",
      secretKey: accounts.alice.sk,
    },
    mainnet: {
      rpc: "https://mainnet.api.tez.ie",
      port: 443,
      network_id: "*",
      secretKey: process.env.ADMIN_SECRET_KEY,
    }
  }
}
