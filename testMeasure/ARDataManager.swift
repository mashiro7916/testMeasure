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

class ARDataManager: ObservableObject {
    private var frameCount: Int = 0
    private var savedFrameCount: Int = 0
    private let fileManager = FileManager.default
    private var baseDirectory: URL?
    private let depthModelManager = DepthModelManager()
    private let saveInterval: Int = 30  // Save every 30 frames (approximately 1 second at 30fps)
    private var lastSaveTime: TimeInterval = 0
    private let minSaveInterval: TimeInterval = 1.0  // Minimum 1 second between saves
    
    init() {
        setupDirectory()
    }
    
    private func setupDirectory() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = documentsPath.appendingPathComponent("testMeasure")
        
        guard let baseDir = baseDirectory else { return }
        
        do {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
            print("DEBUG: Created directory at \(baseDir.path)")
        } catch {
            print("DEBUG: Failed to create directory: \(error)")
        }
    }
    
    func captureFrame(frame: ARFrame) {
        guard let baseDir = baseDirectory else { return }
        
        frameCount += 1
        let currentTime = frame.timestamp
        
        // Check if we should save this frame (based on frame count and time interval)
        let shouldSave = (frameCount % saveInterval == 0) && (currentTime - lastSaveTime >= minSaveInterval)
        
        if !shouldSave {
            return
        }
        
        savedFrameCount += 1
        lastSaveTime = currentTime
        let pixelBuffer = frame.capturedImage
        let currentFrameNumber = savedFrameCount
        
        // Get RGB image dimensions for comparison
        let rgbWidth = CVPixelBufferGetWidth(pixelBuffer)
        let rgbHeight = CVPixelBufferGetHeight(pixelBuffer)
        print("DEBUG: Capturing frame \(currentFrameNumber), RGB size: \(rgbWidth)x\(rgbHeight)")
        
        // Save RGB image on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveRGBImage(pixelBuffer: pixelBuffer, frameNumber: currentFrameNumber, directory: baseDir)
        }
        
        // Convert YUV to RGB for model input
        guard let rgbBuffer = convertYUVToRGB(pixelBuffer) else {
            print("DEBUG: Failed to convert YUV to RGB")
            return
        }
        
        // Estimate depth using Core ML model with RGB input
        depthModelManager.estimateDepth(from: rgbBuffer) { [weak self] depthMap in
            guard let self = self, let depthMap = depthMap else {
                print("DEBUG: Failed to estimate depth for frame \(currentFrameNumber)")
                return
            }
            
            // Check depth map resolution (model output size)
            let depthWidth = CVPixelBufferGetWidth(depthMap)
            let depthHeight = CVPixelBufferGetHeight(depthMap)
            print("DEBUG: Depth map size: \(depthWidth)x\(depthHeight) (model output), RGB size: \(rgbWidth)x\(rgbHeight)")
            
            // Save depth data: original size and upsampled to RGB resolution
            DispatchQueue.global(qos: .utility).async {
                self.saveDepthData(depthMap: depthMap, frameNumber: currentFrameNumber, directory: baseDir, targetWidth: rgbWidth, targetHeight: rgbHeight, rgbPixelBuffer: rgbBuffer)
            }
        }
    }
    
    private func saveRGBImage(pixelBuffer: CVPixelBuffer, frameNumber: Int, directory: URL) {
        let rgbWidth = CVPixelBufferGetWidth(pixelBuffer)
        let rgbHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("DEBUG: Failed to create CGImage from pixel buffer")
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        let imagePath = directory.appendingPathComponent("rgb_frame_\(String(format: "%06d", frameNumber)).png")
        
        guard let imageData = uiImage.pngData() else {
            print("DEBUG: Failed to convert UIImage to PNG data")
            return
        }
        
        do {
            try imageData.write(to: imagePath)
            print("DEBUG: Saved RGB image: \(imagePath.lastPathComponent) (size: \(rgbWidth)x\(rgbHeight))")
        } catch {
            print("DEBUG: Failed to save RGB image: \(error)")
        }
    }
    
    private func depthToColor(_ normalizedDepth: Float) -> (UInt8, UInt8, UInt8) {
        // Convert normalized depth (0.0 to 1.0) to RGB color using rainbow colormap
        // Red (near) -> Yellow -> Green -> Cyan -> Blue (far)
        let value = max(0.0, min(1.0, normalizedDepth))
        
        let r: UInt8
        let g: UInt8
        let b: UInt8
        
        if value < 0.25 {
            // Red to Yellow
            let t = value / 0.25
            r = 255
            g = UInt8(t * 255)
            b = 0
        } else if value < 0.5 {
            // Yellow to Green
            let t = (value - 0.25) / 0.25
            r = UInt8((1.0 - t) * 255)
            g = 255
            b = 0
        } else if value < 0.75 {
            // Green to Cyan
            let t = (value - 0.5) / 0.25
            r = 0
            g = 255
            b = UInt8(t * 255)
        } else {
            // Cyan to Blue
            let t = (value - 0.75) / 0.25
            r = 0
            g = UInt8((1.0 - t) * 255)
            b = 255
        }
        
        return (r, g, b)
    }
    
    private func convertYUVToRGB(_ yuvBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(yuvBuffer)
        let height = CVPixelBufferGetHeight(yuvBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(yuvBuffer)
        
        // If already RGB, return as is
        if pixelFormat == kCVPixelFormatType_32BGRA || pixelFormat == kCVPixelFormatType_32ARGB {
            return yuvBuffer
        }
        
        // Create RGB output buffer
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
            print("DEBUG: Failed to create RGB pixel buffer")
            return nil
        }
        
        // Use Core Image to convert YUV to RGB
        let ciImage = CIImage(cvPixelBuffer: yuvBuffer)
        let context = CIContext()
        context.render(ciImage, to: outputBuffer)
        
        return outputBuffer
    }
    
    private func upsampleDepthMap(_ depthMap: CVPixelBuffer, toWidth width: Int, height: Int) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(depthMap)
        let sourceHeight = CVPixelBufferGetHeight(depthMap)
        
        // If already the same size, return original
        if sourceWidth == width && sourceHeight == height {
            return depthMap
        }
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &outputPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            print("DEBUG: Failed to create output pixel buffer for upsampling")
            return nil
        }
        
        // Use vImage for high-quality bilinear interpolation
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
        }
        
        guard let sourceBase = CVPixelBufferGetBaseAddress(depthMap),
              let destBase = CVPixelBufferGetBaseAddress(outputBuffer) else {
            return nil
        }
        
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        
        var sourceBuffer = vImage_Buffer(
            data: sourceBase,
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: sourceBytesPerRow
        )
        
        var destBuffer = vImage_Buffer(
            data: destBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: destBytesPerRow
        )
        
        // Use high-quality scaling for depth values
        let error = vImageScale_PlanarF(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        
        if error != kvImageNoError {
            print("DEBUG: vImage depth scaling failed with error: \(error)")
            return nil
        }
        
        print("DEBUG: Upsampled depth map from \(sourceWidth)x\(sourceHeight) to \(width)x\(height)")
        return outputBuffer
    }
    
    private func saveDepthData(depthMap: CVPixelBuffer, frameNumber: Int, directory: URL, targetWidth: Int, targetHeight: Int, rgbPixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        
        guard let baseAddr = baseAddress else {
            print("DEBUG: Failed to get base address of depth map")
            return
        }
        
        // Read depth values as Float32
        let buffer = baseAddr.assumingMemoryBound(to: Float32.self)
        var depthValues: [Float] = []
        
        for y in 0..<height {
            let rowStart = buffer.advanced(by: y * (bytesPerRow / MemoryLayout<Float32>.size))
            for x in 0..<width {
                depthValues.append(rowStart[x])
            }
        }
        
        // Save depth map as grayscale PNG image (model output directly)
        if !depthValues.isEmpty {
            let minDepth = depthValues.min() ?? 0
            let maxDepth = depthValues.max() ?? 1
            let range = maxDepth - minDepth
            
            // Normalize depth values to 0-255 for grayscale visualization
            var grayscalePixels: [UInt8] = []
            grayscalePixels.reserveCapacity(depthValues.count)
            
            for depth in depthValues {
                let normalized = range > 0 ? ((depth - minDepth) / range) : 0
                grayscalePixels.append(UInt8(max(0, min(255, normalized * 255.0))))
            }
            
            // Create grayscale image from normalized depth values
            let colorSpace = CGColorSpaceCreateDeviceGray()
            grayscalePixels.withUnsafeMutableBytes { bytes in
                if let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue),
                   let cgImage = context.makeImage() {
                    let uiImage = UIImage(cgImage: cgImage)
                    if let imageData = uiImage.pngData() {
                        let imagePath = directory.appendingPathComponent("depth_image_\(String(format: "%06d", frameNumber)).png")
                        do {
                            try imageData.write(to: imagePath)
                            print("DEBUG: Saved depth grayscale image (original): \(imagePath.lastPathComponent) (size: \(width)x\(height))")
                        } catch {
                            print("DEBUG: Failed to save depth image: \(error)")
                        }
                    }
                }
            }
            
            // Upsample depth map to RGB resolution using Lanczos and save
            if let upsampledDepth = upsampleDepthMapLanczos(depthMap, toWidth: targetWidth, height: targetHeight) {
                saveUpsampledDepthData(depthMap: upsampledDepth, frameNumber: frameNumber, directory: directory, targetWidth: targetWidth, targetHeight: targetHeight, rgbPixelBuffer: rgbPixelBuffer)
            }
        }
    }
    
    private func upsampleDepthMapLanczos(_ depthMap: CVPixelBuffer, toWidth width: Int, height: Int) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(depthMap)
        let sourceHeight = CVPixelBufferGetHeight(depthMap)
        
        // If already the same size, return original
        if sourceWidth == width && sourceHeight == height {
            return depthMap
        }
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &outputPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            print("DEBUG: Failed to create output pixel buffer for Lanczos upsampling")
            return nil
        }
        
        // Use Core Image with high-quality interpolation (Lanczos)
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        
        // Create scale transform
        let scaleX = CGFloat(width) / CGFloat(sourceWidth)
        let scaleY = CGFloat(height) / CGFloat(sourceHeight)
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledImage = ciImage.transformed(by: transform)
        
        // Render with high-quality interpolation (Core Image uses Lanczos by default for high-quality scaling)
        let context = CIContext(options: [.highQualityDownsample: true, .useSoftwareRenderer: false])
        context.render(scaledImage, to: outputBuffer)
        
        print("DEBUG: Upsampled depth map using Lanczos from \(sourceWidth)x\(sourceHeight) to \(width)x\(height)")
        return outputBuffer
    }
    
    private func saveUpsampledDepthData(depthMap: CVPixelBuffer, frameNumber: Int, directory: URL, targetWidth: Int, targetHeight: Int, rgbPixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        
        guard let baseAddr = baseAddress else {
            print("DEBUG: Failed to get base address of upsampled depth map")
            return
        }
        
        // Read depth values as Float32
        let buffer = baseAddr.assumingMemoryBound(to: Float32.self)
        var depthValues: [Float] = []
        
        for y in 0..<height {
            let rowStart = buffer.advanced(by: y * (bytesPerRow / MemoryLayout<Float32>.size))
            for x in 0..<width {
                depthValues.append(rowStart[x])
            }
        }
        
        // Create composite image: RGB on left, depth map on right
        if !depthValues.isEmpty {
            // Convert depth map to grayscale UIImage
            let minDepth = depthValues.min() ?? 0
            let maxDepth = depthValues.max() ?? 1
            let range = maxDepth - minDepth
            
            var grayscalePixels: [UInt8] = []
            grayscalePixels.reserveCapacity(depthValues.count)
            
            for depth in depthValues {
                let normalized = range > 0 ? ((depth - minDepth) / range) : 0
                grayscalePixels.append(UInt8(max(0, min(255, normalized * 255.0))))
            }
            
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let depthCGImage = grayscalePixels.withUnsafeMutableBytes({ bytes -> CGImage? in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                    return nil
                }
                return context.makeImage()
            }) else {
                print("DEBUG: Failed to create depth CGImage")
                return
            }
            
            let depthUIImage = UIImage(cgImage: depthCGImage)
            
            // Convert RGB pixel buffer to UIImage
            let rgbCIImage = CIImage(cvPixelBuffer: rgbPixelBuffer)
            let context = CIContext()
            guard let rgbCGImage = context.createCGImage(rgbCIImage, from: rgbCIImage.extent) else {
                print("DEBUG: Failed to create RGB CGImage")
                return
            }
            let rgbUIImage = UIImage(cgImage: rgbCGImage)
            
            // Create composite image (side by side: RGB left, depth right)
            let compositeWidth = width * 2
            let compositeHeight = height
            let compositeSize = CGSize(width: compositeWidth, height: compositeHeight)
            
            UIGraphicsBeginImageContextWithOptions(compositeSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            // Draw RGB image on the left
            rgbUIImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Draw depth map on the right
            depthUIImage.draw(in: CGRect(x: width, y: 0, width: width, height: height))
            
            guard let compositeImage = UIGraphicsGetImageFromCurrentImageContext() else {
                print("DEBUG: Failed to create composite image")
                return
            }
            
            // Save composite image
            if let imageData = compositeImage.pngData() {
                let imagePath = directory.appendingPathComponent("composite_\(String(format: "%06d", frameNumber)).png")
                do {
                    try imageData.write(to: imagePath)
                    print("DEBUG: Saved composite image (RGB + Depth): \(imagePath.lastPathComponent) (size: \(compositeWidth)x\(compositeHeight))")
                } catch {
                    print("DEBUG: Failed to save composite image: \(error)")
                }
            }
        }
    }
}
