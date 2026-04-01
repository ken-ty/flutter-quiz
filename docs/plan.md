# リアルタイムクイズシステム - 実装計画書

## 依存関係と実装順序

```
Phase 0 (基盤)
    └── Phase 1 (認証) ← 全機能の前提
            ├── Phase 2 (チャンク管理) ← 管理者アプリ単独で完結
            │       └── Phase 3 (セッション管理)
            │               └── Phase 4 (リアルタイム出題・回答) ← 核心機能
            │                       └── Phase 5 (結果表示・閲覧)
            └── Phase 6 (UI/UX) ← Phase 4,5 と並行可能
                    └── Phase 7 (デプロイ)
```

---

## Phase 0: プロジェクト基盤構築

**目的**: 2つの Flutter Web プロジェクトと Firebase 共通設定を作成し、ビルド・デプロイの骨格を確立する。

### ステップ 0-1: Flutter プロジェクト作成

1. `flutter create --platforms web admin` で管理者アプリを作成
2. `flutter create --platforms web client` で回答者アプリを作成
3. 両プロジェクトの `pubspec.yaml` に共通依存を追加:
   - `firebase_core`, `firebase_auth`, `cloud_firestore`
   - `flutter_riverpod` (状態管理)
   - `go_router` (ルーティング)
4. 管理者アプリのみに `qr_flutter` を追加

### ステップ 0-2: Firebase プロジェクト設定

1. Firebase プロジェクト作成（Firebase Console またはCLI）
2. `firebase init` で Firestore, Auth, Hosting を有効化
3. `firebase/` ディレクトリに `firestore.rules` と `firestore.indexes.json` を配置
4. Firebase Hosting をマルチサイト構成に設定:
   - `admin` サイト → `admin/build/web`
   - `client` サイト → `client/build/web`
5. `flutterfire configure` を両プロジェクトで実行し、`firebase_options.dart` を生成

### ステップ 0-3: プロジェクト構成の標準化

両アプリで以下のディレクトリ構造を採用する:

```
lib/
├── main.dart
├── app.dart                 # MaterialApp + Router 設定
├── firebase_options.dart    # 自動生成
├── models/                  # データモデル
├── repositories/            # Firestore CRUD 操作
├── providers/               # Riverpod プロバイダー
├── screens/                 # 画面ウィジェット
├── widgets/                 # 共通ウィジェット
└── router.dart              # GoRouter 定義
```

### ステップ 0-4: CI / Linting

1. `analysis_options.yaml` を両プロジェクトで統一
2. GitHub Actions で `flutter analyze` + `flutter test` を実行するワークフロー作成

**検証**: 両アプリが `flutter run -d chrome` で空画面として起動できること。

---

## Phase 1: 認証 (F1)

**目的**: 両アプリのログイン/登録フローを実装し、管理者判定ロジックを確立する。

### ステップ 1-1: Firestore セキュリティルール（初版）デプロイ

1. 仕様書記載のセキュリティルールを `firebase/firestore.rules` に記述
2. `firebase deploy --only firestore:rules` でデプロイ
3. Firebase Console で `admins` コレクションに管理者アカウントを手動登録

### ステップ 1-2: データモデル作成

- `User` モデル（uid, email, displayName, createdAt）
- `Admin` モデル（uid, email, name）

### ステップ 1-3: 認証リポジトリ

`AuthRepository` クラス:

- `signInWithEmail(email, password)` → `UserCredential`
- `signUp(email, password, displayName)` → `UserCredential` + Firestore `users` ドキュメント作成
- `signOut()`
- `currentUser` ストリーム

`AdminRepository` クラス:

- `isAdmin(uid)` → Firestore `admins/{uid}` の存在確認

### ステップ 1-4: Riverpod プロバイダー

- `authStateProvider` — Firebase Auth の `authStateChanges()` をストリームとして提供
- `currentUserProvider` — 認証状態から User 情報を取得
- 管理者アプリ用: `isAdminProvider` — ログイン後に管理者かどうか判定

### ステップ 1-5: 管理者アプリ - ログイン画面

