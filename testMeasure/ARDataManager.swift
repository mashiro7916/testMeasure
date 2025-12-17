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
    private let depthModelManager = DepthModelManager()
    private let fileManager = FileManager.default
    private var baseDirectory: URL?
    
    // Performance optimization: save less frequently
    private let saveInterval: Int = 30  // Save every 30 frames (approximately 1 second at 30fps)
    private var lastSaveTime: TimeInterval = 0
    private let minSaveInterval: TimeInterval = 1.0  // Minimum 1 second between saves
    
    // Status
    @Published var savedCount: Int = 0
    @Published var isProcessing: Bool = false
    
    init() {
        setupDirectory()
        print("DEBUG: ARDataManager initialized")
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
        let currentFrameNumber = savedFrameCount
        
        // Get RGB image
        let pixelBuffer = frame.capturedImage
        let rgbWidth = CVPixelBufferGetWidth(pixelBuffer)
        let rgbHeight = CVPixelBufferGetHeight(pixelBuffer)
        print("DEBUG: Capturing frame \(currentFrameNumber), RGB size: \(rgbWidth)x\(rgbHeight)")
        
        // Get LiDAR depth if available
        let lidarDepth = frame.sceneDepth?.depthMap
        if let lidar = lidarDepth {
            let lidarWidth = CVPixelBufferGetWidth(lidar)
            let lidarHeight = CVPixelBufferGetHeight(lidar)
            print("DEBUG: LiDAR depth size: \(lidarWidth)x\(lidarHeight)")
        }
        
        // Convert YUV to RGB
        guard let rgbBuffer = convertYUVToRGB(pixelBuffer) else {
            print("DEBUG: Failed to convert YUV to RGB")
            return
        }
        
        // Save RGB image on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveRGBImage(pixelBuffer: rgbBuffer, frameNumber: currentFrameNumber, directory: baseDir)
        }
        
        // Save LiDAR depth on background queue
        if let lidar = lidarDepth {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.saveLidarDepth(lidarDepth: lidar, frameNumber: currentFrameNumber, directory: baseDir)
            }
        }
        
        // Run Depth Anything model on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.depthModelManager.estimateDepth(from: rgbBuffer) { [weak self] relativeDepthMap in
                guard let self = self, let relativeDepth = relativeDepthMap else {
                    return
                }
                
                // Save Depth Anything depth on background queue
                DispatchQueue.global(qos: .utility).async {
                    self.saveDepthAnythingDepth(depthMap: relativeDepth, frameNumber: currentFrameNumber, directory: baseDir)
                }
            }
        }
    }
    
    // MARK: - Save Functions
    
    private func saveRGBImage(pixelBuffer: CVPixelBuffer, frameNumber: Int, directory: URL) {
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
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            print("DEBUG: Saved RGB image: \(imagePath.lastPathComponent) (size: \(width)x\(height))")
            
            DispatchQueue.main.async {
                self.savedCount = self.savedFrameCount
            }
        } catch {
            print("DEBUG: Failed to save RGB image: \(error)")
        }
    }
    
    private func saveLidarDepth(lidarDepth: CVPixelBuffer, frameNumber: Int, directory: URL) {
        CVPixelBufferLockBaseAddress(lidarDepth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(lidarDepth, .readOnly) }
        
        let width = CVPixelBufferGetWidth(lidarDepth)
        let height = CVPixelBufferGetHeight(lidarDepth)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(lidarDepth)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(lidarDepth) else {
            print("DEBUG: Failed to get LiDAR base address")
            return
        }
        
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let rowBytes = bytesPerRow / MemoryLayout<Float32>.size
        
        // Extract depth values
        var depthValues: [Float] = []
        depthValues.reserveCapacity(width * height)
        
        for y in 0..<height {
            let rowStart = buffer.advanced(by: y * rowBytes)
            for x in 0..<width {
                depthValues.append(rowStart[x])
            }
        }
        
        // Save to text file
        let filePath = directory.appendingPathComponent("lidar_depth_\(String(format: "%06d", frameNumber)).txt")
        
        var content = "\(width) \(height)\n"  // Header: width height
        for value in depthValues {
            content += String(format: "%.6f\n", value)
        }
        
        do {
            try content.write(to: filePath, atomically: true, encoding: .utf8)
            print("DEBUG: Saved LiDAR depth: \(filePath.lastPathComponent) (size: \(width)x\(height), \(depthValues.count) values)")
        } catch {
            print("DEBUG: Failed to save LiDAR depth: \(error)")
        }
    }
    
    private func saveDepthAnythingDepth(depthMap: CVPixelBuffer, frameNumber: Int, directory: URL) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            print("DEBUG: Failed to get depth map base address")
            return
        }
        
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let rowBytes = bytesPerRow / MemoryLayout<Float32>.size
        
        // Extract depth values
        var depthValues: [Float] = []
        depthValues.reserveCapacity(width * height)
        
        for y in 0..<height {
            let rowStart = buffer.advanced(by: y * rowBytes)
            for x in 0..<width {
                depthValues.append(rowStart[x])
            }
        }
        
        // Save to text file
        let filePath = directory.appendingPathComponent("depthanything_depth_\(String(format: "%06d", frameNumber)).txt")
        
        var content = "\(width) \(height)\n"  // Header: width height
        for value in depthValues {
            content += String(format: "%.6f\n", value)
        }
        
        do {
            try content.write(to: filePath, atomically: true, encoding: .utf8)
            print("DEBUG: Saved Depth Anything depth: \(filePath.lastPathComponent) (size: \(width)x\(height), \(depthValues.count) values)")
        } catch {
            print("DEBUG: Failed to save Depth Anything depth: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
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
            return nil
        }
        
        // Use Core Image to convert YUV to RGB
        let ciImage = CIImage(cvPixelBuffer: yuvBuffer)
        let context = CIContext()
        context.render(ciImage, to: outputBuffer)
        
        return outputBuffer
    }
}
