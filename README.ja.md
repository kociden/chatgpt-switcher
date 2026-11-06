# ChatGPT Switcher for Windows

Windowsで**ChatGPTデスクトップアプリ**の複数アカウントを、Googleのアカウント切替のように切り替えるツールです。小さな一覧から選ぶと、そのアカウント専用のChatGPTウィンドウが開きます。複数アカウントの同時起動もできます。

依存ゼロのPowerShellスクリプト1本。**インストール不要・常駐なし・約35KB・中身は全部読める。** 今のログインは「メイン」としてそのまま残ります。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)

> [English README](README.md)

---

## なぜ作ったか

2026年時点で、ChatGPTの**Web版**は最大2アカウントの切替に対応しましたが、**デスクトップアプリ**（新しいMicrosoft Store版・パッケージ名 `OpenAI.Codex`）にはアカウント切替が一切ありません。毎回ログアウト→ログインが必要でした。

このスクリプトは、デスクトップアプリにGoogle風のアカウント切替を与えます。ワンクリックで各アカウント、すべて小さな一覧から。

## 特長

- **アカウント一覧** — Googleのアカウント選択のような小窓から起動
- **完全分離** — アカウントごとに専用の Electron ユーザーデータと `CODEX_HOME` を持つのでログインが混ざらない
- **同時起動** — 仕事用と個人を別ウィンドウで並べて使える
- **アカウント別ショートカット** — 自動作成。デスクトップから直接起動できる
- **トレイ常駐** — タスクトレイに常駐。左クリックで一覧、右クリックで各アカウントを直接起動
- **今のログインはそのまま** — 「メイン」として表示。移行も上書きもしない
- **インストール不要・依存なし** — PowerShellスクリプトと `.cmd` だけ。トレイ常駐を選ばない限り何も常駐しない

## 2つのモード

各アカウントは次のどちらかです:

- **分離モード（既定）** — 専用の Electron データと `CODEX_HOME` を持ち、ログインもCodexのプロジェクト/チャットも完全に別。**複数アカウントの同時起動が可能**。
- **完全共有モード（`-Shared`）** — 実の `~/.codex` を使うので、**プロジェクト・チャット・設定が全アカウントで共有**（公式に近い挙動）。切替時に `auth.json` だけ差し替えます。**共有アカウントは1つずつ**（同じ `~/.codex` を2プロセスで触ると壊れ、現行Codex Desktopはシンボリックリンクしたセッションストアを拒否するため）。`auth.json` は毎回バックアップされ、失敗しても再ログインで復帰できます（プロジェクト/チャットは無傷）。

完全共有アカウントの初回: 起動してログイン → `-SaveAuth <id>`（または一覧で右クリック→「現在のログインをこのアカウントとして保存」）。

## 仕組み

ChatGPTデスクトップアプリはElectron製で、次の2つで完全に別インスタンスを起動できます。

| 何を | 設定方法 | 中身 |
|------|----------|------|
| Electron のユーザーデータ | 環境変数 `CODEX_ELECTRON_USER_DATA_PATH` + 起動引数 `--user-data-dir=` | Cookie（=ChatGPTのログイン）、ローカル設定、キャッシュ |
| Codex のホーム | 環境変数 `CODEX_HOME` | `auth.json`、セッション、設定 |

