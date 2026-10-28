<div align="center">

<img src="docs/img/icon transparent.png" width="96" alt="Alive">

# Alive

**Ableton Live のプロジェクト・プラグイン・サンプルを一覧できる、高速でポータブルなカタログ。**

`.exe` ひとつだけ。インストーラーも外部 DLL もランタイムのダウンロードも不要。

![version](https://img.shields.io/badge/version-1.3-2ea043)
![platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078d4)
![framework](https://img.shields.io/badge/.NET%20Framework-4.6%2B-512BD4)
![license](https://img.shields.io/badge/license-MIT-blue)

[**ダウンロード**](../../releases) · [Русский](README.ru.md)

<img src="docs/img/home.png" alt="Alive — ホーム画面">

</div>

---

## 概要

数年 Live を使うと、何十ものフォルダに何百もの `.als` と、プロジェクトごとのバックアップの山が
残ります。Explorer に見えるのは名前と日付だけ。Alive はセット自体を開き、中身 — テンポ、キー、
プラグイン、サンプル、どれが最新バージョンか — を表示します。

主な機能:

- **ホーム** — プロジェクトごとにアレンジメントのサムネイル付きタイルを表示。スターで先頭に固定、
  再生ボタンでセット横のレンダーを再生。タイルの上には「あなたの 1 年」(作業日数、連続記録、
  開始時刻の傾向、ライブラリの総容量) を表示。
- **Sets** — セットの情報 (テンポ、キー、Live バージョン、トラック数、プラグイン、ファイル、
  フォルダサイズ) を一覧。`v1` / `final` / `final 2` は 1 行に折りたたみ。フィルタ (`F`)、
  検索 (`Ctrl F`)、タグとメモ (`Ctrl T`) に対応。新しいセットは再スキャン不要で自動的に現れます。
- **Plugins** (`Ctrl 3`) — 全プラグインを一覧: メーカー、使用セット数、インストール状況。
  リストは Live 自身のプラグインデータベース、または VST2/VST3 フォルダから取得。
- **Samples** (`Ctrl 4`) — 実際に使っているパックと、一度も使っていないパックを集計。
  使用数はプロジェクト単位 (同じ曲の 10 バージョンは 1 とカウント)。未使用・最頻使用・重複の
  一覧、クリックで試聴、Live へのドラッグに対応。Alive がサンプルを移動・削除することはありません。
- **Rescue** (`Ctrl R`) — セットが開かない? Live のログからクラッシュ原因のプラグインを特定。
  ログに手がかりがなければ、セットのコピーでプラグインを順に無効化して自力で犯人を見つけます。
  元のセットには一切触れません。
- **Export** — セットに必要なもの (サンプル、他プロジェクトのファイル、User Library、パック) を
  1 つのフォルダまたは `.zip` に収集。Live の *Collect All and Save* 相当。
- **プレビューとプレイヤー** — `Ctrl Space` でアレンジメント全体を Live のクリップ色で 1 枚絵に。
  `Space` でセット横のレンダーを再生。
- **Stat** — ライブラリ全体を点群として可視化 (1 点 = 1 プロジェクト)。軸・点サイズ・色に
  テンポ、トラック数、年などを割り当て可能。

<img src="docs/img/sets.png" alt="Sets 一覧とプロジェクトパネル">

**プライバシー:** Alive がオンラインになるのは自分から要求したときだけ (**Check for updates**
または日次チェックを有効化した場合)。あなたやライブラリに関する情報は一切送信されません。

## 技術スタック

- **言語 / フレームワーク:** C# (WinForms)、.NET Framework 4.6+ (Windows 10 / 11 に同梱)
- **ビルド:** .NET Framework 4.x 付属の C# コンパイラのみ。IDE も追加インストールも不要
- **macOS 版:** `macos/` に Swift によるネイティブ移植あり (詳細は [macos/PARITY.md](macos/PARITY.md))

## セットアップ

1. [Releases](../../releases) からアーカイブを取得して展開。
2. `Alive.exe` を実行。
3. Ableton のプロジェクトフォルダを指定して **Scan**。

必要なのは **.NET Framework 4.6+** のみ (Windows 10 / 11 に同梱)。

### ソースからビルド

```cmd
build.cmd
```

`bin\Alive.exe` が生成されます。

### キーボードショートカット

| | | | |
|---|---|---|---|
| `F1` | ヘルプ | `Enter` | Live でセットを開く |
| `Ctrl 1` … `Ctrl 4` | Home / Sets / Plugins / Samples | `Shift Enter` | Explorer で表示 |
| `F` | フィルタ | `Space` | レンダー / サンプルを再生 |
| `Shift F` | フォルダをスキャン | `Ctrl Space` | アレンジメントプレビュー |
| `Ctrl F` | 検索 | `Q` | セットをピン留め |
| `Ctrl ,` | 設定 | `Ctrl T` | タグとメモ |
| `F11` / `Ctrl M` | フルスクリーン / 最小化 | `Ctrl R` | セットをレスキュー |
| `Ctrl Q` | 終了 | `F5` | 再スキャン |
| | | `Ctrl N` | Live を起動 |

### トラブルシューティング

1. **「Windows によって PC が保護されました」** — コード署名していないため SmartScreen が
   警告します。**詳細情報 → 実行** をクリック。
2. **アンチウイルスが検知する** — Alive はファイルコピーとアーカイブ書き込みを行うため、
   一部のスキャナーが疑います。誤検知です: コードは全てこのリポジトリにあり、1 コマンドで
   ビルドできます。フォルダを除外設定に追加してください。
3. **起動直後に閉じる** — ダウンロードやメッセンジャー経由で入手した場合、`Alive.exe` を
   右クリック → **プロパティ** → **ブロックの解除** にチェック → OK。
4. **プラグインが表示されない / 一部だけ** — リストは Live のデータベース由来のため、Live を
   一度は起動している必要があります。それでも空なら Live の **Preferences → Plug-Ins → Rescan**、
   または Alive の設定で VST フォルダのスキャンを有効に。
5. **その他** — `%APPDATA%\Alive\alive.log` を送ってください。直近の実行内容が記録されています。

### データフォルダ

Alive が記憶する内容はすべて `%APPDATA%\Alive` にあります (**Settings → Data folder**)。
レジストリを含め他の場所には何も書きません。フォルダを削除すれば完全リセットです。
`activity.cache` (作業履歴) と `notes.cfg` (タグとメモ) だけは再構築できないので先に退避を。
ポータブル運用などで場所を変えたい場合は、起動前に環境変数 `ALIVE_HOME` にフォルダを設定します。

## 構成

| パス | 内容 |
|---|---|
| `src/` | カタログ本体 (C# / WinForms)。エントリポイントは `src/Program.cs` |
| `nebula/` | Stat (ライブラリ全体の散布図) |
| `macos/` | Swift による macOS 移植 |
| `tools/` | テスト・スクリーンショット・SVG 書き出し用スクリプト |
| `build.cmd` | Windows 版のビルドスクリプト |

## ドキュメント

- [FORMAT.md](FORMAT.md) — `.als` フォーマットの解析結果 (実セット 427 個に基づく)。Live を
  開かずにセットを読める理由がここにあります。
- [macos/PARITY.md](macos/PARITY.md) — macOS 版と Windows 版の機能パリティ。
- [docs/maintenance.md](docs/maintenance.md) — CI ランタイムなどのメンテナンス履歴。

## ライセンス

[MIT](LICENSE)
