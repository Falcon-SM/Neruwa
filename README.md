# ねるわ iOS

「夜に睡眠を記録し、朝の状態と一緒に振り返る」ための SwiftUI アプリです。Web PoC の中心フローを引き継ぎつつ、Apple純正アプリと同じナビゲーション、リスト、フォーム、システムカラーを使うネイティブ構成にしています。

## MVP の範囲

- 睡眠タイマー（開始日時を保存し、アプリ再起動後も復元）
- 就寝・起床日時の手入力
- 目標睡眠時間
- 朝の気分 4 段階とコメント
- 直近 7 日の集計と履歴
- HealthKit から昨晩の睡眠を読み込み
- ローカル優先保存と、ログイン時の Firestore 同期
- Google / Firebase ログインとローカルのゲストモード
- 就寝前の点字学習、睡眠中の読み上げ、朝の確認テスト
- 学習カード・再生設定・テスト結果のアカウント別ローカル保存

TMT と友達共有は、Web PoC で検証中の次段階の機能です。

## 必要な環境

- macOS
- Xcode 26.6 以上
- iOS 26.5 SDK
- Firebase プロジェクト（Google ログインとクラウド同期を使う場合）

このリポジトリには Swift Package の解決情報が含まれています。初回に Xcode が Firebase と Google Sign-In の依存関係を取得します。

## 起動

1. `Sleeper.xcodeproj` を Xcode で開く。
2. Signing & Capabilities で自分の Team を確認する。
3. Google ログインを使う場合は、Firebase に登録した Bundle ID と `GoogleService-Info.plist` を一致させる。
4. HealthKit の動作確認は、睡眠データがある実機で行う。
5. `Sleeper` scheme を実行する。

Firebase を設定していない環境でも「ゲストとして試す」からローカル機能を確認できます。

睡眠学習では、Web PoC の大容量音声ファイルをコピーせず、iOS の日本語音声合成を利用します。「睡眠学習」タブでカードを選び、間隔・時間・音量を設定してから再生してください。睡眠タイマーとの自動連携を有効にすると、計測開始・終了に合わせて再生を制御します。長時間のポーリングは行わず、端末負荷を抑えるため1回の再生キューは最大120発話です。

## UI 方針

- 画面上の情報は `List`、`Form`、`Section`、`LabeledContent` で整理
- タブバー、ナビゲーション、標準ボタンの Liquid Glass はOSに任せ、コンテンツ面へ独自のGlassを重ねない
- 固定の夜空背景や独自タイルを使わず、システム背景とセマンティックカラーでライト・ダーク表示へ自動対応
- SF Symbols、Dynamic Type、標準スワイプ操作を利用し、ヘルスケアや時計と同じ操作感を優先
- iPhoneではタブバー、広い画面ではシステムのサイドバーへ適応

## 軽量化

- 長い履歴とカード一覧はシステムの `List` で必要な行だけ生成
- 独自のGlass、ぼかし、Canvas背景をコンテンツから除去
- 睡眠時計の1秒更新は、計測中かつ画面が表示され、アプリが前面にある間だけ実行
- 各画面の縦スクロールをシステムのコンテナ1つに統一
- Firestore同期は取得済みスナップショットとの差分だけを最大400件ずつ書き込み
- 未使用だった `GoogleSignInSwift` 製品のリンクを削除

CLI で確認する場合、Command Line Tools ではなく Xcode 本体を指定します。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Sleeper.xcodeproj \
  -scheme Sleeper -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## データ設計

Web PoC の「日付ごとに 1 件」ではなく、複数セッションと夜跨ぎを扱える `SleepSession` を使います。

```text
SleepSession
├─ id
├─ startDate / endDate
├─ targetMinutes
├─ source: timer / manual / healthKit
├─ mood / note
├─ sleep stages（HealthKit の場合）
└─ createdAt / updatedAt
```

ローカルを先に更新し、ゲストと各 Firebase UID の保存領域を端末内でも分離します。認証済みユーザーだけ次の Firestore パスへ同期します。

```text
/users/{uid}/sleepSessions/{sessionId}
```

睡眠学習データは現在端末内に保存し、ゲストと各 Firebase UID の領域を分離しています。学習内容を意図せずクラウドへ送らないため、Firestore 同期の対象は睡眠記録だけです。

最低限、Firestore Security Rules では本人の UID だけに読み書きを許可してください。ルールを設定・デプロイするまではクラウド同期が失敗してもローカル記録は保持されます。

```text
match /users/{userId}/sleepSessions/{sessionId} {
  allow read, write: if request.auth != null
                     && request.auth.uid == userId;
}
```

## プライバシー

- HealthKit は睡眠分析の読み取りだけを要求します。
- HealthKit 由来データを Firestore へ同期する場合は、利用目的と削除方法を公開前に明示してください。
- Web PoC の動画・音声にはライセンス表記がないため、このアプリにはコピーしていません。
- 睡眠中の読み上げを画面ロック後も継続するため、Background Modes の Audio を使用します。音量を小さくして短時間から試してください。
- 配布前に Sign in with Apple の要否、Firestore Rules、アカウント削除、データ export / delete を確認してください。

## Web PoC からの移植方針

再利用するのは画面フロー、色、記録項目、集計ロジックです。Next.js、Local Storage、Web Notification、HTML Audio のコードは SwiftUI、ローカル永続化、UserNotifications、AVFoundation へ段階的に書き直します。
