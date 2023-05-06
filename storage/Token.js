import { MichelsonMap } from "@taquito/michelson-encoder";
import { char2Bytes } from '@taquito/utils'

import { zeroAddress } from "../test/helpers/Utils";

export default {
  admin: zeroAddress,
  ledger: new MichelsonMap(),
  metadata: MichelsonMap.fromLiteral({
    "": char2Bytes('tezos-storage:contents'),
    contents: char2Bytes(JSON.stringify({
      name: 'My Own NFT contract',
      description: 'This is the description',
      version: '1.0.0',
      authors: ["BGrit <salv@protonmail.com>"],
      homepage: 'https://wizzard.tez.page'
    }))
  }),
  operators: new MichelsonMap(),
  token_metadata: new MichelsonMap(),
  minters: []
}

