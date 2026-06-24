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

**Setup:** Create an OAuth App at https://github.com/settings/developers and enable device flow under the app settings. Set the Client ID through the AIUM target build setting `GITHUB_OAUTH_CLIENT_ID`; `AIUM/Info.plist` exposes it to the app as `GitHubOAuthClientID`. Local builds should put the real value in ignored `Config/AIUM.local.xcconfig`; leave the tracked placeholder `YOUR_GITHUB_CLIENT_ID` in place to disable GitHub login.

**Failure diagnostics:** AIUM preserves GitHub usage failures as plan-specific error snapshots. HTTP failures include the status code and response body preview. Decode failures include the endpoint name so plan unsupported cases, endpoint changes, and response-shape changes can be distinguished in the UI.

---

## OpenAI / Codex APIs

> ⚠️ **WARNING: The Codex API details below describe PRIVATE, UNDOCUMENTED endpoints.**
>
> - These endpoints are not officially supported by OpenAI.
> - They may change or be removed at any time without notice.
> - They should NOT be used in a public/commercial product.
> - All Codex API details are isolated in `PrivateCodexUsageProvider.swift` and `CodexAuthProvider.swift` so they can be replaced when official APIs are released.

### Authentication: Codex Device Code Flow

Codex uses a Codex-specific device authorization flow exposed through the
ChatGPT auth account API, then exchanges the returned authorization code through
the normal OAuth token endpoint.

**Endpoints used by the current implementation:**
```
POST https://auth.openai.com/api/accounts/deviceauth/usercode
POST https://auth.openai.com/api/accounts/deviceauth/token
POST https://auth.openai.com/oauth/token
```

`/deviceauth/usercode` returns `device_auth_id`, `user_code`, string `interval`,
and `expires_at`. The user is sent to `https://auth.openai.com/codex/device`.
`/deviceauth/token` returns `authorization_code`, `code_challenge`, and
`code_verifier` after the user approves the code; pending states are represented
by HTTP 403/404 until approval or timeout.

**Client ID:** `CODEX_OAUTH_CLIENT_ID` is passed through `AIUM/Info.plist` as `CodexOAuthClientID`. The tracked default currently matches the Codex app-server login client ID (`app_EMoamEEZ73f0CkXaXp7hrann`) and can be overridden from ignored `Config/AIUM.local.xcconfig` if OpenAI changes it.

**Token bundle stored in Keychain:**
- `id_token` — OIDC identity token
- `access_token` — ****** for API calls
- `refresh_token` — Used for silent refresh
- `expires_at` — Computed from `expires_in`
- `account_id` — Optional user identifier
- `email` — Optional display name

**Token refresh:** AIUM implements single-flight refresh protection — if multiple concurrent tasks request a valid token, only one refresh is performed and all waiters receive the result.

AIUM extracts `account_id` and `email` from the returned JWT claims when available. Usage refresh also calls the Codex profile endpoint and updates the stored account display metadata if the backend returns it.

### Codex Usage / Rate Limits

```
GET https://chatgpt.com/backend-api/wham/usage
Authorization: ******
ChatGPT-Account-Id: {account_id}  # when known
```

**Supported response shapes:**

Current Codex backend-style rate limits:
```json
{
  "rateLimits": [
    {
      "limitId": "gpt-5-codex",
      "limitName": "GPT-5 Codex",
      "individualLimit": 100,
      "primary": {
        "remaining": 25,
        "limitWindowSeconds": 18000,
        "resetAfterSeconds": 3600
      },
      "secondary": {
        "usedPercent": 40,
        "windowDurationMins": 10080,
        "resetsAt": "2024-01-16T00:00:00Z"
      }
    }
  ],
  "rateLimitResetCredits": { "remaining": 2 }
}
```

Legacy snake_case windows are still accepted:
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
- If `used` is present, use it directly.
- Else if `limit` and `remaining` are present, `used = limit - remaining`.
- Else if `usedPercent` / `used_percent` is present with a limit, `used = limit * usedPercent / 100`.
- Percent-only windows are normalized to `limit = 100`, `unit = "percent"`.
- `limitWindowSeconds`, `windowDurationMins`, `resetAfterSeconds`, `resetsAt`, and `reset_at` are normalized into `UsageSnapshot.windowDurationMins` and `UsageSnapshot.resetAt`.

**Failure diagnostics:** HTTP errors include the endpoint name, status code, and body preview. Decode failures and empty usage payloads are surfaced as Codex error snapshots so private API changes are visible in the app UI.

---

## Adding Official APIs

When official GitHub Copilot or Codex usage APIs are released:

1. Create a new file in `AIUM/Providers/GitHub/` or `AIUM/Providers/Codex/`
2. Implement the `UsageProvider` (or `CodexUsageProvider`) protocol
3. Swap the concrete type in `DashboardViewModel` and `SettingsViewModel`
4. Delete or mark `PrivateCodexUsageProvider.swift` as deprecated

The `UsageSnapshot` model is designed to be provider-agnostic and should not need changes.
