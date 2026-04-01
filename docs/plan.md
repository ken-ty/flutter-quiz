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

**目的**: 2つの Flutter Web プロジェクトと Firebase 共通設定を作成し、MVVM + 3層アーキテクチャの骨格を確立する。

### ステップ 0-1: ローカル環境セットアップ（必須前提条件）

全ての Firebase タスクの前に完了すること。

1. Node.js >= v20 の確認: `node --version`
2. Firebase CLI の確認: `npx -y firebase-tools@latest --version`
3. Firebase 認証: `npx -y firebase-tools@latest login`
4. Firebase プロジェクト作成: `npx -y firebase-tools@latest projects:create`
5. Web アプリ登録（2つ）:

   ```bash
   npx -y firebase-tools@latest apps:create web admin-app
   npx -y firebase-tools@latest apps:create web client-app
   ```

6. SDK 設定取得: `npx -y firebase-tools@latest apps:sdkconfig <APP_ID>`

### ステップ 0-2: Flutter プロジェクト作成

1. `flutter create --platforms web admin` で管理者アプリを作成
2. `flutter create --platforms web client` で回答者アプリを作成
3. 両プロジェクトの `pubspec.yaml` に共通依存を追加:
   - `firebase_core`, `firebase_auth`, `cloud_firestore`
   - `flutter_riverpod` (状態管理)
   - `go_router` (ルーティング)
4. 管理者アプリのみに `qr_flutter` を追加

### ステップ 0-3: Firebase プロジェクト設定

1. プロジェクトルートに `firebase.json` を作成（完全な構成）:

   ```json
   {
     "firestore": {
       "rules": "firebase/firestore.rules",
       "indexes": "firebase/firestore.indexes.json"
     },
     "auth": {
       "providers": {
         "emailPassword": true
       }
     },
     "hosting": [
       {
         "target": "admin",
         "public": "admin/build/web",
         "rewrites": [{ "source": "**", "destination": "/index.html" }]
       },
       {
         "target": "client",
         "public": "client/build/web",
         "rewrites": [{ "source": "**", "destination": "/index.html" }]
       }
     ],
     "emulators": {
       "auth": { "port": 9099 },
       "firestore": { "port": 8080 },
       "hosting": { "port": 5000 }
     }
   }
   ```

   - `rewrites` の `**` → `/index.html` は Flutter Web（SPA）に必須
   - `emulators` セクションで開発用エミュレーターを定義

2. `firebase/firestore.rules` に**全拒否の初期ルール**を作成:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if false;
       }
     }
   }
   ```

3. `firebase/firestore.indexes.json` を空で作成:

   ```json
   {
     "indexes": [],
     "fieldOverrides": []
   }
   ```

4. 初期ルールをデプロイ:

   ```bash
   npx -y firebase-tools@latest deploy --only firestore
   ```

5. Hosting ターゲットを設定:

   ```bash
   npx -y firebase-tools@latest target:apply hosting admin <admin-site-id>
   npx -y firebase-tools@latest target:apply hosting client <client-site-id>
   ```

6. `flutterfire configure` を両プロジェクトで実行し、`firebase_options.dart` を生成

### ステップ 0-4: エミュレーター設定

開発時は本番データを汚さないようエミュレーターを使用する。

1. エミュレーター起動: `npx -y firebase-tools@latest emulators:start --only firestore,auth`
2. `main.dart` の初期化順序（**順序厳守**）:

   ```dart
   // 1. Firebase 初期化
   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
   // 2. エミュレーター接続（開発環境のみ、初期化直後・他の操作の前に）
   if (kDebugMode) {
     FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
     FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
   }
   // 3. アプリ起動
   runApp(const ProviderScope(child: App()));
   ```

### ステップ 0-5: MVVM + 3層アーキテクチャの構成

両アプリで以下のディレクトリ構造を採用する:

```
lib/
├── main.dart
├── app.dart                 # MaterialApp + ProviderScope + Router 設定
├── firebase_options.dart    # 自動生成
├── models/                  # イミュータブルなデータモデル
├── services/                # Firestore/Auth API ラッパー（ステートレス）
├── repositories/            # 単一のデータソース、Result<T> でエラー返却
├── view_models/             # Riverpod Notifier / AsyncNotifier
├── views/                   # 画面ウィジェット（ロジックなし、SafeArea 使用）
├── widgets/                 # 共通ウィジェット
└── router.dart              # GoRouter 定義
```

アーキテクチャ原則（spec 参照）:

- データフロー: Data層 → ViewModel → View（単方向）
- イベントフロー: View → ViewModel → Repository（単方向）
- View にロジックを書かない。トップレベル画面に `SafeArea` を使用
- Service はステートレス（例外を投げる可能性あり）
- Repository は Service をラップし、`Result<T>`（Ok/Error）で返却
- ViewModel（AsyncNotifier）は `Result<T>` を `AsyncValue` に変換
- View は `AsyncValue.when()` で loading / error / data を表示
- モデルはイミュータブル

エラーハンドリングのデータフロー:

```
Service → (例外を投げる可能性)
  ↓
