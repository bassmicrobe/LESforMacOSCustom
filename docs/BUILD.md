# 開発・ビルドガイド

LESforMacOS Custom をソースからビルド・テスト・配布する手順です。利用者向けのインストールは [ユーザマニュアル](USER_MANUAL.md) を参照してください。

## 前提条件

- **Xcode** 14.1 以上（Apple Developer アカウントが必要）
- **Homebrew**
- **CocoaPods**
- **Ruby** 3.x

## 依存パッケージ

```bash
# Homebrew パッケージ
brew install coreutils jq xcbeautify gawk gh gpg

# Ruby gems
gem install --user t
gem install trainer
```

`./scripts/build.sh installdeps` でも Homebrew パッケージと Python 依存関係を入れられます（`-r` を付けると Ruby gem `t` も入ります）。

## クローンとセットアップ

```bash
git clone https://github.com/bassmicrobe/LESforMacOSCustom
cd LESforMacOSCustom

pod install
python3 -m pip install --user --require-hashes -r requirements.txt
```

Python 依存はドキュメント生成（Jinja2 など）向けです。ロックファイルは `requirements.txt`、直接依存の指定は `requirements.in` です。

## ビルドと配布

```
ソースコード
  │
  ├─ [開発用] デバッグビルド → .app → そのまま起動して動作確認
  │
  └─ [配布用] リリースビルド → .app → DMG に梱包 → .dmg をユーザーに配布
                                  │                      │
                                  └─ Developer ID 署名・Apple 公証（配布時必須）
                                     Gatekeeper 検証後にのみ公開
```

### デバッグビルド

```bash
XCODE_ARGS="GCC_TREAT_WARNINGS_AS_ERRORS=NO MACOSX_DEPLOYMENT_TARGET=12.0"
xcodebuild -workspace Hammerspoon.xcworkspace -scheme Hammerspoon \
  -configuration Debug ${XCODE_ARGS} clean build | xcbeautify
```

ワークスペースは `Hammerspoon.xcworkspace` を開いてください（`.xcodeproj` 単体では CocoaPods を解決できません）。

### リリースビルド → DMG

**方法 A: ワンコマンド**

```bash
./scripts/release.sh
```

クリーン、ドキュメント生成、Release 構成でのビルド、検証、公証、アーカイブまで実行します。

**方法 B: 手動ステップ**

```bash
./scripts/build.sh clean
./scripts/build.sh docs
./scripts/build.sh build -s Release -c Release
./scripts/build.sh validate

mkdir -p release
cp -R ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release/*.app/ \
  "./Live Enhancement Suite Custom.app/"

hdiutil create -volname "Live Enhancement Suite Custom" \
  -srcfolder "Live Enhancement Suite Custom.app" \
  -ov -format UDZO release/LiveEnhancementSuite.dmg
shasum -a 256 release/LiveEnhancementSuite.dmg > release/LiveEnhancementSuite.dmg.sha256sum
```

`release/LiveEnhancementSuite.dmg` が手動作成時の配布用インストーラーです。GitHub Releases の成果物名は `LiveEnhancementSuiteCustom.dmg` です。

`./scripts/build.sh` のサブコマンド一覧は `./scripts/build.sh -h` を参照してください。

### Apple 公証

App Store 外で配布する場合、macOS Gatekeeper に認識させるため公証を行います。

```bash
# 公証用プロファイルの設定（初回のみ）
xcrun notarytool store-credentials -v \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password APP_SPECIFIC_PASSWORD

# 公証の実行（DMG 作成前に行う）
./scripts/build.sh notarize
```

### GitHub Actions による自動リリース

`release` Environment に次の Secrets を設定してください。

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_ID`
- `APPLE_APP_PASSWORD`

`v*` 形式のタグをプッシュすると、Developer ID 署名、公証、staple、Gatekeeper 検証、DMG 公証がすべて成功した場合に限り GitHub Actions が公開します。Secrets が未設定、または検証が失敗した場合は公開しません。

```bash
git tag v1.0.0
git push origin v1.0.0
```

ワークフローの詳細: [`.github/workflows/les_release.yml`](../.github/workflows/les_release.yml)

## テスト

Docker を使ってローカル環境を汚さずに Lua テストを実行できます。イメージには Lua 5.4、busted、luacheck が含まれます。

```bash
# イメージをビルドして全テスト実行（luacheck + busted）
docker build -f Dockerfile.test -t les-test .
docker run --rm les-test

# busted テストのみ
docker run --rm les-test busted extensions/les/tests/

# luacheck 静的解析のみ
docker run --rm les-test luacheck extensions/les/

# コンテナ内でシェルを開く
docker run --rm -it les-test /bin/sh
```

テストファイルは `extensions/les/tests/` に `*_spec.lua` の命名規則で配置します。`hs` API はテスト内でモックします。

Hammerspoon 拡張・コアへのコントリビューション手順は [CONTRIBUTING.md](../CONTRIBUTING.md) を参照してください。
