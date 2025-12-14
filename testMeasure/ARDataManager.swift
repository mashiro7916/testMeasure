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
    private let fileManager = FileManager.default
    private var baseDirectory: URL?
    
    init() {
        setupDirectory()
    }
    
    private func setupDirectory() {
        // Create directory in Documents/testMeasure folder
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
        
        // Save RGB image
        saveRGBImage(frame: frame, frameNumber: frameCount, directory: baseDir)
        
        // Save LiDAR depth data
        saveDepthData(frame: frame, frameNumber: frameCount, directory: baseDir)
    }
    
    private func saveRGBImage(frame: ARFrame, frameNumber: Int, directory: URL) {
        let pixelBuffer = frame.capturedImage
        
        // Convert CVPixelBuffer to UIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("DEBUG: Failed to create CGImage from pixel buffer")
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        // Save as PNG
        let imagePath = directory.appendingPathComponent("rgb_frame_\(String(format: "%06d", frameNumber)).png")
        
        guard let imageData = uiImage.pngData() else {
            print("DEBUG: Failed to convert UIImage to PNG data")
            return
        }
        
        do {
            try imageData.write(to: imagePath)
            print("DEBUG: Saved RGB image: \(imagePath.lastPathComponent)")
        } catch {
            print("DEBUG: Failed to save RGB image: \(error)")
        }
    }
    
    private func saveDepthData(frame: ARFrame, frameNumber: Int, directory: URL) {
        // Get scene depth data from ARFrame
        guard let sceneDepth = frame.sceneDepth else {
            print("DEBUG: No scene depth data available for frame \(frameNumber)")
            return
        }
        
        // Get depth map from ARDepthData
        let depthMap = sceneDepth.depthMap
        
        // Convert depth map to array of Float values
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
        
        // Check pixel format - ARKit depth maps are typically kCVPixelFormatType_DepthFloat32
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        var depthValues: [Float] = []
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            // Read depth values as Float32
            let buffer = baseAddr.assumingMemoryBound(to: Float32.self)
            for y in 0..<height {
                let rowStart = buffer.advanced(by: y * (bytesPerRow / MemoryLayout<Float32>.size))
                for x in 0..<width {
                    depthValues.append(rowStart[x])
                }
            }
        } else {
            print("DEBUG: Unsupported depth format: \(pixelFormat)")
            return
        }
        
        // Save depth data as binary file
        let depthPath = directory.appendingPathComponent("depth_frame_\(String(format: "%06d", frameNumber)).bin")
        
        do {
            let data = Data(bytes: depthValues, count: depthValues.count * MemoryLayout<Float>.size)
            try data.write(to: depthPath)
            
            // Also save metadata (width, height) as JSON
            let metadata: [String: Any] = [
                "width": width,
                "height": height,
                "frameNumber": frameNumber,
                "timestamp": frame.timestamp
            ]
            
            let metadataPath = directory.appendingPathComponent("depth_metadata_\(String(format: "%06d", frameNumber)).json")
            let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
            try jsonData.write(to: metadataPath)
            
            print("DEBUG: Saved depth data: \(depthPath.lastPathComponent) (size: \(width)x\(height))")
        } catch {
            print("DEBUG: Failed to save depth data: \(error)")
        }
    }
}

