# メンテナンス履歴

README から移動したメンテナンス記録です。

## CI ランタイムのメンテナンス (2026-10-22)

checkout アクションを公式の `actions/checkout@v7` (内部 Node.js 24) に更新しました (従来は
v4 / Node.js 20)。macOS アプリは引き続き Swift 製で、アプリケーションに Node ランタイムは
同梱されません。ホステッドの macOS 26 / Ubuntu ランナーは、このアクションの最低ランナー
バージョン 2.327.1 をサポートしています。詳細は
[公式の checkout 移行ノート](https://github.com/actions/checkout/tree/v7) を参照してください。

ビルド / テストのトリガー、リリースタグ・手動ゲート、upstream-watch のスケジュール、権限、
Issue / レポートの挙動に変更はありません。このメンテナンスではリリースの作成、notarization の
実行、upstream Issue 更新の手動トリガーは行っていません。既存の Swift ビルド / テストチェックで
変更を検証しており、リリース公開とスケジュール済みウォッチャーは検証対象として実行していません。
