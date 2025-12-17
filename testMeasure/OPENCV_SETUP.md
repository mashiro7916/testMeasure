# OpenCV iOS 設置指南 (OpenCV 4.12)

## 問題：`opencv2/core.hpp not found`

這個錯誤表示 OpenCV 框架沒有正確添加到項目中。

## 你已經下載了 OpenCV 4.12 框架

現在需要將它正確添加到 Xcode 項目中。

## 解決步驟

### 方法 1：使用 CocoaPods（推薦）

1. **安裝 CocoaPods**（如果還沒安裝）：
   ```bash
   sudo gem install cocoapods
   ```

2. **在項目根目錄創建 `Podfile`**：
   ```ruby
   platform :ios, '15.0'
   target 'testMeasure' do
     use_frameworks!
     pod 'OpenCV', '~> 4.8.0'
   end
   ```

3. **安裝依賴**：
   ```bash
   pod install
   ```

4. **打開 `.xcworkspace` 文件**（不是 `.xcodeproj`）：
   ```bash
   open testMeasure.xcworkspace
   ```

### 方法 2：手動添加 OpenCV 4.12 框架（你當前的方法）

1. **你已經下載了 OpenCV 4.12 框架** ✅
   - 確保 `opencv2.framework` 文件完整

2. **添加到 Xcode 項目**：
   - 將 `opencv2.framework` 拖到 Xcode 項目導航器中
   - 選擇 **Copy items if needed**
   - 確保添加到 target: **testMeasure**
   - 點擊 **Finish**

3. **設置 Framework Search Paths**：
   - 選擇項目 → **Build Settings**
   - 搜索 `Framework Search Paths`
   - 添加：`$(PROJECT_DIR)` 或框架所在路徑
   - 確保是 **recursive**（遞歸搜索）

4. **設置 Header Search Paths**（如果需要）：
   - 搜索 `Header Search Paths`
   - 添加：`$(PROJECT_DIR)/opencv2.framework/Headers`

5. **確認框架已鏈接**：
   - 選擇項目 → **Build Phases**
   - 展開 **Link Binary With Libraries**
   - 確認 `opencv2.framework` 在列表中

## 驗證設置

編譯項目，如果沒有錯誤，說明 OpenCV 已正確設置。

## 故障排除

### 問題：`opencv.hpp not found` 或 `opencv2/opencv.hpp not found`

**解決方案 1：檢查 Header Search Paths**
1. 選擇項目 → **Build Settings**
2. 搜索 `Header Search Paths`
3. 確保包含：`$(PROJECT_DIR)/opencv2.framework/Headers`
4. 設置為 **recursive**（遞歸）

**解決方案 2：檢查框架結構**
打開 `opencv2.framework` 文件夾，應該看到：
```
opencv2.framework/
  ├── Headers/
  │   └── opencv2/
  │       ├── core.hpp
  │       ├── imgproc.hpp
  │       └── ...
  └── opencv2 (binary)
```

如果結構不對，可能需要重新下載框架。

**解決方案 3：使用絕對路徑**
如果相對路徑不工作，嘗試使用絕對路徑：
1. 在 Build Settings 中找到 `Header Search Paths`
2. 添加框架的完整路徑，例如：`/Users/YourName/Projects/testMeasure/opencv2.framework/Headers`

**解決方案 4：清理構建**
1. **Product** → **Clean Build Folder** (Shift + Cmd + K)
2. 關閉 Xcode
3. 刪除 DerivedData：`~/Library/Developer/Xcode/DerivedData/testMeasure-*`
4. 重新打開 Xcode 並編譯

## 注意事項

- 如果使用 CocoaPods，必須打開 `.xcworkspace` 而不是 `.xcodeproj`
- OpenCV 框架文件較大（約 100MB+），確保有足夠空間
- 某些 OpenCV 模組（如 stitching）可能與 Swift 有衝突，已通過條件編譯處理
- 確保使用的是 **iOS** 版本的 OpenCV 框架，不是 macOS 版本

