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
    let length3D: Float  // 3D length in meters
    let point3D1: simd_float3  // 3D position of endpoint 1 (in camera coordinate system)
    let point3D2: simd_float3  // 3D position of endpoint 2 (in camera coordinate system)
    
    var length2D: Float {
        return sqrtf((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    }
}

class ARDataManager: ObservableObject {
    private var frameCount: Int = 0
    private let processInterval: Int = 10  // Process every 10 frames for smoother UI
    
    // Camera intrinsics for 3D projection
    private var cameraIntrinsics: simd_float3x3?
    @Published var currentFrame: ARFrame?  // Store current frame for coordinate transformation
    
    // Published properties for UI
    @Published var detectedLines: [DetectedLine] = []  // Only lines > 10cm
    @Published var imageResolution: CGSize = .zero
    @Published var displayImage: UIImage?  // RGB image with lines drawn
    
    // LiDAR depth data
    private var lidarDepthMap: [Float]?
    private var lidarWidth: Int = 0
    private var lidarHeight: Int = 0
    
    init() {
        print("DEBUG: ARDataManager initialized")
    }
    
    func captureFrame(frame: ARFrame) {
        frameCount += 1
        
        // Only process every N frames
        if frameCount % processInterval != 0 {
            return
        }
        
        // Store camera intrinsics and current frame
        cameraIntrinsics = frame.camera.intrinsics
        let pixelBuffer = frame.capturedImage
        let resolution = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        
        DispatchQueue.main.async {
            self.imageResolution = resolution
            self.currentFrame = frame
        }
        
        // Get LiDAR depth if available
        let lidarDepth = frame.sceneDepth?.depthMap
        
        // Convert YUV to RGB
        guard let rgbBuffer = convertYUVToRGB(pixelBuffer) else {
            print("DEBUG: Failed to convert YUV to RGB")
            return
        }
        
        // Extract and store LiDAR depth
        if let lidar = lidarDepth {
            extractLidarDepth(lidarDepth: lidar)
        }
        
        // Detect lines and calculate 3D distances
        if let rgbImage = pixelBufferToUIImage(rgbBuffer) {
            detectLinesAndCalculateDistance(image: rgbImage)
        }
    }
    
    // MARK: - LiDAR Depth Extraction
    
    private func extractLidarDepth(lidarDepth: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly) }
        
        lidarWidth = CVPixelBufferGetWidth(lidarDepth)
        lidarHeight = CVPixelBufferGetHeight(lidarDepth)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(lidarDepth)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(lidarDepth) else {
            return
        }
        
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let rowBytes = bytesPerRow / MemoryLayout<Float32>.size
        
        var depthValues: [Float] = []
        depthValues.reserveCapacity(lidarWidth * lidarHeight)
        
        for y in 0..<lidarHeight {
            let rowStart = buffer.advanced(by: y * rowBytes)
            for x in 0..<lidarWidth {
                depthValues.append(rowStart[x])
            }
        }
        
        lidarDepthMap = depthValues
        print("DEBUG: Extracted LiDAR depth: \(lidarWidth)x\(lidarHeight)")
    }
    
    // MARK: - Line Detection and Distance Calculation
    
    private func detectLinesAndCalculateDistance(image: UIImage) {
        // Detect lines using LSD
        let lines = OpenCVWrapper.detectLines(image)
        
        guard let lidarDepth = lidarDepthMap, let intrinsics = cameraIntrinsics,
              lidarWidth > 0 && lidarHeight > 0 else {
            print("DEBUG: No LiDAR depth available for distance calculation")
            return
        }
        
        // Capture image resolution on current thread to avoid race condition
        let currentResolution = imageResolution
        
        guard currentResolution.width > 0 && currentResolution.height > 0 else {
            print("DEBUG: Invalid image resolution")
            return
        }
        
        // Convert to Swift struct and calculate 3D distances
        var swiftLines: [DetectedLine] = []
        for (index, line) in lines.enumerated() {
            let result = calculate3DCoordinates(
                x1: line.x1, y1: line.y1,
                x2: line.x2, y2: line.y2,
                lidarDepth: lidarDepth,
                intrinsics: intrinsics,
                imageResolution: currentResolution
            )
            
            // Only keep lines longer than 10cm (0.1 meters)
            if result.length > 0.1 {
                swiftLines.append(DetectedLine(
                    id: index,
                    x1: line.x1,
                    y1: line.y1,
                    x2: line.x2,
                    y2: line.y2,
                    length3D: result.length,
                    point3D1: result.point1,
                    point3D2: result.point2
                ))
            }
        }
        
        // Sort by 3D length (longest first)
        swiftLines.sort { $0.length3D > $1.length3D }
        
        // Keep only top 10 lines (all must be > 10cm)
        let topLines = Array(swiftLines.prefix(10))
        
        print("DEBUG: Detected \(lines.count) lines, \(swiftLines.count) lines > 10cm, keeping top \(topLines.count) lines")
        if !topLines.isEmpty {
            print("DEBUG: First line 3D points: p1=\(topLines[0].point3D1), p2=\(topLines[0].point3D2), length=\(topLines[0].length3D)m")
        }
        
        // Draw lines on the image
        let linesArray = NSMutableArray()
        for line in topLines {
            let segment = LineSegment()
            segment.x1 = line.x1
            segment.y1 = line.y1
            segment.x2 = line.x2
            segment.y2 = line.y2
            linesArray.add(segment)
        }
        
        // Draw lines on image (no selection, so pass -1)
        var drawnImage = OpenCVWrapper.drawLines(image, lines: linesArray as! [LineSegment], selectedIndex: -1)
        
        // Add text labels with distances on the image
        drawnImage = addDistanceLabels(to: drawnImage, lines: topLines)
        
        DispatchQueue.main.async {
            self.detectedLines = topLines
            self.displayImage = drawnImage
        }
    }
    
    // Structure to return 3D coordinates and length
    private struct Line3DResult {
        let point1: simd_float3
        let point2: simd_float3
        let length: Float
    }
    
    // MARK: - Depth Sampling and Interpolation
    
    /// Bilinear interpolation to get depth value at sub-pixel coordinates
    private func bilinearInterpolateDepth(x: Float, y: Float, lidarDepth: [Float]) -> Float? {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = x0 + 1
        let y1 = y0 + 1
        
        // Clamp to valid range
        let clampedX0 = max(0, min(lidarWidth - 1, x0))
        let clampedY0 = max(0, min(lidarHeight - 1, y0))
        let clampedX1 = max(0, min(lidarWidth - 1, x1))
        let clampedY1 = max(0, min(lidarHeight - 1, y1))
        
        // Get depth values at four corners
        let idx00 = clampedY0 * lidarWidth + clampedX0
        let idx01 = clampedY1 * lidarWidth + clampedX0
        let idx10 = clampedY0 * lidarWidth + clampedX1
        let idx11 = clampedY1 * lidarWidth + clampedX1
        
        guard idx00 < lidarDepth.count && idx01 < lidarDepth.count &&
              idx10 < lidarDepth.count && idx11 < lidarDepth.count else {
            return nil
        }
        
        let d00 = lidarDepth[idx00]
        let d01 = lidarDepth[idx01]
        let d10 = lidarDepth[idx10]
        let d11 = lidarDepth[idx11]
        
        // Check if any depth value is invalid
        if d00 <= 0 || d01 <= 0 || d10 <= 0 || d11 <= 0 ||
           d00.isNaN || d01.isNaN || d10.isNaN || d11.isNaN ||
           d00.isInfinite || d01.isInfinite || d10.isInfinite || d11.isInfinite {
            return nil
        }
        
        // Bilinear interpolation
        let fx = x - Float(clampedX0)
        let fy = y - Float(clampedY0)
        
        let d0 = d00 * (1 - fx) + d10 * fx
        let d1 = d01 * (1 - fx) + d11 * fx
        let depth = d0 * (1 - fy) + d1 * fy
        
        return depth
    }
    
    /// Sample multiple points along the line and calculate average depth
    private func sampleLineDepth(x1: Float, y1: Float, x2: Float, y2: Float,
                                 lidarDepth: [Float], numSamples: Int = 5) -> (Float, Float)? {
        // Sample endpoints first (most important)
        guard let depth1_start = bilinearInterpolateDepth(x: x1, y: y1, lidarDepth: lidarDepth),
              let depth2_end = bilinearInterpolateDepth(x: x2, y: y2, lidarDepth: lidarDepth) else {
            return nil
        }
        
        // Sample additional points along the line for validation
        var validDepths: [Float] = [depth1_start]
        validDepths.reserveCapacity(numSamples)
        
        // Sample intermediate points (skip first and last as they are endpoints)
        for i in 1..<(numSamples - 1) {
            let t = Float(i) / Float(max(1, numSamples - 1))
            let x = x1 + (x2 - x1) * t
            let y = y1 + (y2 - y1) * t
            
            if let depth = bilinearInterpolateDepth(x: x, y: y, lidarDepth: lidarDepth) {
                validDepths.append(depth)
            }
        }
        
        validDepths.append(depth2_end)
        
        // Use endpoints directly (they are the most accurate for line endpoints)
        // The intermediate samples are used for validation
        return (depth1_start, depth2_end)
    }
    
    private func calculate3DCoordinates(x1: Float, y1: Float, x2: Float, y2: Float,
                                       lidarDepth: [Float], intrinsics: simd_float3x3,
                                       imageResolution: CGSize) -> Line3DResult {
        // Scale line coordinates from image resolution to LiDAR resolution
        let scaleX = Float(lidarWidth) / Float(imageResolution.width)
        let scaleY = Float(lidarHeight) / Float(imageResolution.height)
        
        // Map line endpoints to LiDAR coordinates (keep as Float for interpolation)
        let lx1 = x1 * scaleX
        let ly1 = y1 * scaleY
        let lx2 = x2 * scaleX
        let ly2 = y2 * scaleY
        
        // Sample depth along the line using bilinear interpolation
        guard let (depth1, depth2) = sampleLineDepth(
            x1: lx1, y1: ly1, x2: lx2, y2: ly2,
            lidarDepth: lidarDepth, numSamples: 5
        ) else {
            return Line3DResult(point1: simd_float3(0, 0, 0), point2: simd_float3(0, 0, 0), length: 0)
        }
        
        // Clamp coordinates to valid range for projection
        let clampedX1 = max(0.0, min(Float(lidarWidth - 1), lx1))
        let clampedY1 = max(0.0, min(Float(lidarHeight - 1), ly1))
        let clampedX2 = max(0.0, min(Float(lidarWidth - 1), lx2))
        let clampedY2 = max(0.0, min(Float(lidarHeight - 1), ly2))
        
        // Scale intrinsics to LiDAR resolution
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        
        // Validate intrinsics
        guard fx > 0 && fy > 0 else {
            return Line3DResult(point1: simd_float3(0, 0, 0), point2: simd_float3(0, 0, 0), length: 0)
        }
        
        // Unproject 2D points to 3D using camera intrinsics
        // Formula: X = (u - cx) * Z / fx, Y = (v - cy) * Z / fy, Z = depth
        // Note: ARKit camera coordinate system: X right, Y up, Z forward (right-handed)
        // Image coordinate system: X right, Y down, Z forward
        // So we need to flip Y: Y_camera = -Y_image
        let x1_3d = (clampedX1 - cx) * depth1 / fx
        let y1_3d = -(clampedY1 - cy) * depth1 / fy  // Flip Y for camera coordinate
        let z1_3d = depth1
        
        let x2_3d = (clampedX2 - cx) * depth2 / fx
        let y2_3d = -(clampedY2 - cy) * depth2 / fy  // Flip Y for camera coordinate
        let z2_3d = depth2
        
        let point1 = simd_float3(x1_3d, y1_3d, z1_3d)
        let point2 = simd_float3(x2_3d, y2_3d, z2_3d)
        
        // Calculate 3D Euclidean distance
        let dx = x2_3d - x1_3d
        let dy = y2_3d - y1_3d
        let dz = z2_3d - z1_3d
        
        let length = sqrtf(dx * dx + dy * dy + dz * dz)
        
        return Line3DResult(point1: point1, point2: point2, length: length)
    }
    
    
    // MARK: - Image Drawing
    
    private func addDistanceLabels(to image: UIImage, lines: [DetectedLine]) -> UIImage {
        let size = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }
        
        // Draw the original image
        image.draw(at: .zero)
        
        // Configure text attributes
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.yellow,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0  // Negative for fill with stroke
        ]
        
        // Draw distance labels for each line
        for (index, line) in lines.enumerated() {
            // Calculate midpoint of the line
            let midX = (line.x1 + line.x2) / 2.0
            let midY = (line.y1 + line.y2) / 2.0
            
            // Format distance text
            let distanceText = String(format: "%.1f cm", line.length3D * 100)
            
            // Draw text at midpoint
            let text = NSAttributedString(string: distanceText, attributes: textAttributes)
            let textSize = text.size()
            let textRect = CGRect(
                x: CGFloat(midX) - textSize.width / 2,
                y: CGFloat(midY) - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            // Draw background rectangle for better visibility
            context.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            context.fillEllipse(in: textRect.insetBy(dx: -4, dy: -2))
            
            // Draw text
            text.draw(in: textRect)
        }
        
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage ?? image
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
