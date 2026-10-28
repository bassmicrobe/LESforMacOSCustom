# LESforMacOS Custom

**Ableton Live の操作をショートカットとマクロで拡張する macOS アプリです。**

## 概要

[LESforMacOS](https://github.com/LiveEnhancementSuite/LESforMacOS) のフォークです。アプリ名は **Live Enhancement Suite Custom** で、[Hammerspoon](https://github.com/Hammerspoon/hammerspoon) 上の [Lua スクリプト](extensions/les) により Ableton Live の操作を拡張します。

Ableton Live が前面にあるときだけショートカットが有効になり、他のアプリに切り替えると自動で無効化されます。

| 機能 | 説明 | デフォルトキー |
|------|------|---------------|
| ピアノロールマクロ | ピアノロール操作の自動化 | `` ` `` |
| MIDIクリップ作成 | 新規 MIDI クリップを作成 | `Cmd+Shift+M` |
| プロジェクトバージョニング | 新バージョンとして保存 | `Cmd+Alt+S` |
| マーカー作成 | ロケーターマーカーを作成 | `Shift+L` |
| ウィンドウ管理 | 前面または全プラグインウィンドウを閉じる | `Cmd+W` / `Cmd+Alt+W` |
| プラグイン検索 | Spotlight 風検索とお気に入り | `Cmd+Shift+H` |
| ショートカット一覧 | 全ショートカットのオーバーレイ | `Cmd+Shift+/` |
| AI アシスタント | 音楽制作向けチャット（OpenAI） | `Cmd+Shift+A` |
| カスタムメニュー | メニューバーからの操作 | メニューバー |
| プラグインメニュー設定 | カテゴリ別メニューを GUI で編集 | メニューバー |
| プラグインスキャン | VST3 / AU を検出してメニューを生成 | メニューバー |
| プロジェクトメモ | プロジェクト単位のタイムラインメモ | メニューバー |
| トラックメモ | トラック単位のメモ | メニューバー |
| AI プラグイン提案 | 使用統計ベースの推薦 | メニューバー |
| AI トラック名生成 | トラック名の提案 | メニューバー |
| macOS 通知連携 | エクスポート完了 / 作業時間通知 | 自動 |

オリジナル LES との差分は [機能比較表](docs/FEATURE_COMPARISON.md) を参照してください。

## 技術スタック

- Lua 5.4.7（`LuaSkin/lua-5.4.7/` に組み込み。LES スクリプトロジック）
- Objective-C（Hammerspoon コア）
- C++（LuaSkin・ネイティブ拡張）
- Python 3（ドキュメント生成。Jinja2 / mistune / pygments）
- Xcode 14.1 以上 / CocoaPods
- Docker + [busted](https://github.com/lunarmodules/busted) + luacheck（Lua テスト・静的解析）

## セットアップ

### 動作要件

| 項目 | 要件 |
|------|------|
| macOS | 12 (Monterey) 〜 26 |
| Ableton Live | 9 〜 15 |

### インストール

1. [最新リリース](https://github.com/bassmicrobe/LESforMacOSCustom/releases/latest) から `LiveEnhancementSuiteCustom.dmg` をダウンロードする
2. DMG を開き、指示に従ってインストールする
3. アプリを起動し、**システム設定 → プライバシーとセキュリティ → アクセシビリティ** で許可する

### ソースからビルド

前提は **Xcode 14.1 以上**（Apple Developer アカウントが必要）、**Homebrew**、**CocoaPods**、**Ruby 3.x** です。

```bash
git clone https://github.com/bassmicrobe/LESforMacOSCustom
cd LESforMacOSCustom
pod install
python3 -m pip install --user --require-hashes -r requirements.txt
```

デバッグビルド:

```bash
XCODE_ARGS="GCC_TREAT_WARNINGS_AS_ERRORS=NO MACOSX_DEPLOYMENT_TARGET=12.0"
xcodebuild -workspace Hammerspoon.xcworkspace -scheme Hammerspoon \
  -configuration Debug ${XCODE_ARGS} clean build | xcbeautify
```

Lua テスト（Docker）:

```bash
docker build -f Dockerfile.test -t les-test .
docker run --rm les-test
```

依存関係のインストール、リリースビルド、公証、GitHub Actions による配布、テストの詳細は [開発・ビルドガイド](docs/BUILD.md) を参照してください。

## 使い方

Ableton Live が前面にあるときだけショートカットが有効になります。他のアプリに切り替えると自動で無効化されます。`Cmd+Shift+1` で一時停止／再開できます。

設定は `~/.les/settings.ini` に保存されます（メニューバーの設定 GUI でも変更できます）。OpenAI API キーを含む設定ファイルはパーミッション `600`（所有者のみ読み書き可）で保存されます。

ショートカット・設定項目の詳細は [ユーザマニュアル](docs/USER_MANUAL.md) を参照してください。

## 構成

```
LESforMacOSCustom/
├── Hammerspoon/              # コアアプリケーション (Objective-C)
├── LuaSkin/                  # Lua ランタイムラッパー
│   └── lua-5.4.7/            # 組み込み Lua
├── extensions/               # Hammerspoon 拡張モジュール
│   └── les/                  # Live Enhancement Suite Custom 本体
│       ├── LESmain.lua       # エントリーポイント
│       ├── settings.lua      # 設定システム
│       ├── ai/               # AI 機能 (OpenAI API)
│       ├── shortcuts/        # キーボードショートカット
│       ├── menus/            # メニューバー UI・設定 GUI
│       ├── tracking/         # タイマー・通知・メモ・統計
│       └── tests/            # busted テスト
├── docs/                     # ドキュメント
├── scripts/                  # ビルド・リリース・テスト
├── Hammerspoon.xcworkspace/  # Xcode ワークスペース
├── Dockerfile.test           # Lua テスト用 Docker
└── LICENSE                   # MIT ライセンス
```

設定とジャンプスタート用の `init.lua` は `~/.les` に置かれ、コアロジックはアプリバンドル内の `Contents/Resources/extensions/hs/les`（ソースツリーでは `extensions/les`）にあります。

## ドキュメント

- [ユーザマニュアル](docs/USER_MANUAL.md) — インストール、ショートカット、設定リファレンス
- [機能比較表](docs/FEATURE_COMPARISON.md) — オリジナル LES との差分
- [アーキテクチャ](docs/ARCHITECTURE.md) — GUI・モジュール構成・データフロー
- [開発・ビルドガイド](docs/BUILD.md) — 依存関係、ビルド、公証、テスト
- [変更履歴](CHANGELOG.md) — このフォークでの変更点

## ライセンス

MIT License。再配布・改変の際は、各パーツの著作権表示と MIT ライセンス本文を含めてください。

- LES スクリプト（`extensions/les/`）— [COPYING.txt](extensions/les/COPYING.txt) / [AUTHORS.txt](extensions/les/AUTHORS.txt)
- Hammerspoon コア（`Hammerspoon/`、`LuaSkin/` など）— ルート [LICENSE](LICENSE)
- 組み込み Lua（`LuaSkin/lua-5.4.7/`）— [Lua.org / PUC-Rio](https://www.lua.org/)
- 本フォークの追加・改変 — MIT License（ルート [LICENSE](LICENSE) に従う）

オリジナルの [Live Enhancement Suite for macOS](https://github.com/LiveEnhancementSuite/LESforMacOS)、[Hammerspoon](https://github.com/Hammerspoon/hammerspoon)、[Lua](https://www.lua.org/) の作者・貢献者に感謝します。