Repository → try-catch で Result<T> にラップして返す
  ↓
ViewModel (AsyncNotifier) → Result<T> を AsyncValue に変換
  ↓
View → AsyncValue.when() で表示切り替え
```

### ステップ 0-6: GoRouter 初期設定

管理者アプリ:

| パス | 画面 | 認証 |
|------|------|------|
| `/login` | ログイン | 不要 |
| `/` | ホーム（チャンク一覧） | 管理者 |
| `/chunks/new` | チャンク作成 | 管理者 |
| `/chunks/:chunkId/edit` | チャンク編集 | 管理者 |
| `/sessions/:sessionId` | セッション実行 | 管理者 |
| `/sessions/:sessionId/results` | セッション結果（後日閲覧） | 管理者 |

回答者アプリ:

| パス | 画面 | 認証 |
|------|------|------|
| `/login` | ログイン | 不要 |
| `/register` | 新規登録 | 不要 |
| `/session/:sessionId` | セッション参加（待機〜最終結果） | 要ログイン |
| `/mypage` | マイページ（過去の結果一覧） | 要ログイン |
| `/mypage/:sessionId` | 過去の結果詳細 | 要ログイン |

- 未認証時は `/login` にリダイレクト（GoRouter の `redirect` で制御）
- 管理者アプリはログイン後に `admins` コレクション確認、非管理者は即サインアウト

### ステップ 0-7: CI / Linting

1. `analysis_options.yaml` を両プロジェクトで統一
2. GitHub Actions で `flutter analyze` + `flutter test` を実行するワークフロー作成

**検証**: 両アプリが `flutter run -d chrome` で空画面として起動できること。

---

## Phase 1: 認証 (F1)

**目的**: 両アプリのログイン/登録フローを実装し、管理者判定ロジックを確立する。

### ステップ 1-1: Firestore セキュリティルール（段階的開放）

Phase 0 の全拒否ルールから、認証に必要な部分のみ開放する。

1. `firebase/firestore.rules` に `admins` と `users` コレクションのルールを追加（Validator Function Pattern）
2. ヘルパー関数を定義: `isAuthenticated()`, `isAdmin()`, `isOwner()`, `immutableFieldsUnchanged()`
3. Devil's Advocate テスト（デプロイ前に確認）:
   - 未認証でドキュメントを読めないか？
   - 他ユーザーの `users/{uid}` にアクセスできないか？
   - `email`, `createdAt`（immutable）を書き換えられないか？
   - 1MB 文字列を書き込めないか？（サイズバリデーション確認）
   - 非管理者が `admins` コレクションを読めないか？
4. ドライランで構文確認:

   ```bash
   npx -y firebase-tools@latest deploy --only firestore:rules --dry-run
   ```

5. デプロイ: `npx -y firebase-tools@latest deploy --only firestore:rules`
6. Firebase Console で `admins` コレクションに管理者アカウントを手動登録

### ステップ 1-2: データモデル作成

- `User` モデル（uid, email, displayName, createdAt） — イミュータブル
- `Admin` モデル（uid, email, name） — イミュータブル

### ステップ 1-3: Service 層

`AuthService` クラス（ステートレス、Firebase Auth の薄いラッパー）:

- `signInWithEmail(email, password)` → `UserCredential`（例外を投げる可能性）
- `createUser(email, password)` → `UserCredential`
- `signOut()`
- `authStateChanges()` → `Stream<User?>`

`FirestoreService` クラス（ステートレス、Firestore API の薄いラッパー）:

- `getDocument(path)` / `setDocument(path, data)` / `documentStream(path)` etc.

### ステップ 1-4: Repository 層

`AuthRepository` クラス（Service をラップし `Result<T>` で返却）:

- `signInWithEmail(email, password)` → `Result<UserCredential>`
- `signUp(email, password, displayName)` → `Result<void>`: Auth 作成 + Firestore `users/{uid}` ドキュメント作成
- `signOut()` → `Result<void>`
- `authStateChanges()` → `Stream<User?>`（ストリームはそのまま公開）

`AdminRepository` クラス:

- `isAdmin(uid)` → `Result<bool>`: Firestore `admins/{uid}` の存在確認

### ステップ 1-5: ViewModel 層（Riverpod プロバイダー）

- `authStateProvider` — `StreamProvider`: `authStateChanges()` をストリームとして提供
- `currentUserProvider` — 認証状態から User 情報を取得
- 管理者アプリ用: `isAdminProvider` — `FutureProvider`: ログイン後に管理者かどうか判定

### ステップ 1-6: View 層 — 管理者アプリ - ログイン画面

1. メールアドレス + パスワード入力フォーム（フォーム入力はエフェメラル状態）
2. ログイン後に `admins` コレクション確認。未登録なら即サインアウト + エラー表示
3. エラー時は `AsyncValue.when()` でエラー表示

### ステップ 1-7: View 層 — 回答者アプリ - 新規登録 / ログイン画面

1. 新規登録画面: メールアドレス（学校指定）+ ユーザー名 + パスワード
2. ログイン画面: メールアドレス + パスワード
3. 登録成功時に Firestore `users/{uid}` ドキュメントを作成

**テスト**:

- Repository 層: **Fake** Service でユニットテスト（Fake 推奨、Mock は補助）
- ViewModel 層: `ProviderContainer` + Fake Repository で独立テスト
- View 層: ウィジェットテスト（`ProviderScope.overrides` + Fake でフォームバリデーション確認）
- Service 層: ステートレスな薄いラッパーのため、統合テストでカバー

---

## Phase 2: クイズチャンク管理 (F2)

**目的**: 管理者がクイズ問題セットを作成・編集・削除できるようにする。

### ステップ 2-0: セキュリティルール追加

`quizChunks` コレクションのルールを `firestore.rules` に追加しデプロイ。

### ステップ 2-1: データモデル

- `QuizChunk` モデル（chunkId, title, description, createdBy, createdAt, questions） — イミュータブル
- `Question` モデル（text, choices: List\<String\>(4), correctIndex: int） — イミュータブル

### ステップ 2-2: Repository

`QuizChunkRepository`（Service 経由で Firestore にアクセス、`Result<T>` で返却）:

- `create(chunk)` → `Result<String>` (chunkId) / `update(chunkId, chunk)` → `Result<void>` / `delete(chunkId)` → `Result<void>`
- `watchAll()` → `Stream`（リアルタイム更新）
- `getById(chunkId)` → `Result<QuizChunk>`

### ステップ 2-3: ViewModel

- `quizChunksProvider` — `StreamProvider`: 全チャンクのリアルタイムストリーム
- `quizChunkProvider(chunkId)` — `FutureProvider.family`: 個別チャンク取得
- `chunkFormNotifier` — `AsyncNotifier`: 作成/編集フォームの送信処理

### ステップ 2-4: View — 管理者アプリ画面

1. **ホーム画面** (`/`): チャンク一覧 + 新規作成 FAB
   - `AsyncValue.when()` で loading / error / data を切り替え
2. **チャンク作成/編集画面** (`/chunks/new`, `/chunks/:chunkId/edit`):
   - タイトル、説明、問題の動的追加・削除、各問題の4選択肢 + 正解指定
   - フォーム入力はエフェメラル状態（`TextEditingController`）

**テスト**: Repository のユニットテスト（Fake Service）、チャンク作成画面のウィジェットテスト

---

## Phase 3: セッション管理 (F3)

**目的**: 管理者がチャンクからセッションを作成し、参加用 QR/URL を生成できるようにする。

### ステップ 3-0: セキュリティルール追加

`sessions` コレクションと `participants` サブコレクションのルールを追加しデプロイ。

### ステップ 3-1: データモデル

- `Session` モデル — イミュータブル
  - sessionId, chunkId, status, currentQuestionIndex, createdBy, createdAt
  - questions: List\<SessionQuestion\>（correctIndex を除外した問題データ）
- `SessionStatus` enum（waiting, active, showingResult, finished）
- `SessionQuestion` モデル（text, choices）— correctIndex なし

### ステップ 3-2: Repository

`SessionRepository`（Service 経由、`Result<T>` で返却）:

- `create(chunkId)` → `Result<String>`: チャンクから問題データコピー（**correctIndex 除外**）、status: waiting で作成
- `updateStatus(sessionId, newStatus, currentQuestionIndex?)` → `Result<void>`: **状態遷移バリデーション付き**
- `watchSession(sessionId)` → `Stream<Session>`（リアルタイムリスナー）
- `watchSessions()` → 全セッション一覧ストリーム

状態遷移バリデーション（Repository 内で実施）:

```
waiting       → active のみ許可
active        → showing_result のみ許可
showing_result → active（次の問題）or finished（最終問題後）のみ許可
finished      → 遷移不可
```

不正な遷移が要求された場合は `Result.error()` を返す。

`ParticipantRepository`:

- `join(sessionId, uid, displayName)` → `Result<void>`: `participants/{uid}` ドキュメント作成
- `watchParticipants(sessionId)` → `Stream`（参加者数リアルタイム）

### ステップ 3-3: ViewModel

- `sessionProvider(sessionId)` — `StreamProvider.family`: セッション状態リアルタイム
- `participantCountProvider(sessionId)` — `StreamProvider.family`: 参加者数リアルタイム
- `sessionControlNotifier(sessionId)` — `AsyncNotifier`: 状態遷移操作（Repository の遷移バリデーション経由）

### ステップ 3-4: View — QR/URL 生成

1. セッション作成時に URL 生成: `https://<client-host>/session/{sessionId}`
2. `qr_flutter` で QR コードウィジェットを生成
3. ホーム画面に QR コード + URL を常時表示

