# リアルタイムクイズセッション — 仕様書

## 概要

講義で使用するリアルタイムクイズシステム。
講師が事前に作成したクイズを出題し、受講者がリアルタイムで回答する。
**管理者アプリ**と**回答者アプリ**の2つの独立したWebアプリで構成する。

| アプリ | 説明 | ディレクトリ |
|--------|------|------------|
| **管理者アプリ** (`admin`) | クイズ作成・セッション進行・結果閲覧 | `admin/` |
| **回答者アプリ** (`client`) | クイズ回答・復習 | `client/` |

- **フロントエンド**: Flutter Web（2アプリ）
- **バックエンド**: Firebase (Firestore, Auth, Hosting) — 共通プロジェクト
- **同時接続**: 5〜100人を想定（回答者側）

---

## ユーザーロール

| ロール | 説明 |
|--------|------|
| **管理者（講師）** | クイズの作成・セッション進行・結果閲覧 |
| **回答者（受講者）** | QR/URLからアクセスしクイズに回答・自分の結果を復習 |

---

## アプリアーキテクチャ

両アプリとも **MVVM + 3層アーキテクチャ**（単方向データフロー）を採用する。

```
┌──────────────────────────────────────────────────┐
│  UI層 (View)                                      │
│  - StatelessWidget / ConsumerWidget               │
│  - ロジックを持たない（表示とイベント発火のみ）         │
└──────────────┬───────────────────▲────────────────┘
        イベント ↓                  ↑ 状態
┌──────────────▼───────────────────┴────────────────┐
│  Domain層 (ViewModel)                              │
│  - Riverpod Notifier / AsyncNotifier               │
│  - UI向けの状態変換・ビジネスロジック                   │
└──────────────┬───────────────────▲────────────────┘
               ↓                  ↑
┌──────────────▼───────────────────┴────────────────┐
│  Data層                                            │
│  - Repository: 単一のデータソース、ビジネスロジック     │
│  - Service: Firestore/Auth API ラッパー（ステートレス）│
└──────────────────────────────────────────────────┘
```

### 原則

- **データは下方向のみ**: Data → ViewModel → View
- **イベントは上方向のみ**: View → ViewModel → Repository
- **View にロジックを書かない**: 条件分岐・計算は ViewModel で行う
- **Service はステートレス**: 状態を保持しない。Firestore/Auth の薄いラッパー
- **Repository が単一のデータソース**: Service を組み合わせてデータを管理
- **モデルはイミュータブル**: UI層に渡すドメインモデルは不変オブジェクト

### エラーハンドリング

- Repository は成功/失敗を明示的に返す（例外を投げずに `AsyncValue` で表現）
- ViewModel は `AsyncNotifier` で loading / error / data 状態を管理
- View は `AsyncValue.when()` で状態に応じた表示を切り替え（ローディング、エラー、データ）
- ネットワークエラー時はスナックバーで通知し、リトライ可能な UI を表示

---

## 画面構成

### 管理者アプリ (`admin`)

```
ログイン画面（メールアドレス + パスワード）

ホーム画面
├── クイズチャンク一覧（作成済みのクイズセット）
├── クイズチャンク作成/編集
└── [常時表示] セッション参加用 QRコード + URL

セッション実行画面（チャンク選択後）
├── 待機画面（参加者数表示 + 開始ボタン）
├── 出題画面（問題文 + 4択表示）
├── 結果画面（正解 + 各選択肢の回答割合）
│   └── 「次へ」で次の問題へ
└── 最終結果画面（全問終了後）
    ├── 得点分布（満点: X人, 0点: Y人, ...）
    └── セッション終了

セッション結果画面（後日閲覧用）
└── ユーザーごとの回答・正誤一覧
```

### 回答者アプリ (`client`)

```
新規登録画面
├── メールアドレス入力（学校指定メール）
├── ユーザー名入力
└── パスワード設定

ログイン画面（メールアドレス + パスワード）

セッション参加画面（QR/URLからアクセス）
├── 待機画面（セッション開始を待つ）
├── 回答画面（4択から1つ選択）
├── 結果画面（正解表示 + 全体の回答割合）
│   └── 次の問題を待つ
└── 最終結果画面（自分のスコア: X/Y問正解）

マイページ
└── 過去のクイズ結果一覧
    └── 問題ごとの正誤・復習
```

