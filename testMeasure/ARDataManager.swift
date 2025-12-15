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
    private let depthModelManager = DepthModelManager()
    
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
        let pixelBuffer = frame.capturedImage
        
        // Save RGB image
        saveRGBImage(pixelBuffer: pixelBuffer, frameNumber: frameCount, directory: baseDir)
        
        // Estimate depth using Core ML model
        depthModelManager.estimateDepth(from: pixelBuffer) { [weak self] depthMap in
            guard let self = self, let depthMap = depthMap else {
                print("DEBUG: Failed to estimate depth for frame \(self.frameCount)")
                return
            }
            self.saveDepthData(depthMap: depthMap, frameNumber: self.frameCount, directory: baseDir)
        }
    }
    
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
            print("DEBUG: Saved RGB image: \(imagePath.lastPathComponent)")
        } catch {
            print("DEBUG: Failed to save RGB image: \(error)")
        }
    }
    
    private func saveDepthData(depthMap: CVPixelBuffer, frameNumber: Int, directory: URL) {
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
            print("DEBUG: Saved depth data: \(depthPath.lastPathComponent) (size: \(width)x\(height))")
        } catch {
            print("DEBUG: Failed to save depth data: \(error)")
        }
    }
}
