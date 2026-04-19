# AIDEX Skills

[![version](https://img.shields.io/badge/version-1.0.7-blue)](skills/aidex/package.json)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-compatible-blue)](https://docs.openclaw.ai/tools/skills)

Turn your AI agent into an on-chain trading desk. The [AIDEX](https://ai-dex.io/) skill gives your agent the ability to swap tokens on Ethereum via the AIDEX DEX aggregator — search tokens, quote exchange rates, view balances, and execute swaps with **client-side transaction signing**. The pipeline is optimised for minimal latency between an agent's decision and the moment the signed transaction hits the network.

<div align="center">

<table>
  <tr>
    <td align="center" width="140"><h3>Works<br>with</h3></td>
    <td align="center" width="140">
      <a href="https://openclaw.ai/" title="OpenClaw">OpenClaw</a>
    </td>
  </tr>
</table>

</div>

## Table of Contents

- [Features](#features)
- [Supported Networks](#supported-networks)
- [Installation](#installation)
- [Setup](#setup)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Scripts](#scripts)
- [Security](#security)
- [Links](#links)
- [License](#license)

## Features

- **Token Swaps** — Swap tokens on-chain. The API picks the best route across liquidity pools. The agent just specifies what to trade.
- **Automatic Approvals** — ERC-20 allowance is handled transparently as part of the swap flow — approve transactions are built, signed, and sent automatically when needed.
- **Rate Quotes** — Get current exchange rate and estimated gas cost for any supported pair before trading.
- **Wallet Balances & Allowances** — Query balances for up to 9 tokens at once, including the AIDEX router allowance for each ERC-20.
- **Token Search** — Find tokens by symbol, name, or contract address.
- **Client-side Signing** — Private keys never leave your machine. Transactions are signed locally with ethers.js; the API only broadcasts the signed payload.
- **Transaction Status** — Verify the on-chain result of a swap (including approve steps) by transaction hash.

## Supported Networks

Currently live on **Ethereum mainnet** (chainId 1). Multi-chain EVM support (Base, Arbitrum, Optimism, and more) ships throughout 2026.

## Installation

**From ClawHub:**

```
openclaw skills install aidex
```

**One-click installer:**

```bash
curl -fsSL https://raw.githubusercontent.com/AIDEX-DeFi/skills/main/scripts/aidex-install.sh | bash
```

The script auto-detects your OpenClaw directory (including WSL hosts), downloads the skill bundle, copies it to `~/.openclaw/skills/aidex`, and registers the skill in `openclaw.json`.

**Manual:**

```bash
git clone --branch main https://github.com/AIDEX-DeFi/skills.git /tmp/aidex-skills
cp -r /tmp/aidex-skills/skills/aidex ~/.openclaw/skills/aidex
```

Add to `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "aidex": {
        "enabled": true
      }
    }
  }
}
```

After installation, restart the gateway and start a new chat:

```
openclaw gateway restart
```

Then in the OpenClaw chat type `/new`. On the first request, the agent runs `npm install` in the skill's folder to fetch Node.js dependencies (`ethers` and optionally `@napi-rs/keyring`) — this may take up to a minute. Re-run `npm install` after every skill update.

## Setup

The AIDEX skill works out of the box for read-only operations — searching tokens, checking rates, and viewing balances. **No configuration required.**

To execute swaps, configure your Ethereum private key using one of the options below.

### Option A — Environment variable

**Simple — for testing only.** The private key is passed as a command-line argument and may end up in shell history, process list, and audit logs:

```bash
openclaw config set skills.entries.aidex.env.AIDEX_PRIVATE_KEY "0xYourPrivateKeyHere"
```

**Secure — requires bash (on Windows use WSL).** The key is read interactively into a shell variable and piped via stdin, never appearing in argv:

```bash
read -rsp "AIDEX private key: " k; echo; printf '{"skills":{"entries":{"aidex":{"env":{"AIDEX_PRIVATE_KEY":"%s"}}}}}' "$k" | openclaw config patch --stdin; unset k
```

After changing the config, restart the gateway so the new value takes effect:

```bash
openclaw gateway restart
```

### Option B — System keyring (desktop only)

Store the key in your operating system's credential manager. Not available in Docker, WSL, CI, or headless Linux — use Option A in those environments.

**Windows** (Credential Manager):

```cmd
cmdkey /generic:AIDEX_PRIVATE_KEY.aidex /user:AIDEX_PRIVATE_KEY
```

**macOS** (Keychain):

```bash
security add-generic-password -s aidex -a AIDEX_PRIVATE_KEY -U -w
```

**Linux** (Secret Service — GNOME Keyring, KWallet):

```bash
secret-tool store --label="AIDEX Private Key" service aidex username AIDEX_PRIVATE_KEY target default
```

In all three commands above, you will be prompted to enter the private key interactively.

If both sources are set, the environment variable wins.

## Quick Start

```
> What's the current ETH/USDC rate?
> Show my wallet address
> Check my ETH and USDC balance
> Swap 0.5 ETH to USDC
```

## Usage

Talk to the agent in natural language. It picks the right script for the job.

### Basic flow

| Step           | Example prompts                                                                   |
| -------------- | --------------------------------------------------------------------------------- |
| **Rate**       | _"Quote 1 ETH to USDC"_ / _"What's the DAI/WBTC rate for 1000 DAI?"_              |
| **Balance**    | _"Show my ETH, USDC, and WBTC balances"_ / _"How much USDT do I have?"_           |
| **Swap**       | _"Swap 0.5 ETH to USDC"_ / _"Sell 1000 USDC for DAI with 0.3% slippage"_          |
| **Verify**     | _"Check the status of the last swap"_ / _"Did my USDC approve go through?"_       |

### Specifying tokens

Tokens can be identified by **symbol** (`ETH`, `USDC`, `WBTC`) or by **contract address** (`0xA0b8…eB48`). If a symbol matches multiple tokens the agent will show you the candidates so you can pick by address.

### Tuning a swap

- `--slippage <percent>` — maximum tolerated slippage, default `0.5` (0.5%).
- `--deadline-minutes <min>` — transaction deadline, default `20`, clamped to `[1, 60]`.

The agent surfaces these as optional knobs: _"Swap 0.5 ETH to USDC with 1% slippage"_, _"…with 30-minute deadline"_.

## Scripts

| Script                                         | Purpose                                                                                                        |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `scripts/aidex-install.sh`                     | One-click installer for OpenClaw: downloads the skill bundle, copies it, registers in `openclaw.json`          |
| `skills/aidex/scripts/account.js`              | Derive the wallet address from the configured private key (no API call, no network)                           |
| `skills/aidex/scripts/tokens.js`               | Search the supported token list by symbol, name, or address                                                    |
| `skills/aidex/scripts/rate.js`                 | Quote the current exchange rate and estimated gas cost for a token pair                                        |
| `skills/aidex/scripts/balance.js`              | Read token balances and router allowances for a wallet (up to 9 tokens per call)                               |
| `skills/aidex/scripts/swap.js`                 | Execute a full swap cycle: build transactions via API, sign locally, broadcast (approve + swap)                |
| `skills/aidex/scripts/swap-status.js`          | Verify the on-chain status of a swap operation by transaction hash (1–3 hashes)                                |

Every script prints a single line of JSON to stdout — `{"success": true, ...}` on success, `{"success": false, "error": "…"}` on failure — and exits with a matching status code. See [`skills/aidex/references/scripts.md`](skills/aidex/references/scripts.md) for full argument and output reference.

## Security

AIDEX uses a **client-side signing architecture**. Your private key never leaves your machine — not over the wire, not into logs, not as a CLI argument.

A swap works like this:

1. The script sends high-level parameters (which tokens, how much) to the AIDEX API. **No private key.**
2. The API computes the route and returns a complete *unsigned* transaction (plus any approve transactions needed).
3. The script signs the transactions locally via `ethers.Wallet.signTransaction()`.
4. The signed raw transactions are sent back to the API, which broadcasts them to Ethereum — the same thing any public RPC endpoint does with `eth_sendRawTransaction`.

Because signed transactions are cryptographically bound to their parameters, a compromised AIDEX server still **cannot** alter the recipient, amounts, call data, or gas fields of what you signed. It can only broadcast exactly what you signed.

Read-only operations (`tokens`, `rate`, `balance`, `swap-status`) require no key at all and use only public blockchain data.

For the full threat model, risk assessment, and rationale behind the `primaryEnv` field in the manifest, see [skills/aidex/references/security.md](skills/aidex/references/security.md).

## Links

- [AIDEX](https://ai-dex.io/)
- [OpenClaw Skills Documentation](https://docs.openclaw.ai/tools/skills)
- [Skill reference — scripts](skills/aidex/references/scripts.md)
- [Skill reference — security](skills/aidex/references/security.md)

## License

MIT
