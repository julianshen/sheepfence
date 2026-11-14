# 監測與 GPS

App 負責定位權限提示與前景生命週期。SheepFence 分別呈現定位來源可用性、目前觀測與歷史確認。

## 選擇定位來源

| 模式 | 定位來源 | App 的責任 |
|---|---|---|
| `.sdkManaged` | SDK 的 Core Location provider | 要求權限，隨前景生命週期啟停 |
| `.hostProvided` | App 既有的定位流程 | 提交定位並回報來源可用性 |

先安裝所需資料集。同一模式重複啟動不會重建工作階段；切換模式前必須停止。`submit` 只允許在已啟動的 host-provided 模式使用。

使用 SDK 管理定位時，請在 Info.plist 加入清楚的 `NSLocationWhenInUseUsageDescription`，並由 App 自行向 Core Location 要求權限。啟動 SDK 不會自動跳出權限提示。

## 啟動前先訂閱

以下函式回傳的 Task 應由應用程式模型保留，在擁有者釋放時取消：

```swift
import SheepFence

@MainActor
func watch(_ client: SheepFenceClient) async throws -> Task<Void, Never> {
    let stream = try await client.events(bufferCapacity: 256)
    return Task { @MainActor in
        do {
            for try await event in stream {
                switch event {
                case .stateSnapshot(let state):
                    print("Initial state:", state)
                case .entered(let evaluation):
                    print("Entered:", evaluation.regionID)
                case .exited(let evaluation):
                    print("Exited:", evaluation.regionID)
                case .evaluated(let batch):
                    print("Current observations:", batch.results)
                default:
                    print("State or dataset change:", event)
                }
            }
        } catch {
            print("Subscription ended:", error)
        }
    }
}
```

在主 actor 模型中啟動與停止：

```swift
let eventTask = try await watch(client)
try await client.startMonitoring(mode: .sdkManaged)

// In your app's foreground lifecycle handler, when leaving the foreground:
await client.stopMonitoring()

// When the subscriber's owner is disposed:
eventTask.cancel()
```

這是生命週期片段，不是要在正式 App 中啟動後立即停止。請序列化生命週期操作，並維持單一擁有者。[完整前景範例（英文）](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) 提供實作參考。停止不會刪除資料集或取消訂閱，但會清除本次觀測並回報 `monitoringStopped`，不會虛構退出事件。

## App 提供 GPS

```swift
try await client.startMonitoring(mode: .hostProvided)
let batch = try await client.submit(location: currentLocation)

// When your source cannot supply a fix:
try await client.updateAvailability(LocationAvailability(reason: .noLocation))

// When source availability returns, report it and submit a fresh fix:
try await client.updateAvailability(LocationAvailability())
let recovered = try await client.submit(location: nextLocation)
```

權限遭拒或定位服務關閉時，請回報對應的 `LocationUnavailableReason`。`reducedAccuracy` 是獨立標記，不代表位於區域外。來源恢復可用也不等於已取得新的有效定位。

## 定位中斷與恢復

中斷時，觀測改為不可用，`lastConfirmed` 保留最後確認的內外狀態與時間。請顯示為歷史資訊，而不是目前位置。恢復後的第一個確認結果會建立新基準，不會推測中斷期間的跨界。

`state()` 以單一一致快照投影目前狀態，包含定位新鮮度。不保證在定位過期時產生計時器事件；UI 應重新讀取狀態或利用時間戳記避免持續顯示過期結果。

## 事件與緩衝

每個訂閱先收到原子性的 `stateSnapshot`，之後依序收到事件。`.evaluated` 表示有狀態的輸入結果；`.baseline` 建立基準；`.entered`、`.exited` 表示已確認跨界。`.datasetChanged` 重新設定變更幾何的基準；`.datasetRemoved` 回報刪除。資料替換或刪除不會產生虛構退出。`.evaluationFailed` 是 provider 路徑的評估錯誤，與匯入呼叫直接拋出的錯誤不同。

每個訂閱使用獨立、有上限的緩衝區，預設 256。過慢的訂閱會以 `eventBufferOverflow` 結束，不影響其他訂閱。重新訂閱可取得目前狀態，但不會重播遺漏事件。請讓事件處理保持輕量，需要持久化紀錄時由 App 自行管理。

## 取樣設定

固定取樣預設要求 10 公尺精度及 10 公尺距離篩選；這是 Core Location 的要求值，不是保證。自適應取樣須明確選擇 `.adaptive(SamplingPolicyConfiguration(...))`，其預設值尚未實地校準。請驗證真實路線的耗電與跨界延遲；SDK 不保證背景監測。