---

## 画面遷移フロー

### 管理者アプリフロー

```
[ログイン] → [ホーム] → チャンク選択 → [待機] → 開始 → [出題Q1] → [結果Q1] → [出題Q2] → [結果Q2] → ... → [最終結果]
```

### 回答者アプリフロー

```
[QR/URLアクセス] → [新規登録 or ログイン] → [待機] → [回答Q1] → [結果Q1] → [回答Q2] → [結果Q2] → ... → [最終結果]
```

---

## ルーティング（GoRouter）

Webアプリのため、全画面にブックマーク可能なURLを割り当てる。
未認証時は `/login` にリダイレクト。

### 管理者アプリ

| パス | 画面 | 認証 |
|------|------|------|
| `/login` | ログイン | 不要 |
| `/` | ホーム（チャンク一覧） | 管理者 |
| `/chunks/new` | チャンク作成 | 管理者 |
| `/chunks/:chunkId/edit` | チャンク編集 | 管理者 |
| `/sessions/:sessionId` | セッション実行 | 管理者 |
| `/sessions/:sessionId/results` | セッション結果（後日閲覧） | 管理者 |

### 回答者アプリ

| パス | 画面 | 認証 |
|------|------|------|
| `/login` | ログイン | 不要 |
| `/register` | 新規登録 | 不要 |
| `/session/:sessionId` | セッション参加（待機〜最終結果） | 要ログイン |
| `/mypage` | マイページ（過去の結果一覧） | 要ログイン |
| `/mypage/:sessionId` | 過去の結果詳細 | 要ログイン |

---

## 状態管理（Riverpod）

### 状態の分類

| 状態 | 種別 | Riverpod プロバイダー |
|------|------|----------------------|
| フォーム入力値（ログイン、チャンク編集） | エフェメラル | `setState` / `TextEditingController` |
| 認証状態（ログイン中ユーザー） | アプリ（ストリーム） | `StreamProvider`（`authStateChanges()`） |
| 管理者判定 | アプリ（派生） | `FutureProvider`（`admins/{uid}` 存在確認） |
| セッション状態（status, currentQuestionIndex） | アプリ（リアルタイム） | `StreamProvider`（Firestore `snapshots()`） |
| 現在の問題データ | アプリ（派生） | `Provider`（セッション状態から導出） |
| 回答済みフラグ | アプリ | `FutureProvider`（answers ドキュメント存在確認） |
| チャンク一覧 | アプリ（ストリーム） | `StreamProvider`（管理者アプリのみ） |
| 参加者数 | アプリ（リアルタイム） | `StreamProvider`（participants コレクション） |

### 原則

- リアルタイム同期が必要なデータは `StreamProvider` + Firestore `snapshots()` で管理
- 派生状態は `Provider` で元の状態から計算（重複管理しない）
- エフェメラル状態（フォーム入力等）は Widget ローカルで管理し、Riverpod に載せない

---

## 機能一覧

### F1: 認証（共通 Firebase Auth プロジェクト）

- メール/パスワード認証（Firebase Auth）
- **回答者アプリ**: 新規登録（メールアドレス + ユーザー名 + パスワード）/ ログイン
- **管理者アプリ**: ログインのみ（アカウントは事前登録済み、Firestore `admins` に存在しないユーザーはログイン拒否）
- メール検証（email verification）は現時点では不要とする（学校指定メールの信頼性を前提）

### F2: クイズチャンク管理 [管理者アプリ]

- クイズチャンク（問題セット）の CRUD
- 各チャンクは複数のクイズ問題を含む
- 各問題: 問題文 + 4つの選択肢 + 正解インデックス

### F3: セッション管理 [管理者アプリ]

- チャンク選択 → セッション作成
- セッション作成時、チャンクの問題データ（問題文 + 選択肢のみ、**correctIndex は含めない**）を `sessions` にコピー
- セッション参加用 QRコード + URL の生成・常時表示
- セッション状態管理（待機中 / 出題中 / 結果表示中 / 終了）
- 現在の問題番号の管理
- 参加者管理: `participants` サブコレクションで回答者の参加を記録

### F4: リアルタイム出題・回答 [両アプリ]