各アカウントは `%USERPROFILE%\ChatGPT-Accounts\<id>\` 以下の `electron` / `codex` フォルダを持つだけ。そこを指して `ChatGPT.exe` を起動します。macOS向けの [ccheney/chatgpt-multi-account](https://github.com/ccheney/chatgpt-multi-account) や [Ducksss/codex-profiles](https://github.com/Ducksss/codex-profiles) と同じ方式です。

## 必要環境

- Windows 10 / 11
- 公式**ChatGPTデスクトップアプリ**（[Microsoft Store](https://apps.microsoft.com/) または `winget install --id 9PLM9XGG6VKS -s msstore`）
- Windows PowerShell 5.1（標準搭載）または PowerShell 7+

## 導入

### 方法A — ワンライナー（おすすめ）

PowerShellで実行:

```powershell
irm https://raw.githubusercontent.com/__OWNER__/__REPO__/main/install.ps1 | iex
```

`Documents\ChatGPT-Switcher` にスクリプトを置き、スタートメニューとデスクトップにショートカットを作ります。システムには何もインストールされません。

### 方法B — 手動

1. このリポジトリをダウンロード（緑の **Code** → Download ZIP）またはクローン。
2. `ChatGPT-Switcher` フォルダを好きな場所（例: `Documents\ChatGPT-Switcher`）に置く。
3. `ChatGPT-Switcher.cmd` をダブルクリック。

実行ポリシーの変更は不要です（そのプロセスだけ `-ExecutionPolicy Bypass` で動きます）。

## 使い方

**`ChatGPT-Switcher.cmd`** をダブルクリック → **日本語 / English** を選択 → 一覧が開く。

次回の起動時には前回選んだ言語が選択されています。言語選択画面を閉じると起動を中止します。一覧の **設定 → 言語** からも変更できます。選択した言語は、このツールの画面・ダイアログ・メニュー・トレイ・環境診断に適用されます。ChatGPT 自体の言語設定は別です。

コマンドライン操作は保存された言語を使い、言語選択画面を表示しません。`-Language en` / `-Language ja` を指定すると、その実行だけ言語を上書きし、起動時の言語選択も省略できます（例: `ChatGPT-Switcher.cmd -Language en`、`ChatGPT-Switcher.cmd -Diagnose -Language en`）。ショートカットのファイル名は言語を切り替えても変わりません。

1. **＋ アカウントを追加** → 名前を入力（仕事用 / 個人 …）。
2. 新しいChatGPTウィンドウがサインイン画面で開く → そのアカウントでログイン。
3. 以降は一覧をクリックするだけ。`ChatGPT - 〇〇` のデスクトップショートカットも作られます。

一覧で右クリックすると **ショートカット作成 / 名前変更 / 削除**。今のログインは常に **メイン** として表示されます。

### コマンドライン

```
ChatGPT-Switcher.cmd                  一覧を開く
ChatGPT-Switcher.cmd -Launch 仕事用    指定アカウントで起動（起動中なら前面へ）
ChatGPT-Switcher.cmd -Add 仕事用       追加（+デスクトップにショートカット）
ChatGPT-Switcher.cmd -Remove 仕事用    削除（このPCのそのアカウントのログイン/キャッシュを削除）
ChatGPT-Switcher.cmd -List            一覧表示
ChatGPT-Switcher.cmd -Setup           一覧のショートカットをデスクトップ/スタートに作成
ChatGPT-Switcher.cmd -Tray            タスクトレイ常駐
ChatGPT-Switcher.cmd -AutoStartTray   トレイ常駐をWindows起動時に自動開始
ChatGPT-Switcher.cmd -Diagnose        環境診断
ChatGPT-Switcher.cmd -Version         バージョン表示
```

## 注意・制限

- **サーバー側**の履歴・メモリ・課金はアカウントごとに別のまま。ローカルのセッションを分けているだけで、共有も統合もしません。
- 全ウィンドウのタスクバーアイコンは同じです。判別はアプリ左下のアバター、または一覧の「● 起動中」表示で。
- アプリのアップデートで内部仕様が変わると起動できなくなる可能性があります。`-Diagnose` の出力を添えてissueを立ててください。
- 複数アカウントの所持自体はOpenAIの規約で禁止されていませんが、**Team/Enterpriseの管理ワークスペース**では管理者のポリシーに従ってください。
- これは**非公式**ツールで、OpenAIとは無関係です。自己責任で利用してください（[LICENSE](LICENSE) 参照）。

## アンインストール

`ChatGPT-Switcher` フォルダとショートカット、（必要なら）`%USERPROFILE%\ChatGPT-Accounts` を削除するだけです。

## コントリビュート

Issue / PR 歓迎です（[CONTRIBUTING.md](CONTRIBUTING.md)）。設計上、小さな1ファイルツールに保つ方針です。

## ライセンス

[MIT](LICENSE)
