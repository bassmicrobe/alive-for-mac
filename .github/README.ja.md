<div align="center">

# Alive for Mac

**Ableton Live のプロジェクト・プラグイン・サンプルを素早く一覧できる、macOS ネイティブのカタログアプリ。**

RueBlose 作 [Alive](https://github.com/rueblose/alive) の**非公式 macOS 版ポート**です。

![platform](https://img.shields.io/badge/macOS-14%2B-000000)
![arch](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-native-555555)
![license](https://img.shields.io/badge/license-MIT-blue)

[**ダウンロード**](https://github.com/bassmicrobe/alive-for-mac/releases) · [機能](#機能) · [ショートカット](#キーボードショートカット) · [ビルド](#ソースからのビルド) · [オリジナルとの差分](../macos/PARITY.md) · [English](README.md) · **日本語**

</div>

---

Alive for Mac は Live セット（`.als`）の中身を読み取り、テンポ、キー、プラグイン、サンプル、どれが最新バージョンかを一覧します。
Windows 専用だったオリジナルを Swift / SwiftUI で書き直したもので、ラッパーではありません。
オリジナルの C# ソースは移植の参照として、このリポジトリにそのまま残してあります。

*スクリーンショットは後日追加します（作者自身のライブラリを載せないため）。*

## 動作環境

- macOS 14（Sonoma）以降、Apple Silicon または Intel。
- Ableton Live は必須ではありません。なくてもセットのカタログは使えますが、「Live で開く」は使えません。

## インストール

1. [Releases](https://github.com/bassmicrobe/alive-for-mac/releases) から `AliveForMac-<バージョン>.zip` をダウンロードして展開します。
2. **Alive for Mac.app** を `/Applications` に移動します。
3. このアプリは **ad-hoc 署名のみで公証（notarize）されていない**ため、初回起動が macOS にブロックされます。
   アプリを右クリック →「開く」→「開く」を選ぶか、次のコマンドを実行してください。

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Alive for Mac.app"
   ```
4. ツールバーのフォルダボタンから Live のプロジェクトフォルダを指定し、**スキャン**を押します。

## 機能

- **ホーム。** プロジェクトごとにアレンジメントの絵付きタイル。ピン留め、セットの隣にあるレンダーの再生、1 年分の作業状況（作業した日、連続日数、最長記録、ピーク時間帯）。
- **セット。** テンポ、キー、Live バージョン、トラック数、プラグイン、ファイル、プロジェクトサイズを一目で確認。
  バージョン違い（`v1`、`final`、`final 2`）は 1 行にまとまります。フィルター、検索、列の並べ替え、プロジェクトフォルダに紐づくタグとメモ。新しいセットは自動で現れます。
- **プラグイン。** Audio Unit、VST、VST3 を 1 つのリストに。メーカー、使用セット数、インストール済みかどうか。見つからないプラグインは 1 つずつエラーにせず、落ち着いた状態表示にまとめます。
- **サンプル。** どのサンプルフォルダを実際に使い、どれを一度も使っていないかをプロジェクト単位で集計。未使用・よく使う・重複。クリックで試聴、Live へドラッグ。
- **レスキュー。** セットが開かない？ Live のログからクラッシュしたプラグインを特定するか、セットのコピーでプラグインを 1 つずつ外して原因を探します。元のセットには触れません。
- **エクスポート。** セットに必要なものを 1 つのフォルダまたは `.zip` に集めます（Live の「すべてを収集して保存」に相当）。
- **プレビューとプレーヤー。** アレンジメント全体を Live のクリップ色で表示。セットの隣にあるレンダーを再生。
- **統計。** ライブラリ全体を点の雲として表示。軸・大きさ・色に何を割り当てるか選べます。
- **英語と日本語**をアプリ内で切り替え可能（設定 → 言語：システム / English / 日本語）。

## キーボードショートカット

| | | | |
|---|---|---|---|
| `⌘1` … `⌘4` | ホーム / セット / プラグイン / サンプル | `⌘O` / `Return` | セットを Live で開く |
| `⌘5` | 統計ウィンドウ | `⇧⌘R` | Finder に表示 |
| `⌘F` | 検索 | `Space` | レンダー・サンプルの再生 |
| `⌥⌘F` | フィルター | `⌘Y` | アレンジメントのプレビュー |
| `⇧⌘O` | スキャンするフォルダ | `⌘D` | セットをピン留め |
| `⌘R` | 再スキャン | `⌘T` | タグとメモ |
| `⌘,` | 設定 | `⌥⌘R` | セットをレスキュー |
| `⌘?` | ヘルプ | `⌘E` | エクスポート（すべてを収集） |
| `⌃⌘F` / `⌘M` / `⌘Q` | フルスクリーン / しまう / 終了 | `⌘N` | Live を起動 |

サンプルタブでは、`←` `→` でフォルダを閉じる / 開く、`Space` で試聴、`Return` でフォルダを開く / サンプルをツリーで表示、`⇧Return` で Finder に表示します。

## データ・プライバシー・このアプリがしないこと

- Alive が記憶する内容はすべて `~/Library/Application Support/Alive for Mac` にあります（設定 → データフォルダ）。環境変数 `ALIVE_HOME` で保存先を変更できます。ファイル名と形式はオリジナルと同じです（`settings.cfg`、`notes.cfg`、`index.cache`、`thumbs/` など）。
- サンプルを**移動・削除することは決してありません**。元のセットを**変更することもありません**。レスキューはコピーに対して動作し、エクスポートは新しいフォルダに書き出します。
- ネットワークを使うのは**任意で有効にする**アップデート確認だけです（設定 → アップデート）。このリポジトリの最新リリース情報を GitHub から 1 回取得します。あなたやライブラリの情報は送信しません。

## ソースからのビルド

macOS 14 以降で Xcode 15 以降、または Swift 5.10 ツールチェーンが必要です。サードパーティの依存はありません。

```sh
cd macos
swift build                 # デバッグビルド
swift test                  # ユニットテスト
scripts/build-app.sh        # macos/build/ にユニバーサルの「Alive for Mac.app」を作成（ad-hoc 署名）
scripts/build-app.sh --native   # ホストのアーキテクチャのみ（高速）
scripts/build-app.sh --zip      # macos/dist/AliveForMac-<バージョン>.zip も作成
```

`ALIVE_NO_ACTIVATE=1`、`ALIVE_DEBUG_TAB`、`ALIVE_DEBUG_SHEET` などの環境変数（`macos/Sources/AliveUI/App/DebugLaunch.swift` の冒頭を参照）を使うと、クリックなしで任意の画面を開けます（自動スクリーンショット用）。

## オリジナルの更新の取り込み

このポートはオリジナルのファイルを一切編集しないので、`git merge upstream/main` は常に衝突しません。変更の移植は追跡された作業として行います。`macos/scripts/upstream-sync.sh` が新しいオリジナルのコミットを、対応する Swift ファイル（`macos/upstream-map.tsv`）付きで一覧し、週次のワークフローが移植すべき変更があれば issue を作成します。詳しくは [`macos/docs/UPSTREAM.md`](../macos/docs/UPSTREAM.md) を参照してください。オリジナルとの違いは [`macos/PARITY.md`](../macos/PARITY.md)（英語）にまとめています。

## ライセンスとクレジット

- **Alive** は © RueBlose、MIT ライセンスです：<https://github.com/rueblose/alive>。オリジナルのライセンスはルートの [`LICENSE`](../LICENSE) にそのまま保持しており、アプリ内にも同梱されています。
- **Alive for Mac**（`macos/` と `.github/` 以下すべて）は MIT ライセンスです：[`macos/LICENSE`](../macos/LICENSE)。[`macos/NOTICE.md`](../macos/NOTICE.md) も参照してください。
- 本プロジェクトは非公式のポートです。オリジナルの作者による制作・確認・承認は受けていません。
- Ableton および Live は Ableton AG の商標です。VST は Steinberg Media Technologies GmbH の商標です。Audio Units、macOS、Finder は Apple Inc. の商標です。本プロジェクトはこれらの企業とは無関係であり、後援・承認を受けていません。
