import { TezosToolkit, MichelsonMap } from "@taquito/taquito";
import { InMemorySigner } from "@taquito/signer";
import { char2Bytes } from "@taquito/utils";
import contractJson from "../../build/Token.json";
import { expect } from "chai";
import { rejects } from "assert";

const alice = {
  pkh: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb",
  sk: "edsk3QoqBuvdamxouPhin7swCvkQNgq4jP5KZPbwWNnwdZpSpJiEbq",
  pk: "edpkvGfYw3LyB1UcCahKQk4rF2tvbMUk8GFiTuMjL75uGXrpvKXhjn",
};
const bob = {
  pkh: "tz1aSkwEot3L2kmUvcoxzjMomb9mvBNuzFK6",
  sk: "edsk3RFfvaFaxbHx8BMtEW1rKQcPtDML3LXjNqMNLCzC3wLC1bWbAt",
  pk: "edpkurPsQ8eUApnLUJ9ZPDvu98E8VNj4KtJa1aZr16Cr5ow5VHKnz4",
};
const rpcUrl = "https://rpc.ithacanet.teztnets.xyz";

const MINT_AMOUNT = 2
const error_access_denied = "Access denied"
const tokenUriBytes = char2Bytes('ipfs://fakehash')

let contractAddress = "";
let TezosAlice;
let TezosBob;
let aliceSigner;
let bobSigner;
let tokenId = 1

before("setup", async () => {
  // sets up the Tezos toolkit instance with Alice as a signer
  TezosAlice = new TezosToolkit(rpcUrl);
  aliceSigner = new InMemorySigner(alice.sk);
  TezosAlice.setSignerProvider(aliceSigner);
  // sets up the Tezos toolkit instance with Bob as a signer
  TezosBob = new TezosToolkit(rpcUrl);
  bobSigner = new InMemorySigner(bob.sk);
  TezosBob.setSignerProvider(bobSigner);
});

describe("Origination of contract", () => {
  it("Should originate the contract", async () => {

    try {
      const originationOp = await TezosAlice.contract.originate({
        code: contractJson.michelson,
        storage: {
          admin: alice.pkh,
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
      });
      await originationOp.confirmation();
      contractAddress = originationOp.contractAddress;
      expect(originationOp.hash).to.be.a('string');
      expect(contractAddress).to.be.a('string');
    } catch (error) {
      // console.error(error);
      expect(error).to.be.undefined;
    }
  });
});

describe("Tests for minting", () => {
  it("Should let Alice to mint a token", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const amount = MINT_AMOUNT;
      const op = await contract.methods.mint(amount, alice.pkh, tokenId, MichelsonMap.fromLiteral({ "": tokenUriBytes })).send();
      await op.confirmation(1);

      const newStorage = await contract.storage();
      const alicenewBalance = await newStorage.ledger.get({ 0: alice.pkh, 1: tokenId });
      expect(alicenewBalance.toNumber()).to.equal(amount);
      const tokenMeta = await newStorage.token_metadata.get(tokenId);
      expect(tokenMeta.token_id.toNumber()).to.equal(tokenId);
      expect(tokenMeta.token_info.get("")).to.equal(tokenUriBytes);
    } catch (error) {
      console.error(error);
      expect(error).to.be.undefined;
    }
  });
  it("Should let Alice to mint another token for Bob", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const amount = MINT_AMOUNT;
      tokenId++
      const op = await contract.methods.mint(amount, bob.pkh, tokenId, MichelsonMap.fromLiteral({ "": tokenUriBytes })).send();
      await op.confirmation(1);

      const newStorage = await contract.storage();
      const bobnewBalance = await newStorage.ledger.get({ 0: bob.pkh, 1: tokenId });
      expect(bobnewBalance.toNumber()).to.equal(amount);
      const tokenMeta = await newStorage.token_metadata.get(tokenId);
      expect(tokenMeta.token_id.toNumber()).to.equal(tokenId);
      expect(tokenMeta.token_info.get("")).to.equal(tokenUriBytes);
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should prevent Bob from minting", async () => {
    try {
      const contract = await TezosBob.contract.at(contractAddress);
      const amount = MINT_AMOUNT;
      const tokenId = 11111;
      await rejects(contract.methods.mint(amount, bob.pkh, tokenId, MichelsonMap.fromLiteral({ "": tokenUriBytes })).send(), (err: Error) => {
          expect(err.message).to.equal(error_access_denied);
          return true;
      });
    } catch (error) {
      console.error(error);
      expect(error).to.be.undefined;
    }
  });
});

