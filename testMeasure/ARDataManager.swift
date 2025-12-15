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
        
        // Estimate depth using Core ML model
        depthModelManager.estimateDepth(from: pixelBuffer) { [weak self] depthMap in
            guard let self = self, let depthMap = depthMap else {
                print("DEBUG: Failed to estimate depth for frame \(currentFrameNumber)")
                return
            }
            
            // Check depth map resolution
            let depthWidth = CVPixelBufferGetWidth(depthMap)
            let depthHeight = CVPixelBufferGetHeight(depthMap)
            print("DEBUG: Depth map size: \(depthWidth)x\(depthHeight), RGB size: \(rgbWidth)x\(rgbHeight)")
            
            // Upsample depth map to RGB resolution
            if let upsampledDepth = self.upsampleDepthMap(depthMap, toWidth: rgbWidth, height: rgbHeight) {
                // Save depth data on background queue
                DispatchQueue.global(qos: .utility).async {
                    self.saveDepthData(depthMap: upsampledDepth, frameNumber: currentFrameNumber, directory: baseDir, targetWidth: rgbWidth, targetHeight: rgbHeight)
                }
            } else {
                print("DEBUG: Failed to upsample depth map, saving original size")
                DispatchQueue.global(qos: .utility).async {
                    self.saveDepthData(depthMap: depthMap, frameNumber: currentFrameNumber, directory: baseDir, targetWidth: depthWidth, targetHeight: depthHeight)
                }
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
    
    private func upsampleDepthMap(_ depthMap: CVPixelBuffer, toWidth width: Int, height: Int) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(depthMap)
        let sourceHeight = CVPixelBufferGetHeight(depthMap)
        
        // If already the same size, return original
        if sourceWidth == width && sourceHeight == height {
            return depthMap
        }
        
        // Create CIImage from depth map
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        
        // Create transform to scale to target size
        let scaleX = CGFloat(width) / CGFloat(sourceWidth)
        let scaleY = CGFloat(height) / CGFloat(sourceHeight)
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledImage = ciImage.transformed(by: transform)
        
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
        
        // Render scaled image to output buffer
        let context = CIContext()
        context.render(scaledImage, to: outputBuffer)
        
        print("DEBUG: Upsampled depth map from \(sourceWidth)x\(sourceHeight) to \(width)x\(height)")
        return outputBuffer
    }
    
    private func saveDepthData(depthMap: CVPixelBuffer, frameNumber: Int, directory: URL, targetWidth: Int, targetHeight: Int) {
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
        
        // Save depth data as binary file
        let depthPath = directory.appendingPathComponent("depth_frame_\(String(format: "%06d", frameNumber)).bin")
        
        do {
            let data = Data(bytes: depthValues, count: depthValues.count * MemoryLayout<Float>.size)
            try data.write(to: depthPath)
            print("DEBUG: Saved depth data: \(depthPath.lastPathComponent) (size: \(width)x\(height), target: \(targetWidth)x\(targetHeight))")
        } catch {
            print("DEBUG: Failed to save depth data: \(error)")
        }
    }
}
