<template>
  <div id="app">
    <h1>CONTRACT DEPLOYER EXAMPLE</h1>
    <div>
      <label>
        Contract name:
      </label>
      <br>
      <input type="text" v-model.trim="contractName">
    </div>
    <div style="margin: 1rem">
      <label>
        Description:
      </label>
      <br>
      <textarea type="text" v-model.trim="description" />
    </div>
    <div style="margin: 1rem">
      <span v-if="working">{{ address }} is originating contract...</span>
      <button v-else @click="deployContract">Deploy</button>

    </div>
    <div v-if="error">Error: {{ error }}</div>
    <div v-if="kt">Contract originated: <a :href="`https://better-call.dev/${kt}`">{{ kt }}</a></div>
  </div>
</template>

<script>
import { TezosToolkit, MichelCodecPacker, MichelsonMap } from '@taquito/taquito'
import { char2Bytes } from '@taquito/utils'
import { BeaconWallet } from '@taquito/beacon-wallet'
import contractJson from '../build/Token.json'

const preferredNetwork = 'ithacanet' // 'mainnet'
const rpc = preferredNetwork === 'mainnet' ? 'https://mainnet.api.tez.ie' : 'https://ithacanet.ecadinfra.com' //'https://rpc.ithacanet.teztnets.xyz'

const tezos = new TezosToolkit(rpc)

tezos.setPackerProvider(new MichelCodecPacker())
const wallet = new BeaconWallet({
  name: 'DNS Deployer',
  preferredNetwork
})
tezos.setWalletProvider(wallet)

export default {
  name: 'App',
  data () {
    return {
      contractName: 'Test Contract',
      description: '',
      address: '',
      kt: '',
      working: false,
      error: '',
      opHash: ''
    }
  },
  methods: {
    async deployContract () {
      try {
        if (this.working) return
        this.working = true
        this.error = ''
        await this.disconnectWallet()
        await this.connectWallet()
        if (!this.address) {
          return
        }
        const originationOp = await tezos.wallet.originate({
          code: contractJson.michelson,
          storage: {
            owner: this.address,
            ledger: new MichelsonMap(),
            metadata: MichelsonMap.fromLiteral({
              "": char2Bytes('tezos-storage:contents'),
              contents: char2Bytes(JSON.stringify({
                name: this.contractName,
                description: this.description,
                version: '1.0.0',
                authors: ["BGrit <salv@protonmail.com>"],
                homepage: 'https://wizzard.tez.page'
              }))
            }),
            operators: new MichelsonMap(),
            token_metadata: new MichelsonMap(),
            minters: [],
            tokens_minted: 0,
          }
        }).send()
        await originationOp.confirmation()
        console.log(await originationOp.status())
        const contract = await originationOp.contract()
        this.kt = contract.address
        console.log(contract)
        this.opHash = originationOp.opHash;
        console.log(originationOp)
      } catch (e) {
        this.error = e.message;
      } finally {
        this.working = false;
      }
    },
    async connectWallet () {
      let activeAccount = await wallet.client.getActiveAccount()
      if (!activeAccount) {
        await this.disconnectWallet()
        await wallet.requestPermissions({ network: { type: preferredNetwork } })
        activeAccount = await wallet.client.getActiveAccount()
        if (!activeAccount) {
          throw new Error('Can not connect')
        }
      }
      this.address = await wallet.getPKH()
    },
    async disconnectWallet () {
      await wallet.clearActiveAccount()
      this.address = ''
    }
  }
}
</script>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-align: center;
  color: #2c3e50;
  margin-top: 60px;
}
</style>
