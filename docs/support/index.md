---
layout: page
title: Support
permalink: /support/
---

For help with AIUM, search the [existing GitHub issues](https://github.com/Freeesia/AIUM/issues) or [open a new issue](https://github.com/Freeesia/AIUM/issues/new/choose).

GitHub Issues are public. Do not post access tokens, authorization codes, credentials, account identifiers, screenshots containing private information, or other personal information.

## Before opening an issue

Include the AIUM version, iOS version, affected provider, and the steps that reproduce the problem. Remove private information from screenshots and logs.

### GitHub sign-in

- Confirm the GitHub device-code page completed successfully.
- If the session expired, sign out in AIUM Settings and sign in again.
- AIUM can only display usage data that the GitHub API makes available for your account and plan.

### Codex sign-in

- Confirm the Codex device-code page completed successfully.
- If the session expired, sign out in AIUM Settings and sign in again.
- Codex usage availability and response formats can change with the service.

### Widget display

- Open AIUM and refresh usage before adding or troubleshooting the widget.
- Confirm the main app shows current data.
- Remove and add the widget again if it remains stale after the app refreshes.
- Widget refresh timing is controlled by iOS and may not be immediate.

### App Group configuration

App Group configuration is required only for development builds. The AIUM app and AIUMWidget targets must both use `group.com.studiofreesia.aium`. A missing or mismatched entitlement prevents the widget from reading the app's cached data.

## Privacy

See the [AIUM Privacy Policy]({% link privacy/index.md %}) for details about local storage, service communication, and deletion.
