# AIUM — AI Usage Monitor

AIUM は、GitHub Copilot や OpenAI Codex の利用状況を確認するための個人用 iOS アプリです。

アプリ本体で利用状況を取得し、ホーム画面やロック画面のウィジェットからすぐ確認できるようにします。主な用途は、利用上限までの残量やリセット時刻の目安を日常的に把握することです。

## 重要な注意

AIUM には、OpenAI / Codex の非公開・未文書化 API を利用する実装が含まれています。

- 非公開 API は予告なく変更・停止される可能性があります。
- 現時点では個人利用・検証用途を前提としています。
- 公式の利用状況 API が提供されるまで、公開アプリとして配布しないでください。
- GitHub 側は GitHub App Device Flow と GitHub Billing API を利用します。現在は個人アカウントへ直接課金される Copilot 使用量を対象とします。
- 表示される利用状況は API レスポンスをもとにした目安です。請求・契約・残量の正式な情報は各サービスの公式画面で確認してください。

## 主な機能

- GitHub Copilot の利用状況表示
- OpenAI Codex の利用状況表示
- ホーム画面ウィジェット
- ロック画面ウィジェット
- GitHub / Codex のログイン状態管理
- 利用上限値の手動補正
- アプリとウィジェット間の利用状況キャッシュ共有

## 実装方針

AIUM は、アプリ本体で認証・取得・保存を行い、ウィジェットは保存済みの利用状況を表示する構成です。

- UI は SwiftUI を中心に実装します。
- ウィジェットは WidgetKit を利用します。
- 認証トークンは Keychain に保存します。
- アプリとウィジェットの共有データは App Groups を利用します。
- サービスごとの取得処理は provider として分離し、API 変更時に差し替えやすい構成にします。

## セットアップ

### 1. XcodeGen をインストールする

```sh
brew install xcodegen
```

### 2. Xcode プロジェクトを生成する

```sh
xcodegen generate
```

生成された `AIUM.xcodeproj` を Xcode で開き、`AIUM` アプリターゲットを実行します。`AIUM.xcodeproj` は生成物のため、リポジトリにはコミットしません。

### 3. Signing & Capabilities を設定する

`AIUM` と `AIUMWidget` の両方で、以下を設定します。

- Team
- Bundle Identifier
- App Groups

App Groups の識別子は、アプリ側とウィジェット側で同じものを指定してください。コード内で App Group 識別子を参照している場合は、自分の設定に合わせて変更します。

### 4. GitHub App を設定する

GitHub App を作成し、Device Flow を有効にします。Account permissions の `Plan` を `Read-only` に設定してください。

作成した Client ID は、Swift ファイルや git 管理ファイルに直接書かず、ローカル用 xcconfig から AIUM ターゲットの build setting `GITHUB_OAUTH_CLIENT_ID` に渡します。

`Config/AIUM.xcconfig` には placeholder を置き、`Config/AIUM.local.xcconfig` を optional include します。`Config/AIUM.local.xcconfig` は `.gitignore` 対象です。

ローカルで GitHub ログインを使う場合は、次のファイルを作成してから `xcodegen generate` を実行します。

```xcconfig
// Config/AIUM.local.xcconfig
GITHUB_OAUTH_CLIENT_ID = your_client_id
```

この値が `YOUR_GITHUB_CLIENT_ID` placeholder または空値の場合、アプリは GitHub ログイン処理を開始せず、設定画面にエラーを表示します。

GitHub Appの権限はOAuth scopeではなくApp設定で決まります。Device Flowで取得したGitHub App user access tokenとrefresh tokenはKeychainに保存し、access tokenの期限切れ前に自動更新します。

設定画面では認証コードをコピーしてアプリ内Safariを開きます。GitHubで承認が完了するとブラウザシートは自動で閉じます。

利用状況取得はGitHub Billing APIの`2026-03-10` versionに依存します。OrganizationやEnterpriseで管理・課金されているCopilot seatは個人向けendpointの対象外です。

### 5. Codex 認証を設定する

Codex 側の認証・利用状況取得は非公開 API に依存します。現在の実装では、Codex アプリの login client ID と ChatGPT backend の Codex usage endpoint を利用します。

`Config/AIUM.xcconfig` には現在確認できている `CODEX_OAUTH_CLIENT_ID` を設定しています。この値は公開クライアントIDであり secret ではありませんが、OpenAI 側で変更される可能性があります。変更が必要な場合は、GitHub と同じく `Config/AIUM.local.xcconfig` で上書きしてから `xcodegen generate` を実行します。

```xcconfig
// Config/AIUM.local.xcconfig
CODEX_OAUTH_CLIENT_ID = app_xxx
```

この値が `YOUR_CODEX_CLIENT_ID` placeholder または空値の場合、アプリは Codex ログイン処理を開始せず、設定画面にエラーを表示します。

利用状況取得は `https://chatgpt.com/backend-api/wham/usage` を呼び出し、保存済みの `accountId` がある場合は `ChatGPT-Account-Id` ヘッダーに付与します。認証トークンから取得できた `accountId` / `email` は Keychain 内の Codex token bundle に保存し、設定画面と使用量カードの接続先表示に反映します。

この部分は最も壊れやすいため、公開アプリ向けの安定した仕様として扱わないでください。

### 6. 実行する

アプリを起動し、各サービスにログインして利用状況を更新します。その後、iOS のウィジェット追加画面から AIUM のウィジェットを追加します。

## 使い方

1. アプリを起動する
2. GitHub または Codex にログインする
3. 利用状況を更新する
4. 必要に応じて利用上限値を手動で補正する
5. ホーム画面またはロック画面にウィジェットを追加する

ウィジェットは iOS の更新スケジュールに従って再描画されます。リアルタイム更新を保証するものではありません。

## データの扱い

AIUM は、利用状況の表示に必要な情報を端末内に保存します。

- 認証トークン: Keychain
- 利用状況キャッシュ: App Group 共有領域
- 表示設定・手動補正値: 端末内ストレージ

外部サーバーへの独自送信やクラウド同期は前提としていません。

## 既知の制限

- 非公開 API や preview API に依存する部分は、サービス側の変更で突然動作しなくなる可能性があります。
- 取得できる利用状況は、アカウント種別・契約プラン・サービス側の状態によって変わる可能性があります。
- ウィジェットの更新タイミングは iOS によって制御されます。
- 公開配布する場合は、公式 API への置き換え、利用規約の確認、プライバシーポリシーの整備が必要です。

## ライセンス

このリポジトリのライセンスに従います。