### ステップ 3-5: View — 管理者アプリ画面

1. チャンク一覧から「セッション開始」→ セッション作成 → `/sessions/:sessionId` へ遷移
2. **待機画面**: QR コード + URL + 参加者数（リアルタイム）+ 「開始」ボタン

**テスト**: SessionRepository のユニットテスト（状態遷移バリデーション含む）、Fake Service 使用

---

## Phase 4: リアルタイム出題・回答 (F4)

**目的**: セッションの核心機能。管理者が出題を進行し、回答者がリアルタイムで回答する。

### ステップ 4-0: セキュリティルール追加

`answers` と `results` サブコレクションのルールを追加しデプロイ。

### ステップ 4-1: データモデル

- `Answer` モデル（userId, questionIndex, selectedIndex, answeredAt） — イミュータブル
  - `isCorrect` は保持しない（集計時に管理者側で判定）
- `QuestionResult` モデル（totalAnswers, choiceCounts: List\<int\>(4), correctIndex）

### ステップ 4-2: Repository

`AnswerRepository`（Service 経由、`Result<T>` で返却）:

- `submitAnswer(sessionId, answer)` → `Result<void>`: `answers/{uid}_{questionIndex}` に書き込み（ドキュメントIDで重複防止）
- `watchMyAnswers(sessionId, userId)` → `Stream`: 自分の回答一覧ストリーム
- `getAnswersByQuestion(sessionId, questionIndex)` → `Result<List<Answer>>`: 管理者用集計

