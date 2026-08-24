# ねるわ Android

iOS版の主要体験をJetpack Composeへ移植したAndroidアプリです。

## 実装済み

- 19:00〜翌04:00の夜フローと、それ以外の朝フロー（設定で変更可能）
- 夜: 日記 → 睡眠学習 → PVT → 睡眠音声 → 睡眠タイマー
- 朝: 気分 → PVT → 朝テスト → 記録
- 朝のPVT・テストのスキップ、設定からのデモ起動
- 手入力と永続タイマーによる睡眠記録
- 点字・英単語カード、フォルダ、カード追加、CSV貼り付けインポート、TTS読み上げ
- 90秒PVTと1日・1週間・1ヶ月の結果グラフ
- 気分色・睡眠時間付き月間カレンダーと日付詳細
- みんなの睡眠と投稿画面、公開範囲設定
- GLBを直接表示する3Dねるるん、4段階の状態と殻ごとの揺れ
- 3Dモデル由来のアプリアイコンと問いかけ画像

データは `SharedPreferences` にJSONとしてローカル保存します。Android版の共有フィードは現在ローカルMVPで、Firebase同期とHealth Connectは次の統合作業で追加します。

## ビルド

必要環境:

- JDK 17
- Android SDK Platform 36
- Android SDK Build Tools 36.0.0

```bash
./gradlew :app:assembleDebug
```

Android Studioではこの `Android` ディレクトリをプロジェクトとして開きます。
