# 開発への参加とドキュメント

Swift Package Manager のライブラリで、任意の iOS ホストアプリを含みます。ソースは `Sources/SheepFence`、テストは `Tests/SheepFenceTests` にあります。

## ビルドとテスト

Swift 6 と Xcode を導入した macOS で実行します。

```sh
swift build
swift test --scratch-path .build/developer
```

他の開発者やエージェントと同時に作業する場合は別々の scratch path を使います。iOS 16+ に対応し、エンジンのテストは macOS 13+ でも実行できます。シミュレーター一覧から使用する ID を選びます。

```sh
xcodebuild -showdestinations -scheme SheepFence
xcodebuild test -scheme SheepFence -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID'
```

実機用ホストは [Examples/ForegroundHost](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) を使います。署名情報やビルド生成物をコミットしないでください。

## サイトのビルド

`docs/developer` の Markdown が原本です。`zh-Hant` は繁体字中国語、`ja` は日本語です。テンプレートとスタイルは `docs/site`、削除可能な出力は `.build/site` にあります。

```sh
python3 -m venv .build/docs-venv
.build/docs-venv/bin/pip install -r docs/site/requirements.txt
.build/docs-venv/bin/python scripts/build_docs.py
python3 -m http.server 8000 --directory .build/site
```

`http://localhost:8000` を開きます。ビルドは全言語のローカルリンクとアンカーを検証します。画面変更時はデスクトップと狭い画面を確認してください。ガイドはローカル CSS とシステムフォントを使用し、追跡は行いません。

Pull request でビルドと検証を行い、`main` への push で GitHub Pages に公開します。生成したサイトのみをアップロードします。リポジトリの Pages 設定では GitHub Actions を選択してください。

## ローカル DocC

```sh
xcodebuild docbuild -scheme SheepFence -destination 'generic/platform=iOS' \
  -derivedDataPath .build/documentation CODE_SIGNING_ALLOWED=NO
```

出力は `.build/documentation/Build/Products/Debug-iphoneos/SheepFence.doccarchive` です。Xcode で開いてシンボルの資料を確認できます。Pages は統合ガイドを公開し、このアーカイブは含めません。

## 変更時の注意

公開 API、コード例、3 言語の内容を一致させます。API 名とコードは翻訳しません。UI の翻訳は `docs/site/assets/editor/messages.json` にあります。特にスナップショットのトランザクション、位置の回復、ストリームのキャンセルに関する変更には回帰テストを追加してください。問題報告には最小の再現例を添え、検証記録は実際に確認した後に更新します。

本ソフトウェアはプレリリースです。バージョンタグ、ライセンス、現地での受け入れ確認は個別のリリース判断です。