`ResultRepository`（Service 経由、`Result<T>` で返却）:

- `writeResult(sessionId, questionIndex, result)` → `Result<void>`: 集計結果書き込み
- `watchResult(sessionId, questionIndex)` → `Stream`: 結果ストリーム

### ステップ 4-3: ViewModel

管理者アプリ:

- `currentQuestionProvider(sessionId)` — `Provider.family`: セッション状態から現在の問題データを導出
- `sessionControlNotifier` — Phase 3 で作成済み。以下を追加:
  - 「結果表示」: answers 集計 → results 書き込み → status を `showing_result` に
  - 「次へ」: currentQuestionIndex + 1、status を `active` に
  - 「終了」: status を `finished` に

回答者アプリ:

- `sessionProvider(sessionId)` — `StreamProvider.family`: セッション状態リアルタイム
- `currentQuestionProvider(sessionId)` — `Provider.family`: 現在の問題を導出
- `myAnswerProvider(sessionId, questionIndex)` — `FutureProvider.family`: 回答済みフラグ
- `questionResultProvider(sessionId, questionIndex)` — `StreamProvider.family`: 結果表示用

### ステップ 4-4: View — 管理者アプリ - セッション実行画面 (`/sessions/:sessionId`)

1. **出題画面**: 問題文 + 4択表示 + 「結果表示」ボタン
2. 「結果表示」押下時: answers 集計 → results 書き込み → status を `showing_result` に
3. **結果画面**: 正解 + 各選択肢の回答割合
4. 「次へ」→ currentQuestionIndex + 1、status を `active` に
5. 最後の問題後「終了」→ status を `finished` に
6. 全画面遷移は `AsyncValue.when()` で loading / error / data を表示

