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

## 機能一覧

### F1: 認証（共通 Firebase Auth プロジェクト）

- メール/パスワード認証（Firebase Auth）
- **回答者アプリ**: 新規登録（メールアドレス + ユーザー名 + パスワード）/ ログイン
- **管理者アプリ**: ログインのみ（アカウントは事前登録済み、Firestore `admins` に存在しないユーザーはログイン拒否）

### F2: クイズチャンク管理 [管理者アプリ]

- クイズチャンク（問題セット）の CRUD
- 各チャンクは複数のクイズ問題を含む
- 各問題: 問題文 + 4つの選択肢 + 正解インデックス

### F3: セッション管理 [管理者アプリ]

- チャンク選択 → セッション作成
- セッション参加用 QRコード + URL の生成・常時表示
- セッション状態管理（待機中 / 出題中 / 結果表示中 / 終了）
- 現在の問題番号の管理

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

### `admins` コレクション

```
admins/{uid}
├── email: string
└── name: string
```

### `quizChunks` コレクション

```
quizChunks/{chunkId}
├── title: string
├── description: string
├── createdBy: string (uid)
├── createdAt: timestamp
└── questions: array
    └── [index]
        ├── text: string          // 問題文
        ├── choices: string[4]    // 選択肢
        └── correctIndex: number  // 正解 (0-3)
```

### `sessions` コレクション

```
sessions/{sessionId}
├── chunkId: string
├── status: "waiting" | "active" | "showing_result" | "finished"
├── currentQuestionIndex: number
├── createdBy: string (uid)
├── createdAt: timestamp
└── participantCount: number
```

### `sessions/{sessionId}/answers` サブコレクション

```
answers/{odcumentId}
├── odcumentId: "{odcumentId}" = "{odcumentId}_{questionIndex}"
├── odcumentId: string  (uid)
├── questionIndex: number
├── selectedIndex: number  (0-3)
├── isCorrect: boolean
└── answeredAt: timestamp
```

### `sessions/{sessionId}/results` サブコレクション

```
results/{questionIndex}
├── totalAnswers: number
├── choiceCounts: number[4]    // 各選択肢の回答数
└── correctIndex: number
```

### `users` コレクション

```
users/{uid}
├── email: string
├── displayName: string
└── createdAt: timestamp
```

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

---

## セキュリティルール（Firestore）

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 管理者判定
    function isAdmin() {
      return exists(/databases/$(database)/documents/admins/$(request.auth.uid));
    }

    // 認証済み判定
    function isAuthenticated() {
      return request.auth != null;
    }

    match /admins/{uid} {
      allow read: if isAdmin();
      allow write: if false; // 手動管理
    }

    match /quizChunks/{chunkId} {
      allow read: if isAdmin();
      allow write: if isAdmin();
    }

    match /sessions/{sessionId} {
      allow read: if isAuthenticated();
      allow create: if isAdmin();
      allow update: if isAdmin();

      match /answers/{answerId} {
        allow read: if isAdmin() || request.auth.uid == resource.data.userId;
        allow create: if isAuthenticated()
          && request.auth.uid == request.resource.data.userId;
        allow update: if false; // 回答変更不可
      }

      match /results/{questionIndex} {
        allow read: if isAuthenticated();
        allow write: if isAdmin();
      }
    }

    match /users/{uid} {
      allow read: if request.auth.uid == uid || isAdmin();
      allow create: if request.auth.uid == uid;
      allow update: if request.auth.uid == uid;
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

---

## 今後の拡張候補（スコープ外）

- 問題の画像添付
- 制限時間付き回答
- ランキング表示
- CSV エクスポート
- 複数正解対応