1. メールアドレス + パスワード入力フォーム
2. ログイン後に `admins` コレクション確認。未登録なら即サインアウト + エラー表示
3. GoRouter のリダイレクトで未認証時は `/login` に強制遷移

### ステップ 1-6: 回答者アプリ - 新規登録 / ログイン画面

1. 新規登録画面: メールアドレス + ユーザー名 + パスワード
2. ログイン画面: メールアドレス + パスワード
3. 登録成功時に Firestore `users/{uid}` ドキュメントを作成
4. GoRouter のリダイレクトで未認証時は `/login` に強制遷移

**テスト**: AuthRepository のユニットテスト、isAdmin の判定ロジックテスト、ログインフォームのバリデーション

---

## Phase 2: クイズチャンク管理 (F2)

**目的**: 管理者がクイズ問題セットを作成・編集・削除できるようにする。

### ステップ 2-1: データモデル

- `QuizChunk` モデル（chunkId, title, description, createdBy, createdAt, questions）
- `Question` モデル（text, choices: List\<String\>(4), correctIndex: int）

### ステップ 2-2: リポジトリ

`QuizChunkRepository`:

- `create(chunk)` / `update(chunkId, chunk)` / `delete(chunkId)`
- `getAll()` → ストリーム（リアルタイム更新）
- `getById(chunkId)` → 単一取得

### ステップ 2-3: 管理者アプリ画面

1. **ホーム画面**: チャンク一覧 + 新規作成 FAB
2. **チャンク作成/編集画面**: タイトル、説明、問題の動的追加・削除、各問題の4選択肢 + 正解指定

**テスト**: QuizChunkRepository のユニットテスト、チャンク作成画面のウィジェットテスト

---

## Phase 3: セッション管理 (F3)

**目的**: 管理者がチャンクからセッションを作成し、参加用 QR/URL を生成できるようにする。

### ステップ 3-1: データモデル

- `Session` モデル（sessionId, chunkId, status, currentQuestionIndex, createdBy, createdAt, participantCount）
- `SessionStatus` enum（waiting, active, showingResult, finished）

### ステップ 3-2: リポジトリ

`SessionRepository`:

- `create(chunkId)` → セッション作成（status: waiting）
- `updateStatus(sessionId, status, currentQuestionIndex?)` → 状態更新
- `getSession(sessionId)` → ストリーム
- `getSessions()` → 全セッション一覧

### ステップ 3-3: QR/URL 生成

1. セッション作成時に URL 生成: `https://<client-host>/session/{sessionId}`
2. `qr_flutter` で QR コードウィジェットを生成
3. ホーム画面に QR コード + URL を常時表示

### ステップ 3-4: 管理者アプリ画面

1. チャンク一覧から「セッション開始」→ セッション作成 → 実行画面へ遷移
2. **待機画面**: QR コード + URL + 参加者数 + 「開始」ボタン

**テスト**: SessionRepository のユニットテスト、セッション状態遷移のロジックテスト

---

## Phase 4: リアルタイム出題・回答 (F4)

**目的**: セッションの核心機能。管理者が出題を進行し、回答者がリアルタイムで回答する。

### ステップ 4-1: データモデル

- `Answer` モデル（userId, questionIndex, selectedIndex, isCorrect, answeredAt）
- `QuestionResult` モデル（totalAnswers, choiceCounts: List\<int\>(4), correctIndex）

### ステップ 4-2: リポジトリ

`AnswerRepository`:

- `submitAnswer(sessionId, userId, questionIndex, selectedIndex)` → 回答書き込み
- `getMyAnswers(sessionId, userId)` → 自分の回答一覧
- `getAnswersByQuestion(sessionId, questionIndex)` → 管理者用集計

`ResultRepository`:

- `writeResult(sessionId, questionIndex, result)` → 集計結果書き込み

### ステップ 4-3: 管理者アプリ - セッション実行画面

1. **出題画面**: 問題文 + 4択表示 + 「結果表示」ボタン
2. 「結果表示」押下時: `answers` を集計 → `results` に書き込み → status を `showing_result` に
3. **結果画面**: 正解 + 各選択肢の回答割合
4. 「次へ」→ `currentQuestionIndex` + 1、status を `active` に
5. 最後の問題後「終了」→ status を `finished` に

