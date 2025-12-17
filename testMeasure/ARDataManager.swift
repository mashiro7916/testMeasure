//
//  ARDataManager.swift
//  testMeasure
//
//  Created by jacky72503 on 2025/12/15.
//

import Foundation
import ARKit
import UIKit
import AVFoundation
import CoreVideo
import Accelerate

// Line segment data structure for Swift
struct DetectedLine: Identifiable {
    let id: Int
    let x1: Float
    let y1: Float
    let x2: Float
    let y2: Float
    
    var length2D: Float {
        return sqrtf((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    }
}

// Depth accuracy statistics
struct DepthAccuracyStats {
    let meanError: Float          // Mean absolute error (meters)
    let rmse: Float               // Root mean square error (meters)
    let maxError: Float           // Maximum error (meters)
    let minError: Float           // Minimum error (meters)
    let validPoints: Int          // Number of valid comparison points
    let alignmentScale: Float     // Computed scale factor
    let alignmentShift: Float     // Computed shift factor
}

class ARDataManager: ObservableObject {
    private var frameCount: Int = 0
    private let depthModelManager = DepthModelManager()
    private let processInterval: Int = 10  // Process every 10 frames for smoother UI
    
    // Camera intrinsics for 3D projection
    private var cameraIntrinsics: simd_float3x3?
    private var imageResolution: CGSize = .zero
    
    // Published properties for UI
    @Published var displayImage: UIImage?
    @Published var detectedLines: [DetectedLine] = []
    @Published var selectedLineIndex: Int = -1
    @Published var measuredLength: Float = 0.0  // in meters
    @Published var isProcessing: Bool = false
    
    // Depth visualization
    @Published var alignedDepthImage: UIImage?      // Aligned depth map visualization
    @Published var lidarDepthImage: UIImage?       // LiDAR depth map visualization
    @Published var errorHeatMap: UIImage?          // Error heat map (aligned - LiDAR)
    @Published var showDepthComparison: Bool = false
    
    // Depth data
    private var absoluteDepthMap: [Float]?  // Aligned absolute depth (meters)
    private var lidarDepthMapResampled: [Float]?  // LiDAR depth resampled to depth map resolution
    private var depthWidth: Int = 0
    private var depthHeight: Int = 0
    
    init() {
        print("DEBUG: ARDataManager initialized")
    }
    
    func captureFrame(frame: ARFrame) {
        frameCount += 1
        
        // Only process every N frames
        if frameCount % processInterval != 0 {
            return
        }
        
        // Store camera intrinsics
        cameraIntrinsics = frame.camera.intrinsics
        let pixelBuffer = frame.capturedImage
        imageResolution = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        
        // Get LiDAR depth if available
        let lidarDepth = frame.sceneDepth?.depthMap
        
        // Convert YUV to RGB
        guard let rgbBuffer = convertYUVToRGB(pixelBuffer) else {
            print("DEBUG: Failed to convert YUV to RGB")
            return
        }
        
        // Run Depth Anything model
        depthModelManager.estimateDepth(from: rgbBuffer) { [weak self] relativeDepthMap in
            guard let self = self, let relativeDepth = relativeDepthMap else {
                return
            }
            
            // Align depth maps (LiDAR + Depth Anything)
            self.alignDepthMaps(lidarDepth: lidarDepth, relativeDepth: relativeDepth)
            
            // Generate depth visualizations
            self.generateDepthVisualizations()
            
            // Detect lines and update UI
            if let rgbImage = self.pixelBufferToUIImage(rgbBuffer) {
                self.detectAndDisplayLines(image: rgbImage)
            }
        }
    }
    
    // MARK: - Depth Alignment (Scale-Shift)
    
    private func alignDepthMaps(lidarDepth: CVPixelBuffer?, relativeDepth: CVPixelBuffer) {
        let relWidth = CVPixelBufferGetWidth(relativeDepth)
        let relHeight = CVPixelBufferGetHeight(relativeDepth)
        
        depthWidth = relWidth
        depthHeight = relHeight
        
        // Extract relative depth values
        CVPixelBufferLockBaseAddress(relativeDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(relativeDepth, .readOnly) }
        
        guard let relBase = CVPixelBufferGetBaseAddress(relativeDepth) else { return }
        let relBytesPerRow = CVPixelBufferGetBytesPerRow(relativeDepth)
        let relBuffer = relBase.assumingMemoryBound(to: Float32.self)
        
        var relativeValues: [Float] = []
        for y in 0..<relHeight {
            let rowStart = relBuffer.advanced(by: y * (relBytesPerRow / MemoryLayout<Float32>.size))
            for x in 0..<relWidth {
                relativeValues.append(rowStart[x])
            }
        }
        
        // If LiDAR available, compute scale and shift
        var scale: Float = 1.0
        var shift: Float = 0.0
        
        if let lidar = lidarDepth {
            let (s, sh) = computeScaleShift(lidarDepth: lidar, relativeDepth: relativeValues, relWidth: relWidth, relHeight: relHeight)
            scale = s
            shift = sh
            print("DEBUG: Depth alignment - scale: \(scale), shift: \(shift)")
        } else {
            // No LiDAR: use heuristic (assume depth range 0.5m - 5m)
            let minRel = relativeValues.min() ?? 0
            let maxRel = relativeValues.max() ?? 1
            let range = maxRel - minRel
            if range > 0 {
                scale = 4.5 / range  // Map to 0.5m - 5m range
                shift = 0.5 - minRel * scale
            }
            print("DEBUG: No LiDAR - using heuristic depth scaling")
        }
        
        // Apply scale and shift to get absolute depth
        absoluteDepthMap = relativeValues.map { $0 * scale + shift }
        
        // Resample LiDAR depth to depth map resolution for comparison
        if let lidar = lidarDepth {
            lidarDepthMapResampled = resampleLidarDepth(lidarDepth: lidar, targetWidth: relWidth, targetHeight: relHeight)
        } else {
            lidarDepthMapResampled = nil
        }
    }
    
    // MARK: - Depth Visualization
    
    private func generateDepthVisualizations() {
        guard let alignedDepth = absoluteDepthMap, depthWidth > 0 && depthHeight > 0 else {
            return
        }
        
        // Generate aligned depth visualization
        alignedDepthImage = createDepthVisualization(depthMap: alignedDepth, width: depthWidth, height: depthHeight, title: "Aligned Depth")
        
        // Generate LiDAR depth visualization if available
        if let lidarDepth = lidarDepthMapResampled {
            lidarDepthImage = createDepthVisualization(depthMap: lidarDepth, width: depthWidth, height: depthHeight, title: "LiDAR Depth")
            
            // Generate error heat map
            errorHeatMap = createErrorHeatMap(alignedDepth: alignedDepth, lidarDepth: lidarDepth, width: depthWidth, height: depthHeight)
        } else {
            lidarDepthImage = nil
            errorHeatMap = nil
        }
    }
    
    private func resampleLidarDepth(lidarDepth: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> [Float] {
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly) }
        
        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        
        guard let lidarBase = CVPixelBufferGetBaseAddress(lidarDepth) else {
            return []
        }
        
        let lidarBytesPerRow = CVPixelBufferGetBytesPerRow(lidarDepth)
        let lidarBuffer = lidarBase.assumingMemoryBound(to: Float32.self)
        let lidarRowBytes = lidarBytesPerRow / MemoryLayout<Float32>.size
        
        var resampled: [Float] = []
        resampled.reserveCapacity(targetWidth * targetHeight)
        
        for ty in 0..<targetHeight {
            for tx in 0..<targetWidth {
                // Map target coordinates to LiDAR coordinates
                let lx = Int(Float(tx) / Float(targetWidth) * Float(lidarWidth))
                let ly = Int(Float(ty) / Float(targetHeight) * Float(lidarHeight))
                
                let lidarIdx = min(ly, lidarHeight - 1) * lidarRowBytes + min(lx, lidarWidth - 1)
                let lidarValue = lidarBuffer[lidarIdx]
                
                // Use valid LiDAR value, or 0 if invalid
                if lidarValue > 0 && lidarValue <= 10 && !lidarValue.isNaN && !lidarValue.isInfinite {
                    resampled.append(lidarValue)
                } else {
                    resampled.append(0)  // Invalid depth
                }
            }
        }
        
        return resampled
    }
    
    private func createDepthVisualization(depthMap: [Float], width: Int, height: Int, title: String) -> UIImage? {
        guard depthMap.count == width * height else { return nil }
        
        // Find valid depth range
        let validDepths = depthMap.filter { $0 > 0 && $0 <= 10 }
        guard let minDepth = validDepths.min(), let maxDepth = validDepths.max(), maxDepth > minDepth else {
            return nil
        }
        
        // Create color image from depth map
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        for (index, depth) in depthMap.enumerated() {
            let offset = index * bytesPerPixel
            
            if depth > 0 && depth <= 10 {
                // Normalize depth to 0-1 range
                let normalized = (depth - minDepth) / (maxDepth - minDepth)
                
                // Use colormap: blue (near) -> green -> yellow -> red (far)
                let (r, g, b) = depthToColor(normalized)
                pixels[offset] = b
                pixels[offset + 1] = g
                pixels[offset + 2] = r
                pixels[offset + 3] = 255  // Alpha
            } else {
                // Invalid depth: black
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImage = context.makeImage() else {
            return nil
        }
        
        let image = UIImage(cgImage: cgImage)
        
        // Add title text to image
        return addTextToImage(image: image, text: title)
    }
    
    private func createErrorHeatMap(alignedDepth: [Float], lidarDepth: [Float], width: Int, height: Int) -> UIImage? {
        guard alignedDepth.count == lidarDepth.count && alignedDepth.count == width * height else {
            return nil
        }
        
        // Calculate errors
        var errors: [Float] = []
        errors.reserveCapacity(alignedDepth.count)
        
        for i in 0..<alignedDepth.count {
            let aligned = alignedDepth[i]
            let lidar = lidarDepth[i]
            
            // Only calculate error for valid depths
            if aligned > 0 && aligned <= 10 && lidar > 0 && lidar <= 10 {
                errors.append(abs(aligned - lidar))
            } else {
                errors.append(-1)  // Invalid
            }
        }
        
        // Find error range
        let validErrors = errors.filter { $0 >= 0 }
        guard let minError = validErrors.min(), let maxError = validErrors.max(), maxError > minError else {
            return nil
        }
        
        // Create heat map: green (low error) -> yellow -> red (high error)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        for (index, error) in errors.enumerated() {
            let offset = index * bytesPerPixel
            
            if error >= 0 {
                // Normalize error to 0-1 range
                let normalized = (error - minError) / (maxError - minError)
                
                // Heat map colormap: green -> yellow -> red
                let (r, g, b) = errorToColor(normalized)
                pixels[offset] = b
                pixels[offset + 1] = g
                pixels[offset + 2] = r
                pixels[offset + 3] = 255
            } else {
                // Invalid: black
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImage = context.makeImage() else {
            return nil
        }
        
        let image = UIImage(cgImage: cgImage)
        
        // Add title and error range
        let errorText = String(format: "Error: %.3f - %.3f m", minError, maxError)
        return addTextToImage(image: image, text: "Error Heat Map\n\(errorText)")
    }
    
    private func depthToColor(_ normalizedDepth: Float) -> (UInt8, UInt8, UInt8) {
        // Colormap: blue (near) -> cyan -> green -> yellow -> red (far)
        let value = max(0.0, min(1.0, normalizedDepth))
        
        if value < 0.25 {
            // Blue to Cyan
            let t = value / 0.25
            return (0, UInt8(t * 255), 255)
        } else if value < 0.5 {
            // Cyan to Green
            let t = (value - 0.25) / 0.25
            return (0, 255, UInt8((1.0 - t) * 255))
        } else if value < 0.75 {
            // Green to Yellow
            let t = (value - 0.5) / 0.25
            return (UInt8(t * 255), 255, 0)
        } else {
            // Yellow to Red
            let t = (value - 0.75) / 0.25
            return (255, UInt8((1.0 - t) * 255), 0)
        }
    }
    
    private func errorToColor(_ normalizedError: Float) -> (UInt8, UInt8, UInt8) {
        // Heat map: green (low error) -> yellow -> red (high error)
        let value = max(0.0, min(1.0, normalizedError))
        
        if value < 0.5 {
            // Green to Yellow
            let t = value / 0.5
            return (UInt8(t * 255), 255, 0)
        } else {
            // Yellow to Red
            let t = (value - 0.5) / 0.5
            return (255, UInt8((1.0 - t) * 255), 0)
        }
    }
    
    private func addTextToImage(image: UIImage, text: String) -> UIImage? {
        let size = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // Draw original image
        image.draw(in: CGRect(origin: .zero, size: size))
        
        // Draw text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: 10,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    private func computeScaleShift(lidarDepth: CVPixelBuffer, relativeDepth: [Float], relWidth: Int, relHeight: Int) -> (Float, Float) {
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly) }
        
        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        
        guard let lidarBase = CVPixelBufferGetBaseAddress(lidarDepth) else {
            print("DEBUG: Failed to get LiDAR base address")
            return (1.0, 0.0)
        }
        
        let lidarBytesPerRow = CVPixelBufferGetBytesPerRow(lidarDepth)
        let lidarBuffer = lidarBase.assumingMemoryBound(to: Float32.self)
        
        // Collect corresponding points for least squares
        var sumX: Double = 0  // relative depth
        var sumY: Double = 0  // lidar depth
        var sumXX: Double = 0
        var sumXY: Double = 0
        var count: Int = 0
        
        // Sample points from LiDAR depth map
        // Use adaptive sampling: more samples for better accuracy
        let sampleStep = 2  // Sample every 2nd pixel for better accuracy
        
        for ly in stride(from: 0, to: lidarHeight, by: sampleStep) {
            for lx in stride(from: 0, to: lidarWidth, by: sampleStep) {
                let lidarRowBytes = lidarBytesPerRow / MemoryLayout<Float32>.size
                let lidarIdx = ly * lidarRowBytes + lx
                
                guard lidarIdx >= 0 && lidarIdx < (lidarHeight * lidarRowBytes) else {
                    continue
                }
                
                let lidarValue = lidarBuffer[lidarIdx]
                
                // Skip invalid depth values (LiDAR typically has range 0.1m - 10m)
                if lidarValue <= 0.05 || lidarValue > 10.0 || lidarValue.isNaN || lidarValue.isInfinite {
                    continue
                }
                
                // Map LiDAR coordinates to relative depth coordinates
                // Both are in camera space, so simple linear mapping should work
                let rx = Int(Float(lx) / Float(lidarWidth) * Float(relWidth))
                let ry = Int(Float(ly) / Float(lidarHeight) * Float(relHeight))
                
                if rx >= 0 && rx < relWidth && ry >= 0 && ry < relHeight {
                    let relIdx = ry * relWidth + rx
                    
                    guard relIdx < relativeDepth.count else {
                        continue
                    }
                    
                    let relValue = relativeDepth[relIdx]
                    
                    if !relValue.isNaN && !relValue.isInfinite && relValue > 0 {
                        sumX += Double(relValue)
                        sumY += Double(lidarValue)
                        sumXX += Double(relValue) * Double(relValue)
                        sumXY += Double(relValue) * Double(lidarValue)
                        count += 1
                    }
                }
            }
        }
        
        print("DEBUG: Depth alignment - collected \(count) valid point pairs")
        
        // Least squares: y = scale * x + shift
        // Solving: scale = (n*sumXY - sumX*sumY) / (n*sumXX - sumX*sumX)
        //          shift = (sumY - scale*sumX) / n
        if count > 20 {  // Need at least 20 points for reliable estimation
            let n = Double(count)
            let denom = n * sumXX - sumX * sumX
            if abs(denom) > 1e-6 {
                // Calculate scale and shift in Double precision first
                let scaleDouble = (n * sumXY - sumX * sumY) / denom
                let shiftDouble = (sumY - scaleDouble * sumX) / n
                // Convert to Float at the end
                let scale = Float(scaleDouble)
                let shift = Float(shiftDouble)
                
                // Validate results
                if scale > 0 && scale < 100 && abs(shift) < 10 {
                    print("DEBUG: Depth alignment successful - scale: \(scale), shift: \(shift), samples: \(count)")
                    return (scale, shift)
                } else {
                    print("DEBUG: Depth alignment produced invalid values - scale: \(scale), shift: \(shift)")
                }
            }
        } else {
            print("DEBUG: Insufficient samples for depth alignment (\(count) < 20)")
        }
        
        return (1.0, 0.0)
    }
    
    // MARK: - Line Detection
    
    private func detectAndDisplayLines(image: UIImage) {
        // Detect lines using LSD
        let lines = OpenCVWrapper.detectLines(image)
        
        // Convert to Swift struct
        var swiftLines: [DetectedLine] = []
        for (index, line) in lines.enumerated() {
            swiftLines.append(DetectedLine(
                id: index,
                x1: line.x1,
                y1: line.y1,
                x2: line.x2,
                y2: line.y2
            ))
        }
        
        // Sort by length (longest first)
        swiftLines.sort { $0.length2D > $1.length2D }
        
        // Keep top 20 lines
        let topLines = Array(swiftLines.prefix(20))
        
        // Draw lines on image
        let linesArray = NSMutableArray()
        for line in topLines {
            let segment = LineSegment()
            segment.x1 = line.x1
            segment.y1 = line.y1
            segment.x2 = line.x2
            segment.y2 = line.y2
            linesArray.add(segment)
        }
        
        let drawnImage = OpenCVWrapper.drawLines(image, lines: linesArray as! [LineSegment], selectedIndex: selectedLineIndex)
        
        DispatchQueue.main.async {
            self.detectedLines = topLines
            self.displayImage = drawnImage
        }
    }
    
    // MARK: - Line Selection and Measurement
    
    func selectLine(at index: Int) {
        guard index >= 0 && index < detectedLines.count else { return }
        
        selectedLineIndex = index
        let line = detectedLines[index]
        
        // Calculate 3D length
        let length = calculate3DLength(line: line)
        
        DispatchQueue.main.async {
            self.measuredLength = length
            
            // Redraw with selection
            if let image = self.displayImage {
                let linesArray = NSMutableArray()
                for l in self.detectedLines {
                    let segment = LineSegment()
                    segment.x1 = l.x1
                    segment.y1 = l.y1
                    segment.x2 = l.x2
                    segment.y2 = l.y2
                    linesArray.add(segment)
                }
                self.displayImage = OpenCVWrapper.drawLines(image, lines: linesArray as! [LineSegment], selectedIndex: index)
            }
        }
        
        print("DEBUG: Selected line \(index), 3D length: \(length) meters")
    }
    
    func selectLineNear(point: CGPoint, imageSize: CGSize) {
        // Find the closest line to the tap point
        // Note: detectedLines coordinates are in original image space, not depth map space
        var minDistance: Float = Float.greatestFiniteMagnitude
        var closestIndex = -1
        
        // Get current lines (thread-safe access)
        let currentLines = detectedLines
        
        // Calculate scale from displayed image to original image
        // The displayed image might be scaled, so we need to account for that
        // For simplicity, assume the image is displayed at its original size or scaled proportionally
        let scaleX = Float(imageResolution.width) / Float(imageSize.width)
        let scaleY = Float(imageResolution.height) / Float(imageSize.height)
        let scaledPoint = CGPoint(
            x: CGFloat(Float(point.x) * scaleX),
            y: CGFloat(Float(point.y) * scaleY)
        )
        
        for (index, line) in currentLines.enumerated() {
            let distance = pointToLineDistance(
                point: scaledPoint,
                x1: line.x1, y1: line.y1,
                x2: line.x2, y2: line.y2
            )
            
            if distance < minDistance {
                minDistance = distance
                closestIndex = index
            }
        }
        
        // Select if close enough (within 50 pixels in original image space)
        // Convert threshold to original image space
        let threshold = Float(50.0) * max(scaleX, scaleY)
        if closestIndex >= 0 && minDistance < threshold {
            selectLine(at: closestIndex)
        }
    }
    
    private func pointToLineDistance(point: CGPoint, x1: Float, y1: Float, x2: Float, y2: Float) -> Float {
        let px = Float(point.x)
        let py = Float(point.y)
        
        let dx = x2 - x1
        let dy = y2 - y1
        let lengthSq = dx * dx + dy * dy
        
        if lengthSq == 0 {
            return sqrtf((px - x1) * (px - x1) + (py - y1) * (py - y1))
        }
        
        var t = ((px - x1) * dx + (py - y1) * dy) / lengthSq
        t = max(0, min(1, t))
        
        let projX = x1 + t * dx
        let projY = y1 + t * dy
        
        return sqrtf((px - projX) * (px - projX) + (py - projY) * (py - projY))
    }
    
    private func calculate3DLength(line: DetectedLine) -> Float {
        guard let depthMap = absoluteDepthMap,
              let intrinsics = cameraIntrinsics,
              depthWidth > 0 && depthHeight > 0,
              imageResolution.width > 0 && imageResolution.height > 0 else {
            print("DEBUG: Cannot calculate 3D length - missing data")
            return 0
        }
        
        // Scale line coordinates from original image to depth map resolution
        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)
        
        // Map line endpoints to depth map coordinates
        let dx1 = Int(line.x1 * scaleX)
        let dy1 = Int(line.y1 * scaleY)
        let dx2 = Int(line.x2 * scaleX)
        let dy2 = Int(line.y2 * scaleY)
        
        // Clamp to valid range
        let clampedX1 = max(0, min(depthWidth - 1, dx1))
        let clampedY1 = max(0, min(depthHeight - 1, dy1))
        let clampedX2 = max(0, min(depthWidth - 1, dx2))
        let clampedY2 = max(0, min(depthHeight - 1, dy2))
        
        // Get depth values at endpoints
        let idx1 = clampedY1 * depthWidth + clampedX1
        let idx2 = clampedY2 * depthWidth + clampedX2
        
        guard idx1 < depthMap.count && idx2 < depthMap.count else {
            print("DEBUG: Depth map index out of range - idx1: \(idx1), idx2: \(idx2), count: \(depthMap.count)")
            return 0
        }
        
        let depth1 = depthMap[idx1]
        let depth2 = depthMap[idx2]
        
        // Skip if depth values are invalid
        if depth1 <= 0 || depth2 <= 0 || depth1.isNaN || depth2.isNaN || depth1.isInfinite || depth2.isInfinite {
            print("DEBUG: Invalid depth values - D1: \(depth1)m, D2: \(depth2)m")
            return 0
        }
        
        // Scale intrinsics to depth map resolution
        // Camera intrinsics are in original image coordinates, need to scale to depth map
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        
        // Validate intrinsics
        guard fx > 0 && fy > 0 else {
            print("DEBUG: Invalid camera intrinsics - fx: \(fx), fy: \(fy)")
            return 0
        }
        
        // Unproject 2D points to 3D using camera intrinsics
        // Formula: X = (u - cx) * Z / fx, Y = (v - cy) * Z / fy, Z = depth
        let x1_3d = (Float(clampedX1) - cx) * depth1 / fx
        let y1_3d = (Float(clampedY1) - cy) * depth1 / fy
        let z1_3d = depth1
        
        let x2_3d = (Float(clampedX2) - cx) * depth2 / fx
        let y2_3d = (Float(clampedY2) - cy) * depth2 / fy
        let z2_3d = depth2
        
        // Calculate 3D Euclidean distance
        let dx = x2_3d - x1_3d
        let dy = y2_3d - y1_3d
        let dz = z2_3d - z1_3d
        
        let length = sqrtf(dx * dx + dy * dy + dz * dz)
        
        print("DEBUG: 3D points - P1(\(x1_3d), \(y1_3d), \(z1_3d)) P2(\(x2_3d), \(y2_3d), \(z2_3d))")
        print("DEBUG: Depths - D1: \(depth1)m, D2: \(depth2)m, Length: \(length)m")
        
        return length
    }
    
    // MARK: - Helper Functions
    
    private func convertYUVToRGB(_ yuvBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(yuvBuffer)
        let height = CVPixelBufferGetHeight(yuvBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(yuvBuffer)
        
        if pixelFormat == kCVPixelFormatType_32BGRA || pixelFormat == kCVPixelFormatType_32ARGB {
            return yuvBuffer
        }
        
        var rgbBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &rgbBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = rgbBuffer else {
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: yuvBuffer)
        let context = CIContext()
        context.render(ciImage, to: outputBuffer)
        
        return outputBuffer
    }
    
    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