- 管理者アプリ: 「開始」「次へ」操作でセッション状態を更新
- 回答者アプリ: Firestore リアルタイムリスナーで状態変化を検知し画面を自動遷移
- 回答者は出題中のみ回答可能
- 回答は1問につき1回のみ
- 回答締切は管理者が「結果表示」に進めた時点

### F5: 結果表示 [両アプリ]

- 各問題終了時: 正解 + 各選択肢の回答者割合（リアルタイム集計）
- 全問終了時:
  - 管理者アプリ: 得点分布（満点X人、0点Y人 etc.）
  - 回答者アプリ: 自分のスコア（X/Y問正解）

### F6: 結果閲覧（後日） [両アプリ]

- 管理者アプリ: セッションごとにユーザー別の回答・正誤を閲覧
- 回答者アプリ: マイページから過去の結果を確認・復習

---

## データモデル（Firestore）

各フィールドの型・制約・イミュータブル属性を明記する。

### `admins` コレクション

```
admins/{uid}
├── email: string (必須, immutable)
└── name: string (必須, max 100文字)
```

- 手動管理（Firebase Console から登録）

### `quizChunks` コレクション

```
quizChunks/{chunkId}
├── title: string (必須, max 200文字)
├── description: string (任意, max 1000文字)
├── createdBy: string (必須, uid, immutable)
├── createdAt: timestamp (必須, immutable)
└── questions: array (必須, 1〜50件)
    └── [index]: map
        ├── text: string (必須, max 500文字)
        ├── choices: array of string (必須, 固定4件, 各 max 200文字)
        └── correctIndex: number (必須, 0-3)
```

### `sessions` コレクション

```
sessions/{sessionId}
├── chunkId: string (必須, immutable)
├── status: string (必須, "waiting" | "active" | "showing_result" | "finished")
├── currentQuestionIndex: number (必須, >= 0)
├── createdBy: string (必須, uid, immutable)
├── createdAt: timestamp (必須, immutable)
└── questions: array (必須, immutable)
    └── [index]: map
        ├── text: string          // 問題文
        └── choices: array of string  // 選択肢（4件）
        // ※ correctIndex は含めない（回答者への秘匿のため）
```

- セッション作成時に `quizChunks` から問題データをコピー（`correctIndex` を除外）
- 回答者は `sessions` のみ参照するため、正解を事前に知ることができない

### `sessions/{sessionId}/participants` サブコレクション

```
participants/{uid}
├── joinedAt: timestamp (必須, immutable)
└── displayName: string (必須, max 100文字)
```

- 回答者がセッションに参加した際に自身のドキュメントを作成
- 管理者は participants のカウントで参加者数を把握

### `sessions/{sessionId}/answers` サブコレクション

```
answers/{odcumentId}          // documentId = "{uid}_{questionIndex}"
├── userId: string (必須, uid, immutable)
├── questionIndex: number (必須, >= 0, immutable)
├── selectedIndex: number (必須, 0-3, immutable)
└── answeredAt: timestamp (必須, immutable)
```

- `isCorrect` は保持しない（正解情報は結果集計時に管理者側で判定）
- ドキュメントID の形式 `{uid}_{questionIndex}` で重複回答を防止
- 全フィールド immutable（update 不可）

### `sessions/{sessionId}/results` サブコレクション

```
results/{questionIndex}
├── totalAnswers: number (必須)
├── choiceCounts: array of number (必須, 固定4件)
└── correctIndex: number (必須, 0-3)
```

- 管理者が「結果表示」に遷移した時点で、`answers` を集計して書き込む
- `correctIndex` はこの時点で初めて回答者に公開される

### `users` コレクション

```
users/{uid}
├── email: string (必須, immutable, max 254文字)
├── displayName: string (必須, max 100文字)
└── createdAt: timestamp (必須, immutable)
```

- PII（email）を含むため、読み取りは本人または管理者のみ

---

## セッションの状態遷移

```
waiting → active → showing_result → active → showing_result → ... → finished
            │           │
            │ (出題中)   │ (結果表示中)
            │           │
     回答受付中     回答締切・集計表示
```

