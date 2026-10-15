# Alive for Mac 0.3.1

2026-10-15 — パフォーマンス・UI/UX 改善

- **ファイル変更の自動反映を修正。** 通常起動で監視が始まらない問題を直し、セットの保存・追加を一覧へ自動反映します。開いているフィルターの候補も更新されます。
- **スキャンの応答性とデータ保護。** 起動時の変更履歴の読み取りに件数の上限とキャンセルを追加。大量の変更は全件スキャンへ切り替えます。途中のフォルダを読めない場合は、プロジェクト・サンプルとも前回の一覧を保持します。
- **Spotlight・ウィジェット更新を整理。** 不要になった処理を停止し、古い結果が最新の内容を上書きすることを防ぎます。
- **Quick Look の描画欠けを修正。** 多数のトラックも画像の大きさを抑えながら最後まで表示します。
- **一覧と状態表示を改善。** 多数のピン留め・不明フォルダをスクロールでき、主要な操作を画面内に保ちます。サンプルの未接続表示、入力欄の読み上げ名、拡張機能の状態と再確認を改善しました。
- **Finder タグを保護。** ドライブ未接続中も Alive が付けたタグの記録を保持し、再接続後もご自身で付けたタグと区別します。

**検証:** Apple Silicon / macOS 27.0.1 で991テスト、失敗0件、環境依存の11件をスキップ。日本語の実画面で保存後の自動更新、フィルター、未接続表示と大量項目のスクロールを確認しました。詳細と未確認の実機条件は[監査レポート](PERFORMANCE_UIUX_AUDIT_2026-10-15.md)を参照してください。

**配布:** `AliveForMac-0.3.1.dmg` / `.zip`。macOS 14以降、Apple Silicon・Intel両対応。ad-hoc署名、公証なし。通常の設定・カタログの保存先は従来どおりです。Quick Look とウィジェットの利用には、アプリ設定からの有効化が必要です。

---

## English

Performance and UI/UX improvements:

- Restore automatic catalog refresh when sets are saved or added; open filter choices follow catalog updates.
- Bound startup change-history replay and make obsolete scans cancelable. Preserve previous project and sample catalogs when a subtree cannot be read.
- Cancel superseded Spotlight work and order widget publication so older results cannot overwrite newer content.
- Fit complete Quick Look arrangements within the image budget, including the final track.
- Keep long pin and missing-folder lists scrollable, improve offline indicators and accessibility labels, and clarify extension status and rechecking.
- Preserve Alive's Finder-tag ownership while a drive is offline, keeping personal tags separate after reconnection.

**Validation:** 991 tests, zero failures, 11 environment-dependent skips on Apple Silicon / macOS 27.0.1. Native Japanese UI checks covered automatic file-change refresh, filters, offline indicators and long lists. See the [audit report](PERFORMANCE_UIUX_AUDIT_2026-10-15.md) for scope and remaining hardware checks.

**Downloads:** `AliveForMac-0.3.1.dmg` and `.zip`; macOS 14+, universal Apple Silicon / Intel. Ad-hoc signed, not notarized. Existing settings and catalog storage remain compatible. Quick Look and the widget require one-time enabling in Settings.

MIT. Both license texts and `NOTICE.md` are included in the app and DMG. This is an unofficial port of Alive by RueBlose; it is not affiliated with the original author or Ableton.
