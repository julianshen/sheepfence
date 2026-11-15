# Contributing & documentation

The repository is a Swift Package Manager library with an optional iOS host app. SDK source lives in `Sources/SheepFence`; unit and integration tests live in `Tests/SheepFenceTests`.

## Build and test

On macOS with Swift 6 and Xcode installed:

```sh
swift build
swift test --scratch-path .build/developer
```

Use an isolated scratch path when another developer or agent is running Swift tools in the same checkout. The package targets iOS 16+ and macOS 13+ for engine testing. To run on an installed iOS simulator, first list available destinations, then choose its identifier:

```sh
xcodebuild -showdestinations -scheme SheepFence
xcodebuild test -scheme SheepFence -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID'
```

Use [Examples/ForegroundHost](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) for the signed device host. Do not check in local provisioning credentials or build products.

## Build the developer website

Markdown in `docs/developer` is the source of truth for the website. The renderer rewrites guide links to HTML while preserving Markdown links in the repository. Templates and styles live in `docs/site`; output is disposable under `.build/site`.

```sh
python3 -m venv .build/docs-venv
.build/docs-venv/bin/pip install -r docs/site/requirements.txt
.build/docs-venv/bin/python scripts/build_docs.py
python3 -m http.server 8000 --directory .build/site
```

Open `http://localhost:8000`. The build validates local links and anchors. Preview narrow screens as well as desktop before changing the layout. The site uses local CSS, system fonts and no tracking or external JavaScript.

Pull requests build and validate the site. Pushes to `main` publish it using the repository's GitHub Pages environment. Only the generated site is uploaded, not implementation reports or the entire repository. The workflow follows [GitHub's custom Pages workflow](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages); repository Pages settings must use GitHub Actions.

## Build DocC locally

```sh
xcodebuild docbuild -scheme SheepFence -destination 'generic/platform=iOS' \
  -derivedDataPath .build/documentation CODE_SIGNING_ALLOWED=NO
```

The archive is generated under `.build/documentation/Build/Products/Debug-iphoneos/SheepFence.doccarchive`. Open it in Xcode for symbol-oriented documentation. The Pages site publishes the integration guides; it does not embed this archive.

## Change expectations

Keep public API behavior and examples aligned. Add focused regression coverage for behavior changes, especially snapshot transactions, availability recovery and stream cancellation. Include a minimal reproduction with bug reports. Existing acceptance records describe a particular checkpoint; update evidence only after actually running the corresponding checks.

The current release is v1.0.0 under Apache License 2.0. Use version tags for SDK consumers; `main` remains the development branch. Field acceptance is separate from release testing.

## Translations

English guides remain at the root; Traditional Chinese (`zh-Hant`) and Japanese (`ja`) guides live in matching subdirectories. Keep all three versions aligned when behavior changes. Preserve API identifiers and executable code samples. The language switcher links to the equivalent page, and Fence Studio shares the same local draft across languages.

Editor and site chrome messages live in `docs/site/assets/editor/messages.json`. Use exact message keys or tagged `t` templates with numbered placeholders; never translate user data, IDs or exported GeoJSON keys. Run `node --test scripts/tests/editor-*.test.mjs` and rebuild all 30 pages. Check translated pages and the editor on desktop and mobile before publishing.
