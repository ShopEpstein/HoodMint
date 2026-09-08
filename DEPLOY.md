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

## Hosting — Cloudflare Pages (free, no CLI, no payment method needed)

This repo is already laid out for it: `web/index.html` is the static site,
`functions/api/pin.js` is the pinning endpoint in Cloudflare's Pages
Functions format (Fetch API `Request`/`Response`, not Vercel's Node
`req`/`res` — `api/pin.js` is kept only as a reference if you ever move to a
Node-style host). Cloudflare Pages' free tier covers both: unlimited static
requests, 100k Functions requests/day, no card required.

1. **dash.cloudflare.com** → sign up/log in (free account) → **Workers &
   Pages** → **Create** → **Pages** → **Connect to Git**.
2. Authorize GitHub, pick **ShopEpstein/HoodMint**, branch
   `claude/hoodmint-full-deploy-9iloaa` (or `main` once you merge it).
3. Build settings:
   - Framework preset: **None**
   - Build command: *(leave empty — it's static HTML, nothing to build)*
   - Build output directory: `web`
   - Root directory: *(leave as `/` — Pages Functions must live at the repo
     root's `functions/` folder, which is where it already is)*
4. **Save and Deploy.** First deploy takes under a minute. You get a free
   `*.pages.dev` URL immediately; add a custom domain later for free too if
   you own one.
5. **Settings → Environment variables** → add `PINATA_JWT` (from
   app.pinata.cloud → API Keys → new key → copy JWT) for both **Production**
   and **Preview** → **Save**, then **Retry deployment** so it picks it up.
   Skip this if you'd rather creators paste a CID manually — the console
   still works without it, it just skips auto-pinning.

That's it — every push to that branch auto-redeploys. No `wrangler`, no
local Node build, nothing outside the browser.