### ステップ 4-5: View — 回答者アプリ - セッション参加画面 (`/session/:sessionId`)

1. URL から `sessionId` を取得（GoRouter パスパラメータ）
2. 参加時に `participants/{uid}` ドキュメント作成
3. **待機画面**: status が `waiting` の間表示
4. **回答画面**: status が `active` に変わると `StreamProvider` の更新で自動遷移。4択選択 → 回答送信。回答済みなら送信不可表示。
5. **結果画面**: status が `showing_result` で正解 + 全体回答割合を表示
6. **最終結果画面**: status が `finished` で自分のスコア表示

**テスト**:

- AnswerRepository / ResultRepository のユニットテスト（Fake Service）
- 集計ロジックのユニットテスト
- セッション状態遷移に応じた View 切り替えのウィジェットテスト

---

## Phase 5: 結果表示・閲覧 (F5, F6)

**目的**: リアルタイム結果表示と後日の結果閲覧機能。

### ステップ 5-0: 複合インデックスのデプロイ

後日閲覧のクエリで必要な複合インデックスを `firebase/firestore.indexes.json` に定義しデプロイ:

```json
{
  "indexes": [
    {
      "collectionGroup": "sessions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "answers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "questionIndex", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

```bash
npx -y firebase-tools@latest deploy --only firestore:indexes
```

### ステップ 5-1: 管理者アプリ - 最終結果画面

- 全問終了後の得点分布表示（満点: X人, 0点: Y人, ...）
- `answers` サブコレクション + `results` から全ユーザーの正誤を判定・集計

### ステップ 5-2: 回答者アプリ - 最終結果画面

- 自分のスコア: X/Y問正解
- 各問題の正誤表示（`results` の `correctIndex` と自分の `answers` を照合）

### ステップ 5-3: 管理者アプリ - セッション結果画面（後日閲覧 `/sessions/:sessionId/results`）

- ホーム画面にセッション履歴一覧を追加
- セッション選択 → ユーザーごとの回答・正誤一覧テーブル
- `users` コレクションからユーザー名を取得して表示

### ステップ 5-4: 回答者アプリ - マイページ (`/mypage`, `/mypage/:sessionId`)

- 過去のセッション一覧（自分が参加したセッション）
- セッション選択 → 問題ごとの正誤・復習画面

**テスト**: 得点分布計算ロジックのユニットテスト、マイページのウィジェットテスト

---

## Phase 6: UI/UX 仕上げ・レスポンシブ対応

### ステップ 6-1: レスポンシブ対応

`LayoutBuilder` で画面幅に応じたレイアウトを切り替え:

| 幅 | デバイス | レイアウト |
|----|---------|-----------|
| < 600px | モバイル | シングルカラム、全幅4択ボタン |
| 600-1200px | タブレット | コンテンツ中央寄せ（max-width 600px） |
| > 1200px | デスクトップ | サイドバー + メイン（管理者）/ 中央寄せ（回答者） |

- 管理者アプリ: PC 優先（デスクトップレイアウトをデフォルト）
- 回答者アプリ: モバイル優先（スマホで4択ボタンが押しやすいサイズを確保）

### ステップ 6-2: パフォーマンス検証

- 100人同時回答のシミュレーション（Firebase エミュレーターでテスト）
- 回答送信から結果反映まで2秒以内の確認
- Firestore インデックス最適化

### ステップ 6-3: エラーハンドリング確認

- 全画面で `AsyncValue.when()` による loading / error / data 表示が実装されていること
- ネットワークエラー時のスナックバー通知 + リトライ UI
- セッション途中離脱からの復帰（再接続時に Firestore リスナーが自動復旧）
- 重複回答防止（UI レベル + Firestore ドキュメントID `{uid}_{questionIndex}` 制約）

---

## Phase 7: デプロイ

### ステップ 7-1: Firebase Hosting デプロイ

1. `flutter build web --release` を両アプリで実行
2. Hosting ターゲットが設定済みであることを確認（Phase 0 ステップ 0-3 で実施済み）
3. デプロイ:

   ```bash
   npx -y firebase-tools@latest deploy --only hosting:admin
   npx -y firebase-tools@latest deploy --only hosting:client
   ```

### ステップ 7-2: セキュリティルール最終確認

1. Devil's Advocate テスト（本番環境向け最終チェック）:
   - 未認証アクセスの拒否
   - 他ユーザーデータへのアクセス拒否
   - immutable フィールドの保護
   - サイズバリデーション（1MB 攻撃防止）
   - 状態遷移スキップの防止
2. 全ルールをデプロイ:

   ```bash
   npx -y firebase-tools@latest deploy --only firestore:rules
   npx -y firebase-tools@latest deploy --only firestore:indexes
   ```

### ステップ 7-3: 本番動作確認

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

### 4. 参加者管理

`sessions/{sessionId}/participants/{uid}` サブコレクションで管理。回答者が自身のドキュメントを作成（セキュリティルールで本人のみ作成可）。管理者は participants のカウントで参加者数を把握。

### 5. 共有コードについて

`admin` と `client` は独立した Flutter プロジェクト。初期段階では各アプリにコードをコピーで対応し、将来的に `shared/` パッケージとして切り出すことを検討する。

### 6. エラーハンドリング

`Result<T>` + `AsyncValue` の2段構えで統一:

- Service: 例外を投げる可能性あり
- Repository: try-catch で `Result<T>`（Ok/Error）にラップして返す
- ViewModel (AsyncNotifier): `Result<T>` を `AsyncValue` に変換
- View: `AsyncValue.when()` で状態切り替え

### 7. セッション状態遷移バリデーション

不正な状態遷移を Repository レベルで防止:

- `waiting → active` のみ
- `active → showing_result` のみ
- `showing_result → active`（次の問題）or `finished`（最終問題後）のみ
- `finished → 遷移不可`

### 8. セキュリティルールの段階的デプロイ

Phase 0 で全拒否ルールをデプロイし、各 Phase で必要なコレクションのルールを段階的に追加する。デプロイ前に毎回 Devil's Advocate テストを実施。

---

## テスト戦略

| レベル | 対象 | ツール |
|--------|------|--------|
| ユニットテスト | モデル、Repository、ViewModel | `flutter_test`, Fake クラス（手書き） |
| ウィジェットテスト | 各画面の表示・操作 | `flutter_test`, `ProviderScope.overrides` |
| 統合テスト | セッションフロー全体 | Firebase エミュレーター + `integration_test` |
| 手動テスト | リアルタイム同期、複数端末 | 実機 / ブラウザ複数タブ |

### テスト方針

- **Fake を推奨、Mock は補助**: 外部依存は手書きの Fake クラスで差し替え。`mockito` はFake では表現しにくい複雑な振る舞いの検証にのみ使用
- **Service 層**: ステートレスな薄いラッパーのため、統合テストでカバー
- **Repository 層**: Fake Service でユニットテスト。`Result<T>` の Ok / Error 両方をテスト
- **ViewModel 層**: `ProviderContainer` + Fake Repository で独立テスト
- **View 層**: ロジックを持たないため、ウィジェットテストは表示確認が中心（`ProviderScope.overrides` で依存差し替え）
- 各 Phase 完了時にそのフェーズのテストが全てパスすることを確認
