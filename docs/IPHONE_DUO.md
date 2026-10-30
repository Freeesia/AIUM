# iPhone Duo 対応

## ビルド環境

- Xcode 27.1 以降、iOS 27.1 SDK 以降でビルドします。
- 最低対応 OS は iOS 18.0 です。
- TestFlight ワークフローは `xcode-27` runner の Xcode 27.1 を指定します。

`xcode-27` は GitHub がプレビューとして提供している runner です。

`project.yml` の `xcodeVersion` はプロジェクト生成時の設定です。使用する SDK は実行時に選択されている Xcode によって決まるため、ローカルでも `xcodebuild -version` と `xcrun --sdk iphoneos --show-sdk-version` で確認してください。

## レイアウト

- ダッシュボードはセーフエリア内の実際の表示幅から、サービスを1列または2列に配置します。端末名、画面全体のサイズ、端末の向きによる判定は行いません。
- 列の最小幅は Dynamic Type に追従します。アクセシビリティの文字サイズでは1列にします。
- `AnyLayout` で列構成を切り替えます。画面モデル、スクロール領域、シートの表示状態は切り替えの外側で保持します。
- 利用状況カードは、横並びで収まらないときに縦配置へ切り替えます。リセット時刻と更新時刻も表示幅に合わせて折り返します。
- ナビゲーション、ツールバー、フォーム、シートは標準コンポーネントを使用し、システムの配置とセーフエリアに追従します。

## 動作確認

Xcode 27.1 以降の Device Hub で iPhone Duo を選び、デモモードのダッシュボードで次を確認します。通常の iPhone でも同じビルドを確認してください。

| 操作・状態 | 確認内容 |
| --- | --- |
| 閉じた状態で縦・横に回転 | カード、設定・更新ボタン、スクロール末尾まで表示できる |
| 開いた状態で縦・横に回転 | 十分な幅ではサービスが2列になり、各サービスの見出しとカードがまとまる |
| 起動中に開閉を繰り返す | 表示幅に追従し、取得済みデータや認証状態を維持する |
| 途中まで折りたたむ | 利用可能な表示領域に収まり、画面の狭さに応じて1列になる |
| Split View の左右に配置し、幅を変える | 非対称のセーフエリアに追従し、列数とカード配置が変わる |
| 文字サイズを最大まで上げる | 1列で表示され、残量・上限・時刻が読める |
| 設定シートを開いたまま開閉 | シート、表示設定、入力途中の上限値を維持する |
| リセット確認シートを開いたまま開閉 | 対象アカウントと確認状態を維持し、操作ボタンが表示領域に収まる |
| 日本語・英語、長いアカウント名 | 見出しと利用状況を確認できる |

SwiftUI Preview にも、狭いダッシュボード、広いダッシュボード、狭いカード、文字を拡大したカードを用意しています。

App Store 用の Duo スクリーンショットは、Device Hub で対象の表示状態にして実寸で保存してください。既存の `scripts/capture-app-store-screenshots.sh` は通常の iPhone 用の縦長サイズに変換するため、Duo の撮影には使用しません。

## 参照

- [Apple: Three steps to make your app shine on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [Apple: Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [GitHub Actions: Xcode 27 runner の搭載ソフトウェア](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
