---
layout: page
title: Privacy Policy
permalink: /privacy/
---

Effective date: July 3, 2026

AIUM is an iOS app for individuals to view their GitHub Copilot and OpenAI Codex usage. This policy explains how AIUM handles information.

## Information AIUM handles

AIUM handles only the information needed to authenticate with the services you choose and display usage information:

- Authentication credentials, including access and refresh tokens
- Account identifiers and display names returned by GitHub or OpenAI
- Usage, allowance, and rate-limit information returned by GitHub or OpenAI
- App preferences, including refresh settings, manually entered usage limits, and the Demo Mode setting

AIUM does not include advertising or analytics SDKs and does not collect location, contacts, photos, advertising identifiers, or diagnostic data for the developer.

## How information is used and stored

Authentication credentials are stored in the iOS Keychain. Usage snapshots are stored on your device or in the app's local App Group container so the AIUM widget can display them. Preferences are stored locally on your device.

AIUM does not operate a developer-controlled backend and does not upload this information to the developer or synchronize it through a developer cloud service.

## Communication with GitHub and OpenAI

When you sign in or refresh usage, AIUM communicates directly from your device with the service you selected. Automatic background refresh may also make these requests based on your refresh setting. The requests include the credentials and account information required by that service to authenticate you and return usage data.

Information processed by these services is governed by their respective policies:

- [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- [OpenAI Privacy Policy](https://openai.com/policies/privacy-policy/)

AIUM does not sell your information or share it with advertising, analytics, or data-broker services.

## Retention, deletion, and revoking access

AIUM retains credentials, cached usage information, and preferences on your device until you remove them.

- Signing out of GitHub or Codex in AIUM deletes that service's credentials and cached usage information from the app.
- You can revoke AIUM's access separately from the relevant GitHub or OpenAI account settings.
- Deleting AIUM removes its locally stored app data from the device. Remove any remaining widget before deletion if iOS still displays it.

The developer does not hold a server-side copy of AIUM data and therefore has no developer-hosted account data to delete.

## Website hosting

This policy and the AIUM support site are hosted by GitHub Pages. GitHub may process standard web request information when you visit these pages under the GitHub Privacy Statement linked above.

## Changes

This policy may be updated when AIUM's data handling changes. The effective date at the top of this page will be updated when a revision is published.

## Contact

For privacy questions, open a [GitHub issue](https://github.com/Freeesia/AIUM/issues). Do not include access tokens, credentials, or personal information in a public issue.
