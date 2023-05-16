const { TezosToolkit, MichelCodecPacker } = require("@taquito/taquito")
const { InMemorySigner } = require("@taquito/signer")

const { migrate } = require("../scripts/helpers")
const storage = require("../storage/Factory")

module.exports = async (tezos, network) => {

  tezos = new TezosToolkit(tezos.rpc.url)
  tezos.setPackerProvider(new MichelCodecPacker())
  const signer = await InMemorySigner.fromSecretKey(network.secretKey)
  const ADMIN = await signer.publicKeyHash()
  tezos.setProvider({
    config: {
      confirmationPollingTimeoutSecond: 90000,
    },
    signer,
  })

  console.log('Factory')
  storage.default.owner = ADMIN
  const minteryAddress = await migrate(
    tezos,
    "Factory",
    storage
  )
  console.log(`address: ${minteryAddress}`)
}
