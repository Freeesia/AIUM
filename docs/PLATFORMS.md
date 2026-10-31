# iPad・macOS 対応

## 構成

| 環境 | scheme | 最低 OS | ウィジェット |
| --- | --- | --- | --- |
| iPhone・iPad | `AIUM` | iOS / iPadOS 18.0 | ホーム画面・ロック画面 |
| Mac | `AIUMMac` | macOS 15.0 | デスクトップ・通知センターの small / medium |

iOS のアプリ・ウィジェット・テストは端末ファミリー `1,2` に対応します。iPad は縦・横・上下反転を許可し、全画面表示を強制しません。ダッシュボードは表示幅と文字サイズに応じて1列・2列を切り替えます。

Mac は共通の SwiftUI 画面・認証・データモデルを使うネイティブアプリです。アプリ全体でダッシュボードのモデルを共有し、設定ウィンドウでの変更を反映します。`⌘,` は設定、`⌘R` は更新です。認証コードは `NSPasteboard` にコピーし、既定のブラウザで認証先を開きます。

iOS の `BGTaskScheduler` は Mac には組み込みません。Mac の定期更新はアプリプロセスの実行中に行います。ウィジェットはネットワーク認証を行わず、同じ Mac の App Group に保存されたスナップショットを表示します。iPhone・iPad・Mac 間でのクラウド同期はありません。

## Mac の署名

`AIUMMac` と `AIUMWidgetMac` は App Sandbox と Hardened Runtime を有効にします。アプリ本体だけが外向きのネットワーク接続を許可します。

両ターゲットで `group.com.studiofreesia.aium` の App Group を許可する、macOS 用の開発プロファイルが必要です。iOS 用のプロファイルは流用できません。Keychain は macOS でも保護属性を適用するため、すべての操作で `kSecUseDataProtectionKeychain` を指定します。

Xcode の Signing & Capabilities で Team、各 Bundle Identifier、App Groups を設定して `AIUMMac` を実行してください。既存の開発者アカウントを使って自動署名を準備する場合、プロファイルや App ID の設定が変更されることがあります。

画面のみを署名なしで確認する場合:

```sh
AIUM_MAC_CODE_SIGNING_ALLOWED=NO ./script/build_and_run.sh --verify --demo
```

ビルド先は既定で `build/macos` です。`AIUM_MAC_DERIVED_DATA` と `AIUM_MAC_CONFIGURATION` で変更できます。スクリプトはそのビルド先の Mac アプリだけを終了して起動し直します。

## テスト

```sh
xcodegen generate
xcodebuild test -project AIUM.xcodeproj -scheme AIUM \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
xcodebuild test -project AIUM.xcodeproj -scheme AIUMMac \
  -destination 'platform=macOS'
```

Mac で `CODE_SIGNING_ALLOWED=NO` を付けた場合、署名済みホストを必要とする Keychain 保護属性と App Group 共有読み出しの2件は明示的にスキップします。署名済みホストではスキップせず、設定不足をテスト失敗として扱います。CI は iPad の全テストと、署名なし Mac の共通機能テストを実行します。macOS の署名付き検証と配布設定は CI の対象外です。

| 確認対象 | 操作 |
| --- | --- |
| iPad | 縦・横表示と、ウィンドウ幅変更時の1列・2列切替を確認する |
| iPad の設定 | シート内で表示項目や更新間隔を変更し、閉じて反映を確認する |
| Mac | ウィンドウを狭くし、カードと時刻が収まることを確認する |
| Mac の設定 | `⌘,` で開き、表示項目・デモモード・更新間隔の反映を確認する |
| 認証 | デモモードを解除し、コードのコピー・ブラウザ認証・再起動後のログイン保持を確認する |
| ウィジェット | 署名済みアプリで利用状況を取得し、small / medium に同じ残量が表示されることを確認する |
| リセット | 署名済みアプリで確認シートを開き、対象アカウント・有効期限・操作ボタンが収まることを確認する。実際の消費操作は検証に含めない |

## 参照

- [Apple: Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [Apple: kSecUseDataProtectionKeychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)
