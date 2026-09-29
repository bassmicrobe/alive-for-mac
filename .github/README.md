<div align="center">

# Alive for Mac

**Ableton Live のプロジェクト・プラグイン・サンプルを素早く一覧できる、macOS ネイティブのカタログアプリ**

RueBlose 作 [Alive](https://github.com/rueblose/alive) の**非公式 macOS 版ポート**です。

![platform](https://img.shields.io/badge/macOS-14%2B-000000)
![arch](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-universal-555555)
![license](https://img.shields.io/badge/license-MIT-blue)

[**ダウンロード**](https://github.com/bassmicrobe/alive-for-mac/releases/latest) · [インストール](#インストール) · [機能](#機能) · [ショートカット](#キーボードショートカット) · [ビルド](#ソースからのビルド) · [ライセンス](#ライセンス) · [オリジナルとの差分](../macos/PARITY.md) · **日本語** | [English](README.en.md)

</div>

---

Alive for Mac は Live セット（`.als`）の中身を読み取り、テンポ、キー、プラグイン、サンプル、どれが最新バージョンかを一覧します。
Windows 専用だったオリジナルを Swift / SwiftUI で書き直したもので、ラッパーではありません。
オリジナルの C# ソースは移植の参照として、このリポジトリにそのまま残してあります。

## 動作環境

- macOS 14（Sonoma）以降。Apple Silicon と Intel の両方に対応するユニバーサルバイナリです。
- Ableton Live は必須ではありません。なくてもセットのカタログは使えますが、「Live で開く」は使えません。

## インストール

1. [Releases](https://github.com/bassmicrobe/alive-for-mac/releases/latest) から `AliveForMac-<バージョン>.dmg` をダウンロードします。
2. DMG を開き、**Alive for Mac** を **Applications** フォルダにドラッグします。
3. 初回起動の許可を与えます。このアプリは **ad-hoc 署名のみで、公証（notarize）されていません**。そのため macOS の Gatekeeper が初回起動をブロックします。
   - macOS 15（Sequoia）以降では、右クリック →「開く」では回避できません。次の手順で許可します。
     1. Applications から **Alive for Mac** を一度開こうとします（ブロックされます）。
     2. **システム設定 → プライバシーとセキュリティ** を開き、下の方に表示される「"Alive for Mac" はブロックされました」の横にある **「このまま開く」** を押します。
     3. 確認ダイアログで承認します（パスワードまたは Touch ID を求められます）。
   - 上級者向けの代替手段として、ターミナルで隔離属性を外すこともできます。

     ```sh
     xattr -dr com.apple.quarantine "/Applications/Alive for Mac.app"
     ```
4. ツールバーのフォルダボタンから Live のプロジェクトフォルダを追加し、**スキャン**を押します。

DMG にはアプリのほか、ライセンス文書（`LICENSE`、`LICENSE-macos`、`NOTICE.md`）が入っています。`.zip` 版もリリースに添付しています。

## 機能

- **ホーム。** プロジェクトごとにアレンジメントの絵付きタイル。ピン留め、セットの隣にあるレンダーの再生、1 年分の作業状況（作業した日、連続日数、最長記録、ピーク時間帯）。
- **セット。** テンポ、キー、Live バージョン、トラック数、プラグイン、ファイル、プロジェクトサイズを一目で確認。
  バージョン違い（`v1`、`final`、`final 2` など）は 1 行にまとまります。フィルター、検索、列の並べ替え、プロジェクトごとのタグとメモ。新しいセットは自動で現れます。
- **プラグイン。** Audio Unit、VST、VST3 を 1 つのリストに。メーカー、使用セット数、インストール済みかどうか。一覧の取得元は設定で「Live のプラグインデータベース」と「プラグインフォルダ」から選べます。見つからないプラグインは 1 つずつエラーにせず、落ち着いた状態表示にまとめます。
- **サンプル。** どのサンプルフォルダを実際に使い、どれを一度も使っていないかをプロジェクト単位で集計。未使用・よく使う・重複。クリックで試聴、Live へドラッグ。
- **レスキュー。** セットが開かない場合に、Live のログからクラッシュしたプラグインを特定するか、セットのコピーでプラグインを 1 つずつ外して原因を探します。元のセットには触れません。
- **エクスポート。** セットに必要なものを 1 つのフォルダまたは `.zip` に集めます（Live の「すべてを収集して保存」に相当）。
- **プレビューとプレーヤー。** アレンジメント全体を Live のクリップ色で表示。セットの隣にあるレンダーを再生。
- **統計。** ライブラリ全体を点の雲として表示。軸・大きさ・色に何を割り当てるか選べます。
- **英語と日本語**をアプリ内で切り替え可能（設定 → 言語：システム / English / 日本語）。

## キーボードショートカット

アプリ内の「ヘルプ」（`⌘?`）にも同じ一覧があります。

| | | | |
|---|---|---|---|
| `⌘1` … `⌘4` | ホーム / セット / プラグイン / サンプル | `⌘O` / `Return` | セットを Live で開く |
| `⌘5` | 統計ウィンドウ | `⇧⌘R` | Finder に表示 |
| `⌘F` | 検索 | `⌥⌘P` | レンダー・サンプルの再生 / 一時停止 |
| `⌥⌘F` | フィルター | `Space` | フォーカス中のリストで再生 / 一時停止 |
| `⇧⌘O` | スキャンするフォルダ | `⌘Y` | アレンジメントのプレビュー |
| `⌘R` | 再スキャン | `⌘D` | セットをピン留め |
| `⌘,` | 設定 | `⌘T` | タグとメモ |
| `⌘?` | ヘルプ | `⌥⌘R` | セットをレスキュー |
| `⌃⌘F` / `⌘M` / `⌘Q` | フルスクリーン / しまう / 終了 | `⌘E` | エクスポート（すべてを収集） |
| `⌘N` | Live を起動 | | |

サンプルタブでは、`←` `→` でフォルダを閉じる / 開く、`Space` で試聴、`Return` でフォルダを開く / サンプルをツリーで表示、`⇧Return` で Finder に表示します。

## データ・プライバシー・このアプリがしないこと

- Alive が記憶する内容はすべて `~/Library/Application Support/Alive for Mac` にあります（設定 → データフォルダ）。環境変数 `ALIVE_HOME` で保存先を変更できます。タグとメモは `notes.cfg`、設定は `settings.cfg`、スキャン結果は `index.cache`、サムネイルは `thumbs/` に保存されます。ファイル名と形式は基本的にオリジナルと同じです。
- 元のセットを**変更することは決してありません**。サンプルを**移動・削除することもありません**。レスキューはセットのコピーに対して動作し、エクスポートは新しいフォルダ（または `.zip`）に書き出します。
- ネットワークを使うのは**アップデート確認だけ**です。設定の「アップデートを確認」を押したとき、または「1日1回アップデートを確認する」を有効にしたとき（初期状態は無効）に、このリポジトリの最新リリース情報を GitHub から取得します。あなたやライブラリの情報は送信しません。

## ソースからのビルド

Swift Package（`swift-tools-version:5.10`）です。Xcode 27（Swift 6.4）でのビルドを確認しており、GitHub Actions では `macos-26` ランナーの最新安定版 Xcode でビルドとテストを行います。サードパーティの依存はありません。

```sh
cd macos
swift build                     # デバッグビルド
swift test                      # ユニットテスト
scripts/build-app.sh            # macos/build/ にユニバーサルの「Alive for Mac.app」を作成（ad-hoc 署名）
scripts/build-app.sh --native   # ホストのアーキテクチャのみ（高速）
scripts/build-app.sh --zip      # macos/dist/AliveForMac-<バージョン>.zip も作成
scripts/build-app.sh --dmg      # macos/dist/AliveForMac-<バージョン>.dmg も作成（--zip と併用可）
```

`ALIVE_NO_ACTIVATE=1`、`ALIVE_DEBUG_TAB`、`ALIVE_DEBUG_SHEET` などの環境変数（`macos/Sources/AliveUI/App/DebugLaunch.swift` の冒頭を参照）を使うと、クリックなしで任意の画面を開けます（自動スクリーンショット用）。

## オリジナルの更新の取り込み

このポートはオリジナルのファイルを一切編集しないので、`git merge upstream/main` は常に衝突しません。変更の移植は追跡された作業として行います。`macos/scripts/upstream-sync.sh` が新しいオリジナルのコミットを、対応する Swift ファイル（`macos/upstream-map.tsv`）付きで一覧し、週次のワークフローが移植すべき変更があれば issue を作成します。詳しくは [`macos/docs/UPSTREAM.md`](../macos/docs/UPSTREAM.md) を参照してください。オリジナルとの違いは [`macos/PARITY.md`](../macos/PARITY.md)（英語）にまとめています。

## ライセンス

本プロジェクトは、MIT ライセンスで公開されている **Alive（by RueBlose）** の派生物（ポート）です。

- **オリジナルの Alive**：著作権表示と許諾表示は、リポジトリ直下の [`LICENSE`](../LICENSE) に一切変更せずそのまま保持しています。
- **macOS 版ポート**（`macos/` と `.github/` 以下）：MIT ライセンスです（[`macos/LICENSE`](../macos/LICENSE)）。このファイルには、オリジナルの著作権表示とポートの著作権表示が併記されています。

  ```text
  Original work — Alive, https://github.com/rueblose/alive
  Copyright (c) 2026

  macOS port — Alive for Mac, https://github.com/bassmicrobe/alive-for-mac
  Copyright (c) 2026 takahashitoru (bassmicrobe)
  ```
- **ライセンス文書の同梱**：上記 2 つのライセンス全文と [`macos/NOTICE.md`](../macos/NOTICE.md) は、アプリ内（`Alive for Mac.app/Contents/Resources/`）と DMG に含まれ、アプリの「設定 → 情報」でも表示されます。
- **サードパーティのコード・ライブラリ**：使用していません。Apple のシステムフレームワークと、macOS 標準の zlib のみを使います。
- **非公式であること**：本プロジェクトはオリジナルの作者による制作・確認・承認を受けておらず、関係もありません。
- **商標**：Ableton、Live、Max for Live、Push は Ableton AG の商標です。VST は Steinberg Media Technologies GmbH の商標です。Audio Units、macOS、Finder は Apple Inc. の商標です。本プロジェクトはこれらの企業とは無関係であり、後援・承認を受けていません。

## クレジット

すばらしいオリジナルを公開してくれた RueBlose 氏と [Alive](https://github.com/rueblose/alive) プロジェクトに感謝します。