describe("Tests for transfers", () => {
  it("Should prevent Alice from sending unexisting token", async () => {
    const contract = await TezosAlice.contract.at(contractAddress);
    const oldStorage = await contract.storage();
    const tokenId = 0
    await rejects(contract.methods
      .transfer([
        {
          from_: alice.pkh,
          txs: [
            {
              to_: bob.pkh,
              token_id: tokenId,
              amount: 1
            }
          ]
        }
      ])
      .send(),
      (err: Error) => {
        expect(err.message).to.equal("FA2_TOKEN_UNDEFINED");
        return true;
    });
  });
  it("Should prevent Alice from sending tokens over her balance", async () => {
    const contract = await TezosAlice.contract.at(contractAddress);
    const oldStorage = await contract.storage();
    const tokenId = 1;
    await rejects(contract.methods
      .transfer([
        {
          from_: alice.pkh,
          txs: [
            {
              to_: bob.pkh,
              token_id: tokenId,
              amount: MINT_AMOUNT + 1
            }
          ]
        }
      ])
      .send(),
      (err: Error) => {
        expect(err.message).to.equal("FA2_INSUFFICIENT_BALANCE");
        return true;
    });
  });

  it("Should allow Alice to add Bob to minters", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const storage = await contract.storage();
      expect(storage.minters).to.not.include(bob.pkh);
      const op = await contract.methods.update_minters('add_minter', bob.pkh).send();
      await op.confirmation(1);

      const newStorage = await contract.storage();
      expect(newStorage.minters).to.include(bob.pkh);
    } catch (error) {
      console.error(error);
      expect(error).to.be.undefined;
    }
  });

  it("Should let minter Bob to mint a token", async () => {
    try {
      const contract = await TezosBob.contract.at(contractAddress);
      const amount = MINT_AMOUNT;
      tokenId++
      const op = await contract.methods.mint(amount, bob.pkh, tokenId, MichelsonMap.fromLiteral({ "": tokenUriBytes })).send();
      await op.confirmation(1);

      const newStorage = await contract.storage();
      const bobnewBalance = await newStorage.ledger.get({ 0: bob.pkh, 1: tokenId });
      expect(bobnewBalance.toNumber()).to.equal(amount);
      const tokenMeta = await newStorage.token_metadata.get(tokenId);
      expect(tokenMeta.token_id.toNumber()).to.equal(tokenId);
      expect(tokenMeta.token_info.get("")).to.equal(tokenUriBytes);
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should prevent Bob to add alice to minters", async () => {
    try {
      const contract = await TezosBob.contract.at(contractAddress);
      const storage = await contract.storage();
      expect(storage.minters).to.not.include(alice.pkh);
      await rejects(contract.methods.update_minters('add_minter', bob.pkh).send(), (err: Error) => {
        expect(err.message).to.equal(error_access_denied);
        return true;
      });
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should allow Alice to remove Bob from minters", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const storage = await contract.storage();
      expect(storage.minters).to.include(bob.pkh);
      const op = await contract.methods.update_minters('remove_minter', bob.pkh).send();
      await op.confirmation(1);

      const newStorage = await contract.storage();
      expect(newStorage.minters).to.not.include(bob.pkh);
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should allow Alice to transfer tokens to Bob", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const storage = await contract.storage();
      const tokenId = 1
      const amount = 1
      const aliceOriginalBalance = await storage.ledger.get({ 0: alice.pkh, 1: tokenId });
      expect(aliceOriginalBalance.toNumber()).to.equal(MINT_AMOUNT);
      const bobOriginalBalance = await storage.ledger.get({ 0: bob.pkh, 1: tokenId });
      expect(bobOriginalBalance).to.be.undefined;

      const op = await contract.methods
        .transfer([
          {
            from_: alice.pkh,
            txs: [{ to_: bob.pkh, token_id: tokenId, amount }]
          }
        ])
        .send();
      await op.confirmation();

      const newStorage = await contract.storage();
      const alicenewBalance = await newStorage.ledger.get({ 0: alice.pkh, 1: tokenId });
      expect(alicenewBalance.toNumber()).to.equal(aliceOriginalBalance.toNumber() - amount);
      const bobNewBalance = await newStorage.ledger.get({ 0: bob.pkh, 1: tokenId });
      expect(bobNewBalance.toNumber()).to.equal(amount);
    } catch (error) {
      console.error(error);
      expect(error).to.be.undefined;
    }
  });

  it("Should allow Alice to transfer more tokens to Bob", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const storage = await contract.storage();
      const tokenId = 1
      const aliceOriginalBalance = await storage.ledger.get({ 0: alice.pkh, 1: tokenId });
      const amount = aliceOriginalBalance.toNumber()
      const bobOriginalBalance = await storage.ledger.get({ 0: bob.pkh, 1: tokenId });
      const op = await contract.methods
        .transfer([
          {
            from_: alice.pkh,
            txs: [{ to_: bob.pkh, token_id: tokenId, amount }]
          }
        ])
        .send();
      await op.confirmation();

      const newStorage = await contract.storage();
      const alicenewBalance = await newStorage.ledger.get({ 0: alice.pkh, 1: tokenId });
      expect(alicenewBalance).to.be.undefined;
      const bobNewBalance = await newStorage.ledger.get({ 0: bob.pkh, 1: tokenId });
      expect(bobNewBalance.toNumber()).to.equal(amount + bobOriginalBalance.toNumber());
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should prevent Alice from transferring Bob's tokens", async () => {
    const contract = await TezosAlice.contract.at(contractAddress);
    await rejects(contract.methods
        .transfer([
          {
            from_: bob.pkh,
            txs: [
              {
                to_: alice.pkh,
                token_id: tokenId, // Bob minted last
                amount: 1
              }
            ]
          }
        ]).send(), (err: Error) => {
          expect(err.message).to.equal("FA2_NOT_OPERATOR");
          return true;
    });
  });

  it("Should prevent Bob from making transfers on behalf of Alice", async () => {
    const contract = await TezosBob.contract.at(contractAddress);
    await rejects(contract.methods
        .transfer([
          {
            from_: alice.pkh,
            txs: [
              {
                to_: bob.pkh,
                token_id: 1,
                amount: 1
              }
            ]
          }
        ])
        .send(), (err: Error) => {
          expect(err.message).to.equal("FA2_NOT_OPERATOR");
          return true;
    });
  });
});

