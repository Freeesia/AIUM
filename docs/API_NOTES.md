# API Notes

This document describes the GitHub and Codex API endpoints used by AIUM.

---

## GitHub APIs

All GitHub API requests use the `Authorization: ****** header and target `https://api.github.com`.

### Authenticated User

```
GET /user
```

Returns the authenticated user's profile. Used to obtain the `login` (username) needed for billing endpoints.

**Response fields used:**
- `login` — GitHub username
- `id` — numeric user ID
- `name` — display name (may be null)

### GitHub Copilot AI Credit Usage

```
GET /users/{username}/settings/billing/ai_credit/usage
```

Returns usage for the newer "AI Credits" billing model used by GitHub Copilot.

**Response fields used:**
- `used_in_current_period` — credits consumed so far this month
- `total_allowance` — total monthly credit allowance (may be null; use manual override in Settings)
- `current_period_end` — ISO 8601 timestamp for when the period resets

> **Note:** This endpoint may require a specific Copilot plan tier and may not be available to all users.

### GitHub Copilot Legacy Premium Requests

```
GET /users/{username}/settings/billing/premium_request/usage
```

Returns usage for the older "Premium Requests" billing model.

**Response fields used:**
- `used_premium_requests` — requests used so far
- `included_premium_requests` — included monthly allowance (may be null; use manual override)
- `last_updated_at` — when the usage data was last updated

> **Note:** This endpoint may be deprecated in the future as GitHub transitions to the AI Credits model.

### Authentication: GitHub Device Flow

AIUM uses the [GitHub Device Flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow) to avoid requiring a custom URL callback.

1. App POSTs to `https://github.com/login/device/code` with `client_id` and `scope`
2. User visits `verification_uri` and enters `user_code`
3. App polls `https://github.com/login/oauth/access_token` with `device_code`
4. Access token is stored in the Keychain

**Required scopes:** `read:user`, `read:org`

**Setup:** Create an OAuth App at https://github.com/settings/developers. Enable device flow under the app settings.

---

## OpenAI / Codex APIs

> ⚠️ **WARNING: The Codex API details below describe PRIVATE, UNDOCUMENTED endpoints.**
>
> - These endpoints are not officially supported by OpenAI.
> - They may change or be removed at any time without notice.
> - They should NOT be used in a public/commercial product.
> - All Codex API details are isolated in `PrivateCodexUsageProvider.swift` and `CodexAuthProvider.swift` so they can be replaced when official APIs are released.

### Authentication: Codex Device Code Flow

Similar to GitHub's device flow, Codex uses an OIDC device authorization grant.

**Endpoints (UNVERIFIED — may need adjustment):**
```
POST https://auth.openai.com/oauth/device/code
POST https://auth.openai.com/oauth/token
```

**Token bundle stored in Keychain:**
- `id_token` — OIDC identity token
- `access_token` — ****** for API calls
- `refresh_token` — Used for silent refresh
- `expires_at` — Computed from `expires_in`
- `account_id` — Optional user identifier
- `email` — Optional display name

**Token refresh:** AIUM implements single-flight refresh protection — if multiple concurrent tasks request a valid token, only one refresh is performed and all waiters receive the result.

### Codex Usage / Rate Limits

```
GET https://api.openai.com/v1/usage/rate_limits
Authorization: ******
```

> **TODO:** Verify this endpoint path. The actual path may differ.

**Expected response shape (UNVERIFIED):**
```json
{
  "primary_window": {
    "limit": 50,
    "remaining": 20,
    "reset_at": "2024-01-15T12:00:00Z",
    "window_duration_mins": 60,
    "used_percent": null
  },
  "secondary_window": {
    "limit": 500,
    "remaining": 350,
    "reset_at": "2024-01-16T00:00:00Z",
    "window_duration_mins": 1440
  },
  "reset_credits": null
}
```

**Normalization logic:**
- `used = limit - remaining` (unless `used_percent` is provided, in which case `used = limit * used_percent / 100`)
- Primary window → `WindowKind.custom` (hourly)
- Secondary window → `WindowKind.daily`

---

## Adding Official APIs

When official GitHub Copilot or Codex usage APIs are released:

1. Create a new file in `AIUM/Providers/GitHub/` or `AIUM/Providers/Codex/`
2. Implement the `UsageProvider` (or `CodexUsageProvider`) protocol
3. Swap the concrete type in `DashboardViewModel` and `SettingsViewModel`
4. Delete or mark `PrivateCodexUsageProvider.swift` as deprecated

The `UsageSnapshot` model is designed to be provider-agnostic and should not need changes.
