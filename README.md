# AIUM — AI Usage Monitor

> **Personal-use iOS app** that monitors usage limits for **GitHub Copilot** and **OpenAI Codex**, and displays them on the Home Screen and Lock Screen via iOS widgets.

---

## ⚠️ Important Warning

**AIUM currently uses private / undocumented OpenAI/Codex API endpoints.**

- These endpoints are not officially supported and **may change or disappear without notice**.
- This app is intended for **personal use only**.
- **Do NOT submit to the public App Store** until official usage APIs are available.
- GitHub API endpoints used are official and documented, but billing APIs may require specific plan levels.

---

## Features

| Feature | Status |
|---------|--------|
| GitHub Copilot AI Credit usage | ✅ |
| GitHub Copilot legacy Premium Requests | ✅ |
| OpenAI Codex rate-limit usage | ✅ (private API) |
| Home Screen widget (small, medium) | ✅ |
| Lock Screen widget | ✅ |
| GitHub Device Flow login | ✅ |
| Codex device-code login | ✅ |
| Keychain token storage | ✅ |
| App Group shared cache | ✅ |
| Manual limit overrides | ✅ |
| MVVM architecture | ✅ |
| Unit tests | ✅ |

---

## Setup

### Requirements

- macOS 14 or later
- Xcode 15 or later
- iOS 17+ device or simulator

### Step 1: Clone and open

```bash
git clone https://github.com/Freeesia/AIUM.git
open AIUM.xcodeproj
```

### Step 2: Configure signing

1. In Xcode, select the **AIUM** project
2. Set your **Team** in the Signing & Capabilities pane for both `AIUM` and `AIUMWidget` targets

### Step 3: Configure the App Group

1. In **Signing & Capabilities** for both `AIUM` and `AIUMWidget`, add an **App Groups** capability
2. Use the identifier: `group.io.github.freeesia.aium` (or your own)
3. Update `UsageStore.appGroupIdentifier` in `AIUM/Storage/UsageStore.swift` if you changed it

### Step 4: Configure GitHub OAuth

1. Go to [GitHub Developer Settings → OAuth Apps](https://github.com/settings/developers)
2. Create a new OAuth App with device flow enabled
3. Copy the **Client ID**
4. Replace `YOUR_GITHUB_CLIENT_ID` in `AIUM/Providers/GitHub/GitHubAuthProvider.swift`:
   ```swift
   static let clientId = "YOUR_GITHUB_CLIENT_ID"  // ← replace this
   ```

### Step 5: Configure Codex (optional / experimental)

1. Replace `YOUR_CODEX_CLIENT_ID` in `AIUM/Providers/Codex/CodexAuthProvider.swift`
2. Verify the endpoint paths in `PrivateCodexUsageProvider.swift` — these use private APIs and may need adjustment
3. See `docs/API_NOTES.md` for details

### Step 6: Build and run

Select the **AIUM** scheme and run on a device or simulator.

---

## Architecture

```
AIUM/
├── AIUMApp.swift               # App entry point
├── Models/
│   └── UsageSnapshot.swift     # Normalized usage model (shared with widget)
├── Storage/
│   ├── UsageStore.swift        # App Group JSON cache (shared with widget)
│   └── KeychainHelper.swift    # Keychain wrapper
├── Providers/
│   ├── UsageProviderProtocol.swift
│   ├── GitHub/
│   │   ├── GitHubAuthProvider.swift    # Device flow auth
│   │   ├── GitHubAPIClient.swift       # REST API client
│   │   └── GitHubUsageProvider.swift   # Usage normalization
│   └── Codex/
│       ├── CodexAuthProvider.swift     # Token management + refresh
│       └── PrivateCodexUsageProvider.swift  # ⚠️ Private API
├── ViewModels/
│   ├── DashboardViewModel.swift
│   └── SettingsViewModel.swift
└── Views/
    ├── DashboardView.swift
    ├── UsageCardView.swift
    └── SettingsView.swift

AIUMWidget/
├── AIUMWidgetBundle.swift      # Widget bundle entry
├── AIUMWidget.swift            # Timeline providers
└── AIUMWidgetView.swift        # Widget views

AIUMTests/
├── UsageSnapshotTests.swift
├── GitHubParsingTests.swift
└── CodexParsingTests.swift
```

### Design Principles

- **MVVM**: Views observe ViewModels; ViewModels coordinate with Providers
- **Actor isolation**: Auth providers and API clients are `actor` types for Swift concurrency safety
- **Modular providers**: `UsageProvider` protocol allows swapping implementations without UI changes
- **No third-party dependencies**: Uses only Apple frameworks
- **Keychain for secrets**: Tokens never stored in UserDefaults or plaintext files
- **App Group for widget data**: Widget reads a JSON file from the shared container

---

## Keychain Usage

| Key | Service | Account | Contents |
|-----|---------|---------|----------|
| GitHub access token | `io.github.freeesia.aium` | `github_access_token` | OAuth access token |
| Codex token bundle | `io.github.freeesia.aium` | `codex_token_bundle` | JSON-encoded `CodexTokenBundle` |

---

## App Group

Both the app and widget extension share an App Group container (`group.io.github.freeesia.aium`).

- The main app writes `usage_snapshots.json` to the container after each refresh
- The widget reads this file in its `TimelineProvider` without performing any network calls or login

---

## Known Limitations

1. **Codex private API**: The Codex usage endpoint is undocumented and fragile. The current implementation is a best guess and may require updates.
2. **GitHub billing APIs**: These APIs may require the user to be on a paid GitHub Copilot plan.
3. **No push/background refresh**: iOS background execution for networking is unreliable. The widget refreshes on its own schedule (~30 min) by reading the cached file.
4. **No iPad/Mac support**: App is iOS-phone only by design per project requirements.
5. **No iCloud sync**: Tokens and settings are local-only.

---

## License

MIT — see [LICENSE](LICENSE)