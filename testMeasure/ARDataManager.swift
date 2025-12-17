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
    
    // Depth data
    private var absoluteDepthMap: [Float]?  // Aligned absolute depth (meters)
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
    }
    
    private func computeScaleShift(lidarDepth: CVPixelBuffer, relativeDepth: [Float], relWidth: Int, relHeight: Int) -> (Float, Float) {
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly) }
        
        let lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        let lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        
        guard let lidarBase = CVPixelBufferGetBaseAddress(lidarDepth) else {
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
        let sampleStep = 4  // Sample every 4th pixel for speed
        
        for ly in stride(from: 0, to: lidarHeight, by: sampleStep) {
            for lx in stride(from: 0, to: lidarWidth, by: sampleStep) {
                let lidarIdx = ly * (lidarBytesPerRow / MemoryLayout<Float32>.size) + lx
                let lidarValue = lidarBuffer[lidarIdx]
                
                // Skip invalid depth values
                if lidarValue <= 0 || lidarValue > 10 || lidarValue.isNaN || lidarValue.isInfinite {
                    continue
                }
                
                // Map LiDAR coordinates to relative depth coordinates
                let rx = Int(Float(lx) / Float(lidarWidth) * Float(relWidth))
                let ry = Int(Float(ly) / Float(lidarHeight) * Float(relHeight))
                
                if rx >= 0 && rx < relWidth && ry >= 0 && ry < relHeight {
                    let relIdx = ry * relWidth + rx
                    let relValue = relativeDepth[relIdx]
                    
                    if !relValue.isNaN && !relValue.isInfinite {
                        sumX += Double(relValue)
                        sumY += Double(lidarValue)
                        sumXX += Double(relValue) * Double(relValue)
                        sumXY += Double(relValue) * Double(lidarValue)
                        count += 1
                    }
                }
            }
        }
        
        // Least squares: y = scale * x + shift
        if count > 10 {
            let n = Double(count)
            let denom = n * sumXX - sumX * sumX
            if abs(denom) > 1e-6 {
                let scale = Float((n * sumXY - sumX * sumY) / denom)
                let shift = Float((sumY - scale * sumX) / n)
                return (scale, shift)
            }
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
        var minDistance: Float = Float.greatestFiniteMagnitude
        var closestIndex = -1
        
        // Scale point to depth map coordinates
        let scaleX = Float(depthWidth) / Float(imageSize.width)
        let scaleY = Float(depthHeight) / Float(imageSize.height)
        let scaledPoint = CGPoint(x: CGFloat(Float(point.x) * scaleX), y: CGFloat(Float(point.y) * scaleY))
        
        for (index, line) in detectedLines.enumerated() {
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
        
        // Select if close enough (within 30 pixels)
        if closestIndex >= 0 && minDistance < 30 {
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
              depthWidth > 0 && depthHeight > 0 else {
            return 0
        }
        
        // Scale line coordinates to depth map resolution
        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)
        
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
        let depth1 = depthMap[clampedY1 * depthWidth + clampedX1]
        let depth2 = depthMap[clampedY2 * depthWidth + clampedX2]
        
        // Scale intrinsics to depth map resolution
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        
        // Unproject to 3D
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
        print("DEBUG: Depths - D1: \(depth1)m, D2: \(depth2)m")
        
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

