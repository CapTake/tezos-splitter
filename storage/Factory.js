import { MichelsonMap } from "@taquito/michelson-encoder";
import { char2Bytes } from '@taquito/utils'

export default {
  splitters: 0,
  metadata: MichelsonMap.fromLiteral({
    "": char2Bytes('tezos-storage:contents'),
    contents: char2Bytes(JSON.stringify({
      name: 'Splitter Factory contract',
      description: 'Contract to create your own personal splitter for tez or any tokens. Use with caution. No guarantees.',
      version: '1.0.0',
      authors: ["B.Grit <salv@protonmail.com>"],
      homepage: 'https://wizzard.tez.page'
    }))
  }),
  holders: new MichelsonMap()
}

