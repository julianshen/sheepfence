# 參與開發與文件

SDK 原始碼在 `Sources/SheepFence`，測試在 `Tests/SheepFenceTests`；專案使用 Swift Package Manager，另附 iOS 測試主程式。

## 建置與測試

在安裝 Swift 6 與 Xcode 的 macOS 執行：

```sh
swift build
swift test --scratch-path .build/developer
```

多人或代理程式同時操作時請使用不同暫存路徑。支援 iOS 16+；macOS 13+ 用於引擎測試。先列出模擬器目的地，再填入可用的識別碼：

```sh
xcodebuild -showdestinations -scheme SheepFence
xcodebuild test -scheme SheepFence -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID'
```

實機主程式見 [Examples/ForegroundHost](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost)。請勿提交簽署憑證或建置產物。

## 建置文件網站

`docs/developer` 的 Markdown 是網站來源，`zh-Hant` 與 `ja` 分別保存繁體中文及日文。模板與樣式在 `docs/site`，輸出在可刪除的 `.build/site`。

```sh
python3 -m venv .build/docs-venv
.build/docs-venv/bin/pip install -r docs/site/requirements.txt
.build/docs-venv/bin/python scripts/build_docs.py
python3 -m http.server 8000 --directory .build/site
```

開啟 `http://localhost:8000`。建置會檢查所有語言的本機連結與錨點。修改版面時請檢查桌面與窄螢幕。指南使用本機 CSS 與系統字型，沒有追蹤程式。

Pull request 會建置驗證；推送至 `main` 後由 GitHub Pages 發布，僅上傳生成的網站。儲存庫 Pages 設定應使用 GitHub Actions。

## 本機 DocC

```sh
xcodebuild docbuild -scheme SheepFence -destination 'generic/platform=iOS' \
  -derivedDataPath .build/documentation CODE_SIGNING_ALLOWED=NO
```

輸出在 `.build/documentation/Build/Products/Debug-iphoneos/SheepFence.doccarchive`，可用 Xcode 開啟。Pages 發布整合指南，不包含此封存檔。

## 變更要求

保持公開 API、程式範例及三種語言一致；API 名稱與程式碼不翻譯。介面翻譯位於 `docs/site/assets/editor/messages.json`。新增行為時加入針對性的回歸測試，特別注意快照交易、位置恢復及串流取消。錯誤回報應附最小重現。僅在實際執行驗證後更新測試證據。

目前版本為 v1.0.0，採用 Apache License 2.0。SDK 使用者應選用版本標籤；`main` 為開發分支。實地驗收與發布測試分別處理。