describe("Tests for operators", () => {
  it("Should set Alice as an operator for Bob", async () => {
    try {
      const tokenId = 1
      const contract = await TezosBob.contract.at(contractAddress);
      const storage = await contract.storage();
      const param = {
        owner: bob.pkh,
        operator: alice.pkh,
        token_id: tokenId
      }
      const operator = await storage.operators.get(param);
      expect(operator).to.be.undefined;

      const op = await contract.methods.update_operators([{ add_operator: param }]).send();
      await op.confirmation();
      const newStorage = await contract.storage();
      const aliceNewOperator = await newStorage.operators.get(param);
      expect(aliceNewOperator).to.be.ok;
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should let Alice make a transfer on behalf of Bob", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const storage = await contract.storage();
      const tokenId = 1
      const amount = 1
      const bobOriginalBalance = await storage.ledger.get({ 0:bob.pkh, 1: tokenId });

      const op = await contract.methods
        .transfer([
          {
            from_: bob.pkh,
            txs: [{ to_: alice.pkh, token_id: tokenId, amount }]
          }
        ])
        .send();
      await op.confirmation(1);

      const newStorage = await contract.storage();
      const bobNewBalance = await newStorage.ledger.get({ 0:bob.pkh, 1: tokenId });
      expect(bobNewBalance.toNumber()).to.equal(bobOriginalBalance.toNumber() - amount);
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should remove Alice from operators for Bob", async () => {
    try {
      const tokenId = 1
      const contract = await TezosBob.contract.at(contractAddress);
      const storage = await contract.storage();
      const param = {
        owner: bob.pkh,
        operator: alice.pkh,
        token_id: tokenId
      }
      const operator = await storage.operators.get(param);
      expect(operator).to.be.ok;

      const op = await contract.methods.update_operators([{ remove_operator: param }]).send();
      await op.confirmation();
      const newStorage = await contract.storage();
      const aliceNewOperator = await newStorage.operators.get(param);
      expect(aliceNewOperator).to.be.undefined;
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });

  it("Should prevent Alice add an operator for Bob", async () => {
    try {
      const contract = await TezosAlice.contract.at(contractAddress);
      const storage = await contract.storage();
      const tokenId = 1
      const param = {
        owner: bob.pkh,
        operator: alice.pkh,
        token_id: tokenId
      }
      const aliceOperator = await storage.operators.get(param);
      expect(aliceOperator).to.be.undefined;
      await rejects(contract.methods.update_operators([{ add_operator: param }]).send(), (err: Error) => {
          expect(err.message).to.equal("FA2_NOT_OWNER");
          return true;
      });
    } catch (error) {
      expect(error).to.be.undefined;
    }
  });
});
