---
layout: default
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy

_Last updated: 2026-05-01_

Open Bitcoin Tracker ("the app") is a free, open-source Android app that lets you track the Bitcoin price and record how much you hold in satoshis. This page explains exactly what the app does — and does not do — with your data.

## Summary

- **No accounts. No sign-in. No analytics. No advertising. No tracking SDKs.**
- The app does **not** collect, transmit, or share any personal information.
- Everything you type into the app — stack names, satoshi amounts, settings — is stored only on your device.
- The only network requests the app makes are to public market-data endpoints, and those requests do **not** include any information about you.

## What stays on your device

The following data is stored locally on your Android device and never leaves it:

- The stacks you create (names and satoshi amounts).
- Your app settings (currency, theme, haptics, lock mode, etc.).
- Your PIN (if you set one).

You can optionally lock the app with a PIN or biometrics to hide the value of your stacks from anyone who picks up your device. The app developer has no way to recover your stacks if you uninstall the app, lose the device, or forget your PIN.

The app explicitly opts out of Android cloud backup and device-transfer for its own data, so your stacks are not silently copied to Google's servers as part of system backups.

## What the app fetches from the network

To show you live and historical Bitcoin prices, the app makes anonymous, read-only requests to public market-data services:

- **Kraken** — for the live price stream and historical OHLC candles.
  - WebSocket: `wss://ws.kraken.com/v2`
  - REST: `https://api.kraken.com`
- **Bundled historical data** from **Coin Metrics**, shipped inside the app for long-range charts. This data is not fetched at runtime.

These requests contain only the information needed to ask for a price (e.g. a trading pair like `BTC/USD`). They do not include any account identifier, device identifier, advertising ID, name, email, or location. Kraken and your network provider can see your device's IP address, as is true for any internet request — the app developer does not.

## Permissions the app requests

- **Internet access** — to fetch live and historical Bitcoin prices.
- **Use biometric** — only if you choose to lock your stacks with your fingerprint or face. The biometric check is performed by Android; the app never sees your biometric data.

## Children

The app is not directed at children. It does not knowingly collect any data from anyone, regardless of age.

## Changes to this policy

If this policy ever changes, the updated version will be published at this URL and the "Last updated" date above will reflect the change. Because the source for this page lives in the app's public GitHub repository, the full history of changes is auditable in the [repository's commit log](https://github.com/Max-Hodler/open-bitcoin-tracker).

## Contact

Questions about this policy can be filed as an issue on the project's GitHub repository: <https://github.com/Max-Hodler/open-bitcoin-tracker/issues>
