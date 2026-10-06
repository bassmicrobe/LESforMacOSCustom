# セキュリティ・パフォーマンス・UI/UX監査（2026-10-05）

基点は `6ef1a98b`、ブランチは `codex/audit-ui-ux-security-performance`。
前回の未コミット修正を保持したまま、現在の LES 実装と更新用依存部品を監査した。
開始時からある `.claude/settings.local.json` の削除は変更していない。
監査完了時点では、commit、push、実アプリの入れ替え・起動、OS権限変更、実OpenAI通信は行っていない。

## 今回の修正

- AI通信：上流のエラー本文にはAPIキーや送信内容が含まれ得るため、そのまま画面・ログへ渡さず、HTTP状態と許可したエラー種別から安全な定型文を返す。
- 設定：不正な型、0/1以外のトグル、小数の整数項目、負値、非有限値を拒否。不正な保存要求は全体を拒否し、ディスクとメモリを変更しない。
- 設定の読み取り失敗：元ファイルや動作中の設定を上書きしない。読み取れない既存ファイルも新規ファイル扱いにしない。設定の読み取り・初期化失敗時のリロードでは既存メニューを保持する。
- バックアップ：ネイティブのディレクトリ列挙APIが返す状態と終了処理を保持し、権限適用・古いバックアップ整理を実行できるようにする。
- 共通保存：書き込み・flush・close失敗時は一時ファイルの削除を試み、元ファイルへ置換しない。入力ファイルのclose失敗も成功と判定しない。
- VST3：大きいメタデータに対する全体パターン走査を抑え、最大12件と8msの処理予算で続きを次のタイマーへ渡す。予算は各エントリ処理後に確認するため、1ファイルの読み取り・分類全体や各回の占有時間を8ms以下に保証する変更ではない。
- プラグイン追記：逆順挿入による二次的な配列移動を線形の配列結合へ変更。終端判定を限定し、`Endorphin`等の名前を終端として扱わない。`End ;comment`との互換性を維持する。
- メニュー：カンマを含む名前・検索語・親子カテゴリが途中で切れる問題を修正。公開の診断文字列とini形式は維持し、内部の行データだけを構造化する。
- 日本語入力：IME変換中のEnter/Cmd+Enterでは送信・トラック切替を行わない。通常の送信操作と改行は維持する。
- AI推薦：画面の読み込み完了を待って初回要求を開始。古い画面や重複した読み込み完了通知からは開始しない。
- メモ：未保存入力があるプロジェクト切替には破棄確認を追加。取消、保存中、JavaScriptの判定失敗では旧画面と旧保存先を保持。古い確認応答は適用しない。
- CI：実際の埋め込みJavaScriptを使うキーボード・切替確認テストを追加する。

## 更新部品のセキュリティ

Sparkleを `2.6.4` から `2.9.6` に更新し、Podfile・lock・このリポジトリで管理している配布部品を同期した。他のPodの版は変更していない。

旧版は公開されたインストーラーのシンボリックリンク関連脆弱性の影響範囲に含まれる。現在のアプリでは自動確認が無効・更新フィードが空であり、通常の自動更新で悪用されたと確認したわけではない。
修正済み版への更新は [公式リリース](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6)、影響条件は [更新先パスの検証問題](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5) と [root実行時のキャッシュ処理問題](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-4v99-qgq9-6pxp) に基づく。

## 検証

- 変更前：Lua 177件成功、静的解析57警告・0エラー。
- 各変更は関連する回帰テストで、問題が再現する状態から修正後の成功まで確認した。
- ローカルLua 5.5で分類キーを含まない4MiBの合成文字列を12回分類したCPU参考測定は約1033msから約4.6ms。アプリ内Lua 5.4.7・実プラグイン環境の性能向上幅を示す測定ではない。
- 統合Luaテスト：225件成功、0失敗・0エラー。AIの成功/拒否/異常応答、設定と保存の失敗時の非変更、メニュー構築、非同期処理、メモの保存先を検証。
- 実埋め込みJavaScriptテスト：20件成功。IME入力、通常ショートカット、改行、保存中の切替拒否、破棄確認を検証。追加依存なしのNode標準テスト。
- 静的解析：57警告・0エラー。変更前の警告数を維持し、既存の許容上限62以内。
- 自前ソースの差分チェックとPodfile構文チェックに成功。配布部品の上流由来空白は下記の境界として扱う。
- Sparkle 2.9.6を独立した検証プロセスで読み込み、既存コードが利用するSUUpdaterの7つのクラス/インスタンスメソッドが存在することを確認。更新処理のインスタンス生成・通信・インストールは行っていない。
- 更新元の `Pods/Sparkle/Sparkle.framework` のdeep/strict署名検証に成功。
- XcodeのReleaseスキーム・Release構成で、署名なしarm64ビルドに成功（終了コード0、`BUILD SUCCEEDED`）。生成アプリ内の本体実行ファイルがarm64、同梱Sparkleが2.9.6であることを確認した。
- 生成アプリに含まれる本番用Lua 47ファイルのSHA-256が、監査完了時点のソースとすべて一致した。

検証コマンド：

```sh
docker run --rm -v "$PWD:/app:ro" -w /app les-test:latest sh scripts/run-lua-tests.sh
node --test extensions/les/tests/ui_keyboard_spec.mjs
git diff --check -- . ':!Pods/**'
ruby -c Podfile
codesign --verify --deep --strict Pods/Sparkle/Sparkle.framework
xcodebuild -workspace Hammerspoon.xcworkspace -scheme Release \
  -configuration Release -destination platform=macOS \
  -derivedDataPath /tmp/les-audit-20261005 -jobs 2 \
  MACOSX_DEPLOYMENT_TARGET=12.0 GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

## 確認範囲の境界

- 実際のAbleton LiveとWKWebViewを接続したE2E、macOSの実IME・確認ダイアログ、実API通信は未実施。モックのLua API契約と実埋め込みJavaScriptの動作を検証した。
- Xcodeビルドはインストール済みアプリと別の一時出力先で実行し、起動・反映はしない。
- 配布用の署名・公証・x86_64ビルドは未検証。CocoaPodsの同梱処理はヘッダ等を除外するが、今回は再署名を無効にしたため、生成アプリ内Sparkleの署名検証は欠落した署名対象リソースを理由に不成功となる。更新元の配布frameworkの署名成功とは区別し、この検証用アプリを配布可能な署名済み成果物として扱わない。
- 新しいSparkle配布ヘッダに上流由来の末尾空白がある。署名付き配布部品を改変せず、自前ソースの差分チェックとは区別する。
- ネイティブ拡張・全同梱ライブラリの網羅的なソース監査、実機のCPU/応答時間測定、プロジェクト全体80%カバレッジの証明は今回の検証に含まない。
- 実際のAPIキー流出を確認したわけではなく、利用者の設定・過去ログから資格情報を取得していない。過去のログに実キーが残っていた場合の失効・再発行は別途必要。
