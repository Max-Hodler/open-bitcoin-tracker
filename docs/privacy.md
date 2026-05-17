---
layout: default
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy

_Last updated: 2026-05-17_

Open Bitcoin Tracker ("the app") is a free, open-source Android app that lets you track the value of your bitcoin portfolio. This page explains exactly what the app does — and does not do — with your data.

## Summary

- **No accounts. No sign-in. No analytics. No advertising. No tracking SDKs.**
- The app does **not** collect, transmit, or share any personal information.
- Everything you type into the app — stack names, bitcoin amounts, settings — is stored only on your device.
- The only network requests the app makes are to public market-data and Bitcoin-network endpoints, and those requests do **not** include any information about you.

## What stays on your device

The following data is stored locally on your Android device and never leaves it:

- The stacks you create (names and bitcoin amounts).
- Your app settings (currency, theme, haptics, lock mode, etc.).
- Your PIN (if you set one).

You can optionally lock the app with a PIN or biometrics to hide the value of your stacks from anyone who picks up your device. The app developer has no way to recover your stacks if you uninstall the app, lose the device, or forget your PIN.

The app explicitly opts out of Android cloud backup and device-transfer for its own data, so your stacks are not silently copied to Google's servers as part of system backups.

## What the app fetches from the network

To show you live and historical Bitcoin prices and current network conditions, the app makes anonymous, read-only requests to public services:

- **Kraken** — for the live price stream and historical OHLC candles.
  - WebSocket: `wss://ws.kraken.com/v2`
  - REST: `https://api.kraken.com`
- **mempool.space** — for current network hashrate and mempool/block data.
  - REST: `https://mempool.space/api`

In addition, long-range price charts use a **Coin Metrics** daily BTC/USD reference-rate dataset (`assets/btc_history.csv`) that is bundled inside the app at build time. This dataset is not fetched at runtime, and the app does not contact Coin Metrics' servers.

These requests contain only the information needed to ask for a price or a block (e.g. a trading pair like `BTC/USD`, or a hashrate window like `3d`). They do not include any account identifier, device identifier, advertising ID, name, email, or location. Kraken, mempool.space, and your network provider can see your device's IP address, as is true for any internet request — the app developer does not.

## Links that open in your browser

A few places in the app — the block details sheet, and the links on the About screen (GitHub, Kraken, Coin Metrics, mempool.space, this privacy policy) — open URLs in your device's default browser. Once you tap one, your browser is the one making the request, and its own privacy behavior (and any privacy policy of the destination site) applies.

## Permissions the app requests

- **Internet access** — to fetch live and historical Bitcoin prices and Bitcoin-network data.
- **Use biometric** — only if you choose to lock your stacks with your fingerprint or face. The biometric check is performed by Android; the app never sees your biometric data.

## Children

The app is not directed at children. As stated above, the app does not collect any personal data from anyone, of any age.

## Changes to this policy

If this policy ever changes, the updated version will be published at this URL and the "Last updated" date above will reflect the change. Because the source for this page lives in the app's public GitHub repository, the full history of changes is auditable in the [repository's commit log](https://github.com/Max-Hodler/open-bitcoin-tracker).

## Contact

Questions about this policy can be filed as an issue on the project's GitHub repository: <https://github.com/Max-Hodler/open-bitcoin-tracker/issues>
