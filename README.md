# Tezos NFT tokensale contracts


# Requiremets

- Installed [NodeJS](https://nodejs.org/en/) (tested with NodeJS v15+);
- Installed [Yarn](https://classic.yarnpkg.com/lang/en/docs/install/#mac-stable);
- Installed node modules:

  ```shell
    yarn install
  ```

# Compiling contract

Compilation is splitted into a few steps.

To compile all contracts (without lambdas) run the next command:

```shell
  yarn compile
```

# Testing contract

To run all the tests execute the next command:

```shell
  yarn test
```

# Frontend view

To start local frontend:

```shell
  yarn serve
```
Contract must be already compiled. Without it deployment won't work.

# Deploying contract

To deploy testnet contract:

```shell
  yarn migrate
```
To deploy mainet contract:

Copy .env.example to .env and edit ADMIN_SECRET_KEY

```shell
  yarn migrate-mainnet
```