### ステップ 4-4: 回答者アプリ - セッション参加画面

1. URL から `sessionId` を取得
2. **待機画面**: status が `waiting` の間。参加者数インクリメント。
3. **回答画面**: status が `active` に変わると自動遷移。4択選択 → 回答送信。
4. **結果画面**: status が `showing_result` で正解 + 全体回答割合を表示。
5. **最終結果画面**: status が `finished` で自分のスコア表示。

**テスト**: 回答送信・集計ロジックのユニットテスト、セッション状態遷移の統合テスト

---

## Phase 5: 結果表示・閲覧 (F5, F6)

**目的**: リアルタイム結果表示と後日の結果閲覧機能。

### ステップ 5-1: 管理者アプリ - 最終結果画面

- 全問終了後の得点分布表示（満点: X人, 0点: Y人, ...）
- `answers` サブコレクションから全ユーザーの全回答を集計

### ステップ 5-2: 回答者アプリ - 最終結果画面

- 自分のスコア: X/Y問正解
- 各問題の正誤表示

### ステップ 5-3: 管理者アプリ - セッション結果画面（後日閲覧）

- ホーム画面にセッション履歴一覧を追加
- セッション選択 → ユーザーごとの回答・正誤一覧テーブル

### ステップ 5-4: 回答者アプリ - マイページ

- 過去のセッション一覧
- セッション選択 → 問題ごとの正誤・復習画面

**テスト**: 得点分布計算ロジックのユニットテスト、マイページのウィジェットテスト

---

## Phase 6: UI/UX 仕上げ・レスポンシブ対応

### ステップ 6-1: レスポンシブ対応

- PC / スマートフォン表示の切り替え
- 回答画面の4択ボタンはスマホでも押しやすいサイズに
- 管理者アプリは PC 優先レイアウト

### ステップ 6-2: パフォーマンス検証

- 100人同時回答のシミュレーション
- 回答送信から結果反映まで2秒以内の確認
- Firestore インデックス最適化

### ステップ 6-3: エラーハンドリング

- ネットワークエラー時のリトライ / 通知
- セッション途中離脱からの復帰
- 重複回答防止（UI + Firestore ドキュメントID制約）

---

## Phase 7: デプロイ

### ステップ 7-1: Firebase Hosting 設定

1. `firebase.json` でマルチサイト設定
2. `flutter build web --release` を両アプリで実行
3. `firebase deploy --only hosting` でデプロイ

### ステップ 7-2: 本番動作確認

1. 管理者アカウントでログイン → チャンク作成 → セッション開始
2. QR コードから回答者アプリにアクセス → 登録 → 回答
3. リアルタイム同期の確認
4. 複数端末での同時テスト

---

## 設計上の重要な判断事項

### 1. correctIndex の秘匿

`sessions` ドキュメントには `correctIndex` を含めない。セッション作成時にチャンクの問題データ（問題文 + 選択肢のみ）を `sessions` にコピーする。正解情報は管理者が「結果表示」に遷移した時点で `results/{questionIndex}` に書き込む。これにより回答者が DevTools で正解を事前に見ることを防ぐ。

### 2. 回答集計方式

管理者が「結果表示」操作時にクライアント（管理者アプリ）側で `answers` を読み取り集計して `results` に書き込む。100人規模なら十分実用的。

### 3. 重複回答防止

ドキュメントID を `{userId}_{questionIndex}` とすることで Firestore レベルで一意性を保証。

### 4. 共有コードについて

`admin` と `client` は独立した Flutter プロジェクト。初期段階では各アプリにコードをコピーで対応し、将来的に `shared/` パッケージとして切り出すことを検討する。

---

## テスト戦略

| レベル | 対象 | ツール |
|--------|------|--------|
| ユニットテスト | モデル、リポジトリ、プロバイダー | `flutter_test`, `mockito`, `fake_cloud_firestore` |
| ウィジェットテスト | 各画面の表示・操作 | `flutter_test`, `ProviderScope.overrides` |
| 統合テスト | セッションフロー全体 | Firebase エミュレーター + `integration_test` |
| 手動テスト | リアルタイム同期、複数端末 | 実機 / ブラウザ複数タブ |