管理者の操作:
1. `waiting`: 参加者を待つ。「開始」押下で `active` へ
2. `active`: 出題中。管理者が「結果表示」押下で `showing_result` へ
3. `showing_result`: 正解・割合表示。「次の問題」押下で次の `active` へ
4. 最後の問題の結果表示後、「終了」押下で `finished` へ

---

## 技術構成

| 要素 | 技術 |
|------|------|
| UI | Flutter Web × 2アプリ |
| 認証 | Firebase Authentication (Email/Password) |
| DB | Cloud Firestore |
| リアルタイム同期 | Firestore リアルタイムリスナー (`snapshots()`) |
| QRコード生成 | `qr_flutter` パッケージ（管理者アプリ） |
| ホスティング | Firebase Hosting（マルチサイト: admin / client） |
| 状態管理 | Riverpod |

### Firebase 設定 (`firebase.json`)

```json
{
  "auth": {
    "providers": {
      "emailPassword": true
    }
  }
}
```

### リポジトリ構成

```
flutter-quiz/
├── admin/          # 管理者アプリ（Flutter Web）
├── client/         # 回答者アプリ（Flutter Web）
├── firebase/       # Firebase 設定（共通）
│   ├── firestore.rules
│   └── firestore.indexes.json
└── docs/           # ドキュメント
```

### 複合インデックス（`firestore.indexes.json`）

以下のクエリで複合インデックスが必要となる:

| 用途 | コレクション | フィールド |
|------|------------|-----------|
| セッション一覧（状態+日時順） | `sessions` | `status` ASC, `createdAt` DESC |
| ユーザー別回答取得 | `sessions/{id}/answers` | `userId` ASC, `questionIndex` ASC |

---

## セキュリティルール（Firestore）

