# OpenCV 頭文件找不到 - 修復步驟

## 問題
`opencv2/core.hpp not found` 錯誤

## 可能原因
1. `opencv2.framework` 不在項目目錄中
2. Xcode 緩存問題
3. 項目設置被重置

## 修復步驟

### 1. 確認 opencv2.framework 位置
確保 `opencv2.framework` 在項目根目錄：
```
testMeasure/
  ├── opencv2.framework/  ← 應該在這裡
  ├── testMeasure/
  └── testMeasure.xcodeproj/
```

### 2. 在 Xcode 中檢查設置

#### A. Framework Search Paths
1. 選擇項目（藍色圖標）
2. 選擇 Target "testMeasure"
3. Build Settings
4. 搜索 "Framework Search Paths"
5. 確保包含：
   - `$(PROJECT_DIR)`
   - `$(PROJECT_DIR)/**`
   - 設置為 **recursive**

#### B. Header Search Paths
1. 在 Build Settings 中搜索 "Header Search Paths"
2. 確保包含：
   - `$(PROJECT_DIR)/opencv2.framework/Headers`
   - `$(PROJECT_DIR)/**`
   - 設置為 **recursive**

#### C. Link Binary With Libraries
1. 選擇 Target "testMeasure"
2. Build Phases
3. Link Binary With Libraries
4. 確認 `opencv2.framework` 在列表中
5. 如果沒有，點擊 `+` 添加

### 3. 清理構建
1. Product → Clean Build Folder (Shift + Cmd + K)
2. 關閉 Xcode
3. 刪除 DerivedData：
   - `~/Library/Developer/Xcode/DerivedData/testMeasure-*`
4. 重新打開 Xcode

### 4. 如果 opencv2.framework 不存在
需要下載並添加到項目：
1. 下載 OpenCV for iOS (4.12)
2. 解壓縮
3. 將 `opencv2.framework` 複製到項目根目錄
4. 在 Xcode 中右鍵項目 → Add Files to "testMeasure"
5. 選擇 `opencv2.framework`
6. 確保勾選 "Copy items if needed" 和 Target "testMeasure"

### 5. 驗證設置
在 Terminal 中運行：
```bash
ls -la opencv2.framework/Headers/core.hpp
```
應該能找到文件。

## 快速修復（如果框架存在但找不到）
1. 在 Xcode 中：File → Workspace Settings
2. 將 Build System 改為 "Legacy Build System"
3. Clean Build Folder
4. 重新構建

如果還是不行，改回 "New Build System"。

