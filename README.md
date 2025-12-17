# testMeasure

iOS AR 線段測量應用程式

## 功能

- 使用 ARKit 獲取 RGB 圖像和 LiDAR 深度數據
- 使用 OpenCV LSD 算法檢測圖像中的線段
- 使用 LiDAR 深度計算線段的 3D 距離
- 在 AR 畫面中用黃色線段顯示超過 10cm 的線段（最多 10 條）
- 3D 空間繪製線段，跟隨物體移動

## 需求

- iOS 設備（支援 LiDAR：iPhone 12 Pro 及以上、iPad Pro 2020 及以上）
- Xcode 14.0 或更高版本
- OpenCV 框架（需要手動添加到項目中）

## 設置

1. 在 Xcode 中打開項目
2. 添加 OpenCV 框架到項目（參考 OpenCV 官方文檔）
3. 確保 Bridging Header 設置正確：`testMeasure/testMeasure-Bridging-Header.h`
4. 運行項目

## 使用

運行應用程式後，將設備對準要測量的物體，應用程式會自動：
- 檢測線段
- 計算 3D 距離
- 在 AR 畫面中顯示超過 10cm 的線段（黃色）