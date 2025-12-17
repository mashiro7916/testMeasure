# 手動添加 opencv2.framework 到 Xcode 項目

## 問題：在 Link Binary With Libraries 中找不到 opencv2.framework

這表示框架文件存在，但沒有正確添加到 Xcode 項目中。

## 解決方法：手動添加框架

### 方法 1：從文件系統添加（推薦）

1. **找到 opencv2.framework 的位置**
   - 可能在下載文件夾、桌面或其他位置
   - 記住完整路徑

2. **在 Xcode 中添加**：
   - 在 Xcode 左側項目導航器中，**右鍵點擊項目名稱**（最上方的藍色圖標）
   - 選擇 **Add Files to "testMeasure"...**
   - 瀏覽到 `opencv2.framework` 的位置
   - **重要設置**：
     - ✅ 勾選 **Copy items if needed**（如果框架不在項目目錄中）
     - ✅ 選擇 **Create groups**（不是 Create folder references）
     - ✅ 在 **Add to targets** 中勾選 **testMeasure**
   - 點擊 **Add**

3. **驗證框架已添加**：
   - 在項目導航器中應該能看到 `opencv2.framework`
   - 展開它應該能看到 `Headers` 文件夾

### 方法 2：拖放添加

1. **打開 Finder**，找到 `opencv2.framework` 文件夾

2. **拖放到 Xcode**：
   - 將 `opencv2.framework` 從 Finder **拖到** Xcode 左側項目導航器
   - 拖到項目名稱下方（與其他文件同一層級）
   - 會彈出對話框

3. **在對話框中設置**：
   - ✅ 勾選 **Copy items if needed**
   - ✅ 選擇 **Create groups**
   - ✅ 在 **Add to targets** 中勾選 **testMeasure**
   - 點擊 **Finish**

### 方法 3：添加到 Link Binary With Libraries（如果框架已在項目中）

如果框架已經在項目導航器中，但 Link Binary With Libraries 中找不到：

1. **在項目導航器中找到 opencv2.framework**
2. **選擇它**（單擊）
3. **在右側 File Inspector 中**（右側面板，第一個標籤）：
   - 找到 **Target Membership**
   - ✅ 確保 **testMeasure** 已勾選

4. **然後在 Build Phases 中添加**：
   - 選擇項目 → **Build Phases**
   - 展開 **Link Binary With Libraries**
   - 點擊 `+`
   - 在彈出窗口中，切換到 **Add Other...** → **Add Files...**
   - 瀏覽到項目中的 `opencv2.framework`
   - 選擇並添加

### 驗證框架是否正確添加

1. **在項目導航器中**：
   - 應該能看到 `opencv2.framework`
   - 展開後應該有 `Headers` 文件夾

2. **在 Build Phases → Link Binary With Libraries**：
   - 應該能看到 `opencv2.framework`
   - 狀態應該是 **Required**

3. **在 Build Settings → Framework Search Paths**：
   - 應該包含 `$(PROJECT_DIR)` 或框架的實際路徑

## 如果還是找不到

### 檢查框架是否完整

1. 在 Finder 中右鍵點擊 `opencv2.framework`
2. 選擇 **顯示包內容**
3. 應該看到：
   ```
   opencv2.framework/
     ├── Headers/
     │   └── opencv2/
     │       ├── core.hpp
     │       └── ...
     └── opencv2 (這是二進制文件)
   ```

如果結構不對，可能需要重新下載框架。

### 檢查框架版本

確保下載的是 **iOS** 版本的 OpenCV 框架，不是 macOS 版本。

## 完成後

1. **清理構建**：Product → Clean Build Folder (Shift + Cmd + K)
2. **重新編譯**：Cmd + B

鏈接錯誤應該會消失。

