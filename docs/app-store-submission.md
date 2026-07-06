# App Store Connect 提出メモ

Issue #40 の提出作業で App Store Connect へ転記する内容をまとめる。回答は提出対象ビルドの実装が変わるたびに再確認すること。

## App Privacy

- Privacy Policy URL: `https://aium.studiofreesia.com/privacy/`
- Tracking: No
- Third-Party Advertising: No
- Developer's Advertising or Marketing: No
- Analytics: No
- Data Broker への共有: No

現在の実装は開発者管理サーバー、広告 SDK、解析 SDK を使用しない。ただし GitHub と OpenAI のアカウントへ端末から直接接続し、認証・利用状況取得を行うため、次の項目を保守的に申告する。

| App Store Connect のデータ種別 | 用途 | ユーザーにリンク | Tracking |
| --- | --- | --- | --- |
| Contact Info > Email Address | App Functionality | Yes | No |
| Identifiers > User ID | App Functionality | Yes | No |
| Usage Data > Other Usage Data | App Functionality | Yes | No |

根拠:

- Codex のトークン情報にはアカウント ID とメールアドレスが含まれ、Keychain に端末内保存される。
- GitHub のユーザー ID、ユーザー名、Copilot 使用量と、Codex のアカウント ID、メールアドレス、レート制限情報を各サービスから取得する。
- 認証情報は Keychain、利用状況は端末内またはローカル App Group コンテナ、設定値は UserDefaults に保存する。
- 開発者管理サーバーへの送信、広告、解析、マーケティング、第三者への販売・共有は行わない。

注意: Apple の定義では、端末内だけで処理するデータは「収集」に当たらない。一方、AIUM はユーザーが選択した GitHub / OpenAI と継続的に直接通信するため、審査時の過少申告を避ける目的で上記を申告する。提出前に App Store Connect の最新設問と各サービスの処理内容を再確認する。

## 年齢レーティング

以下はすべて `None` または `No` とする。

- Parental Controls / Age Assurance: No
- Unrestricted Web Access: No
- User-Generated Content: No
- Messaging and Chat: No
- Advertising: No
- Profanity or Crude Humor / Horror or Fear Themes: None
- Alcohol, Tobacco, Drugs: None
- Medical or Treatment Information: None
- Mature or Suggestive Themes / Sexual Content / Nudity: None
- Cartoon, Fantasy, Realistic or Graphic Violence: None
- Guns or Other Weapons: None
- Contests / Loot Boxes / Simulated Gambling / Gambling: None

AIUM 内のブラウザは GitHub / OpenAI の認証ページ、プライバシーポリシー、サポートページという固定 URL の表示だけに使用し、任意 URL を自由に閲覧する機能はない。このため `Unrestricted Web Access` は `No` とする。

## App Review Notes

以下を App Review Notes に貼り付ける。

```text
AIUM is an unofficial personal usage dashboard for GitHub Copilot and OpenAI Codex. It is not affiliated with, endorsed by, or sponsored by GitHub, Microsoft, or OpenAI.

REVIEW WITHOUT AN ACCOUNT
Demo Mode lets App Review inspect the complete dashboard and widgets without GitHub or OpenAI credentials:
1. Open the iOS Settings app.
2. Go to Apps > AIUM.
3. Enable Demo Mode.
4. Return to AIUM (relaunch it if it was already open).
5. The dashboard displays clearly marked sample data. Sign-in is disabled while Demo Mode is enabled.

BACKGROUND REFRESH
AIUM registers the BGAppRefreshTask identifier com.studiofreesia.aium.usage-refresh. When iOS grants background execution and the user has enabled automatic refresh, the app requests current usage information from the selected provider. iOS controls the actual execution schedule. Background refresh is not used for tracking, advertising, or analytics.

WIDGETS
The Home Screen and Lock Screen widgets only display the latest usage snapshots cached by the main app in the local App Group container group.com.studiofreesia.aium. The widget extension does not sign users in and does not independently contact GitHub or OpenAI.

EXTERNAL SERVICES
GitHub sign-in uses GitHub App Device Flow and read-only access to billing-plan usage. Codex sign-in uses a device authorization flow. AIUM then contacts GitHub or OpenAI directly from the device to retrieve the signed-in user's usage information. Credentials are stored in the iOS Keychain. AIUM has no developer-operated backend and includes no advertising or analytics SDKs.

If live sign-in is tested, the reviewer must use an account they are authorized to access. No shared review account is required because Demo Mode covers all reviewable UI and widget states.
```

## スクリーンショット

最高解像度の 6.9-inch iPhone 用 PNG を用意する。縦向きの対応サイズは `1260 x 2736`、`1290 x 2796`、`1320 x 2868` のいずれか。1〜10枚を登録できる。

推奨順:

1. Demo Mode のダッシュボード全体
2. GitHub Copilot の使用量カード
3. OpenAI Codex の使用量カード
4. 設定画面（Demo Mode により認証情報が表示されない状態）
5. ホーム画面の Medium Widget
6. ロック画面の Lock Screen Widget

撮影時の注意:

- 実アカウントのメールアドレス、ユーザー名、認証コード、トークンを含めない。
- Demo Mode を使い、サンプルであることが UI 上でも判別できる状態にする。
- iPhone の表示言語ごとに、日本語版と英語版をそれぞれ撮影する。
- App Store Connect へアップロード後、並び順と各ローカライゼーションへの割り当てを確認する。

起動済みの 6.9-inch iPhone Simulator が1台ある状態で、次のコマンドを実行するとデモモードのダッシュボードと設定画面を撮影できる。ステータスバーを固定し、生成画像が App Store Connect の対応ピクセルサイズであることも検証する。

```sh
scripts/capture-app-store-screenshots.sh ja
scripts/capture-app-store-screenshots.sh en
```

複数の Simulator が起動している場合は `SIMULATOR_UDID` を指定する。画像は `artifacts/app-store/screenshots/<language>/` に生成され、Git の管理対象には含めない。

## 実装監査メモ

- Privacy Manifest: `AIUM/PrivacyInfo.xcprivacy`
- Required Reason API: `UserDefaults`
- Approved reason: `CA92.1`（アプリ自身だけがアクセスできる設定値の読み書き）
- `NSPrivacyTracking`: `false`
- `ITSAppUsesNonExemptEncryption`: `false`

## 参照

- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Describing use of required reason API](https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api)
