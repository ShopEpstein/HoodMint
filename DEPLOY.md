# Deploying HoodMint

The contracts are built and compile clean (`npm run compile`, solc 0.8.24 + viaIR).
This session's sandbox has no network path to Robinhood Chain's RPC, faucet, or
Blockscout (its egress policy blocks those hosts outright), so the actual deploy
transactions have to be broadcast from a machine that isn't behind that block —
your laptop, a CI runner, or your browser wallet. Two ways to do it:

## Option A — CLI (hardhat), your own machine

```bash
git clone https://github.com/ShopEpstein/HoodMint
cd HoodMint
npm install
cp .env.example .env
# edit .env, set DEPLOYER_PRIVATE_KEY to a wallet funded with a little ETH
# (sub-cent gas on Robinhood Chain). Use a wallet you don't mind burning —
# never reuse a key that's touched a browser session or chat history for
# anything holding real value afterward.
```

1. **Rehearse on testnet first** (free — get test ETH from
   `https://faucet.testnet.chain.robinhood.com`):
   ```bash
   npm run deploy:test
   ```
2. **Go live** once the testnet run looks right:
   ```bash
   npm run deploy
   ```
   Copy the printed `HoodMintFactory` address.
3. **Verify on Blockscout:**
   ```bash
   npx hardhat verify --network robinhood <FACTORY_ADDRESS> <DEPLOYER_ADDRESS>
   ```
4. Put `<FACTORY_ADDRESS>` into `web/index.html` → `const FACTORY_ADDRESS = "..."`,
   commit, push.

## Option B — No CLI, just MetaMask + Remix (remix.ethereum.org)

1. Add Robinhood Chain to MetaMask: chain ID `4663`, RPC
   `https://rpc.mainnet.chain.robinhood.com`, explorer
   `https://robinhoodchain.blockscout.com`.
2. In Remix, create the three files under `contracts/` from this repo
   (`HoodMintCollection.sol`, `HoodMintFactory.sol`,
   `interfaces/ITransferValidator.sol`) plus the OpenZeppelin/ERC721A imports
   (Remix resolves `npm:@openzeppelin/contracts` and `npm:erc721a` imports
   automatically).
3. Compiler tab: solc `0.8.24`, enable optimizer (200 runs) **and** "Enable
   viaIR".
4. Deploy tab: environment "Injected Provider – MetaMask" (confirms you're on
   chain 4663), contract `HoodMintFactory`, constructor arg `owner_` = your
   wallet address. Deploy — MetaMask prompts you for the sub-cent gas fee.
5. Copy the deployed address into `web/index.html` → `FACTORY_ADDRESS`.
6. Verify via the Blockscout UI's "Verify & Publish" on the contract page
   (flattened source, same compiler settings as step 3), or the CLI command
   above.

## After the factory is live

`web/index.html` → `FACTORY_ADDRESS` is the only code change needed. Everyone
after that deploys their own collection through the **Launch** tab in their
own browser wallet — no server-held key, no cost to you, ever.

## Hosting — Cloudflare (free, no payment method needed)

Cloudflare currently has two separate free products that both host static
sites + a small API route, and they are **not interchangeable** — a project
built for one silently doesn't work on the other:

- **Pages** (`*.pages.dev`, "Connect to Git" flow) — routes any file under
  `functions/` automatically; that's what `functions/api/pin.js` is for.
- **Workers** (`*.workers.dev`, the newer unified "Workers & Pages ->
  Workers" product, Git-connected via "Workers Builds", deploy command
  `npx wrangler deploy`) — needs an explicit `wrangler.jsonc` config and a
  single worker entry script; that's what `wrangler.jsonc` + `worker.js` at
  the repo root are for.

**If your project already shows a `workers.dev` URL and a "Deploy command:
npx wrangler deploy"** (check Settings on the project), you're on Workers —
`wrangler.jsonc` + `worker.js` in this repo now match that exactly:
`assets.directory` points at `web/`, and `worker.js` handles `POST /api/pin`
itself, falling through to static assets for everything else. Just:

1. Push this repo (already done) so the Worker project's connected branch
   has `wrangler.jsonc` and `worker.js` at the root.
2. In the dashboard, **Retry build** (or push again — it auto-redeploys on
   every push to the connected branch).
3. **Settings → Variables and Secrets** → add `PINATA_JWT` as a **Secret**
   (from app.pinata.cloud → API Keys → new key → copy JWT) → **Retry
   build**. Skip this if you'd rather creators paste a CID manually — the
   console still works without it.

Workers' free tier covers this fully: 100k requests/day, no card required.

**If you'd rather use classic Pages instead** (`*.pages.dev`): dash.cloudflare.com
→ Workers & Pages → Create → **Pages** → Connect to Git → pick the repo →
Build output directory `web`, build command empty, root directory `/` →
Deploy. `functions/api/pin.js` is already in place for that path; set
`PINATA_JWT` under Settings → Environment variables the same way.

Either way: every push to the connected branch auto-redeploys, no local
build needed.