Validator Function Pattern を採用し、全コレクションにバリデーション関数を適用する。

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ========== ヘルパー関数 ==========

    function isAuthenticated() {
      return request.auth != null;
    }

    function isAdmin() {
      return isAuthenticated()
        && exists(/databases/$(database)/documents/admins/$(request.auth.uid));
    }

    function isOwner(uid) {
      return isAuthenticated() && request.auth.uid == uid;
    }

    // イミュータブルフィールド保護
    function immutableFieldsUnchanged(fields) {
      return !request.resource.data.diff(resource.data).affectedKeys().hasAny(fields);
    }

    // ========== admins ==========

    match /admins/{uid} {
      allow read: if isAdmin();
      allow write: if false; // 手動管理のみ
    }

    // ========== quizChunks ==========

    match /quizChunks/{chunkId} {
      function isValidQuizChunk(data) {
        return data.keys().hasAll(['title', 'createdBy', 'createdAt', 'questions'])
          && data.title is string && data.title.size() > 0 && data.title.size() <= 200
          && (!('description' in data) || (data.description is string && data.description.size() <= 1000))
          && data.createdBy is string
          && data.createdAt is timestamp
          && data.questions is list && data.questions.size() >= 1 && data.questions.size() <= 50;
      }

      allow read: if isAdmin();
      allow create: if isAdmin()
        && isValidQuizChunk(request.resource.data)
        && request.resource.data.createdBy == request.auth.uid;
      allow update: if isAdmin()
        && isValidQuizChunk(request.resource.data)
        && immutableFieldsUnchanged(['createdBy', 'createdAt']);
      allow delete: if isAdmin();
    }

    // ========== sessions ==========

    match /sessions/{sessionId} {
      function isValidSession(data) {
        return data.keys().hasAll(['chunkId', 'status', 'currentQuestionIndex', 'createdBy', 'createdAt', 'questions'])
          && data.chunkId is string
          && data.status in ['waiting', 'active', 'showing_result', 'finished']
          && data.currentQuestionIndex is number && data.currentQuestionIndex >= 0
          && data.createdBy is string
          && data.createdAt is timestamp
          && data.questions is list && data.questions.size() >= 1;
      }

      allow read: if isAuthenticated();
      allow create: if isAdmin()
        && isValidSession(request.resource.data)
        && request.resource.data.createdBy == request.auth.uid;
      allow update: if isAdmin()
        && isValidSession(request.resource.data)
        && immutableFieldsUnchanged(['chunkId', 'createdBy', 'createdAt', 'questions']);
      allow delete: if false;

      // ----- participants -----

      match /participants/{uid} {
        function isValidParticipant(data) {
          return data.keys().hasAll(['joinedAt', 'displayName'])
            && data.joinedAt is timestamp
            && data.displayName is string && data.displayName.size() > 0 && data.displayName.size() <= 100;
        }

        allow read: if isAuthenticated();
        allow create: if isOwner(uid)
          && isValidParticipant(request.resource.data);
        allow update, delete: if false;
      }

      // ----- answers -----

      match /answers/{answerId} {
        function isValidAnswer(data) {
          return data.keys().hasAll(['userId', 'questionIndex', 'selectedIndex', 'answeredAt'])
            && data.userId is string
            && data.questionIndex is number && data.questionIndex >= 0
            && data.selectedIndex is number && data.selectedIndex >= 0 && data.selectedIndex <= 3
            && data.answeredAt is timestamp;
        }

        allow read: if isAdmin() || (isAuthenticated() && resource.data.userId == request.auth.uid);
        allow create: if isAuthenticated()
          && isValidAnswer(request.resource.data)
          && request.resource.data.userId == request.auth.uid;
        allow update, delete: if false; // 回答変更不可
      }

      // ----- results -----

      match /results/{questionIndex} {
        function isValidResult(data) {
          return data.keys().hasAll(['totalAnswers', 'choiceCounts', 'correctIndex'])
            && data.totalAnswers is number && data.totalAnswers >= 0
            && data.choiceCounts is list && data.choiceCounts.size() == 4
            && data.correctIndex is number && data.correctIndex >= 0 && data.correctIndex <= 3;
        }

        allow read: if isAuthenticated();
        allow create, update: if isAdmin() && isValidResult(request.resource.data);
        allow delete: if false;
      }
    }

    // ========== users ==========

    match /users/{uid} {
      function isValidUser(data) {
        return data.keys().hasAll(['email', 'displayName', 'createdAt'])
          && data.email is string && data.email.size() > 0 && data.email.size() <= 254
          && data.displayName is string && data.displayName.size() > 0 && data.displayName.size() <= 100
          && data.createdAt is timestamp;
      }

      allow read: if isOwner(uid) || isAdmin();
      allow create: if isOwner(uid) && isValidUser(request.resource.data);
      allow update: if isOwner(uid)
        && isValidUser(request.resource.data)
        && immutableFieldsUnchanged(['email', 'createdAt']);
      allow delete: if false;
    }
  }
}
```

---

## 非機能要件

- **レスポンス**: 回答送信から結果反映まで2秒以内
- **同時接続**: 100人同時回答でも安定動作
- **対応端末**: PC / スマートフォンのブラウザ（レスポンシブ対応）
- **オフライン**: 非対応（リアルタイム通信が前提）

### レスポンシブブレークポイント

`LayoutBuilder` で画面幅に応じたレイアウトを切り替える。

| 幅 | デバイス | レイアウト |
|----|---------|-----------|
| < 600px | モバイル | シングルカラム、全幅4択ボタン |
| 600-1200px | タブレット | コンテンツ中央寄せ（max-width 600px） |
| > 1200px | デスクトップ | サイドバー + メイン（管理者）/ 中央寄せ（回答者） |

- 管理者アプリ: PC 優先（デスクトップレイアウトをデフォルト）
- 回答者アプリ: モバイル優先（スマホで4択ボタンが押しやすいサイズを確保）

### テスト方針

| レベル | 対象 | ツール |
|--------|------|--------|
| ユニットテスト | Repository, ViewModel, モデル | `flutter_test`, `mockito`, `fake_cloud_firestore` |
| ウィジェットテスト | 各画面の表示・操作 | `flutter_test`, `ProviderScope.overrides` |
| 統合テスト | セッション全体フロー（ログイン→回答→結果） | Firebase エミュレーター + `integration_test` |

- Repository は Fake でテスト（Firestore に依存しない）
- ViewModel は `ProviderContainer` で独立テスト
- View はロジックを持たないため、ウィジェットテストは表示確認が中心
- 各 Phase 完了時にそのフェーズのテストが全てパスすることを確認

---

## 今後の拡張候補（スコープ外）

- 問題の画像添付
- 制限時間付き回答
- ランキング表示
- CSV エクスポート
- 複数正解対応
