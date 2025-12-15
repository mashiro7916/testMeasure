//
//  DepthModelManager.swift
//  testMeasure
//
//  Created by jacky72503 on 2025/12/15.
//

import Foundation
import CoreML
import CoreVideo
import Accelerate

class DepthModelManager {
    private var model: MLModel?
    private var inputName: String?
    private var outputName: String?
    private var inputWidth: Int = 0
    private var inputHeight: Int = 0
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        // Try to find model file in order: mlpackage -> mlmodelc -> mlmodel
        var modelURL: URL?
        var modelType: String = ""
        
        if let url = Bundle.main.url(forResource: "DepthAnythingV2", withExtension: "mlpackage") {
            modelURL = url
            modelType = "mlpackage"
        } else if let url = Bundle.main.url(forResource: "DepthAnythingV2", withExtension: "mlmodelc") {
            modelURL = url
            modelType = "mlmodelc"
        } else if let url = Bundle.main.url(forResource: "DepthAnythingV2", withExtension: "mlmodel") {
            modelURL = url
            modelType = "mlmodel"
        }
        
        guard let url = modelURL else {
            print("DEBUG: Model file not found. Please add DepthAnythingV2.mlpackage, DepthAnythingV2.mlmodelc or DepthAnythingV2.mlmodel to the project.")
            print("DEBUG: Make sure the file is added to the target and copied to bundle.")
            return
        }
        
        print("DEBUG: Found model file: \(url.lastPathComponent) (type: \(modelType))")
        print("DEBUG: Model file path: \(url.path)")
        
        do {
            let model = try MLModel(contentsOf: url)
            self.model = model
            
            // Get model input/output specifications
            let description = model.modelDescription
            if let inputDesc = description.inputDescriptionsByName.first {
                self.inputName = inputDesc.key
                // Fixed input size for Depth Anything V2: 518x392
                self.inputWidth = 518
                self.inputHeight = 392
                print("DEBUG: Model input: \(inputDesc.key), fixed size: \(inputWidth)x\(inputHeight)")
            }
            
            if let outputDesc = description.outputDescriptionsByName.first {
                self.outputName = outputDesc.key
                print("DEBUG: Model output: \(outputDesc.key)")
            }
            
            print("DEBUG: Successfully loaded Depth Anything V2 model from \(url.lastPathComponent)")
        } catch {
            print("DEBUG: Failed to load model: \(error)")
            print("DEBUG: Error details: \(error.localizedDescription)")
        }
    }
    
    func estimateDepth(from rgbPixelBuffer: CVPixelBuffer, completion: @escaping (CVPixelBuffer?) -> Void) {
        guard let model = model, let inputName = inputName, let outputName = outputName else {
            print("DEBUG: Model not loaded, cannot estimate depth")
            completion(nil)
            return
        }
        
        // Perform prediction on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            // Prepare input: resize and convert to model input format
            guard let modelInput = self.prepareModelInput(from: rgbPixelBuffer, targetWidth: self.inputWidth, targetHeight: self.inputHeight) else {
                print("DEBUG: Failed to prepare model input")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            do {
                // Create feature provider
                let inputFeature = try MLFeatureValue(pixelBuffer: modelInput)
                let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputFeature])
                
                // Perform prediction
                let prediction = try model.prediction(from: provider)
                
                // Extract output
                guard let outputFeature = prediction.featureValue(for: outputName) else {
                    print("DEBUG: No output feature found")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Convert output to CVPixelBuffer
                var depthMap: CVPixelBuffer?
                
                if let pixelBuffer = outputFeature.imageBufferValue {
                    depthMap = pixelBuffer
                } else if let multiArray = outputFeature.multiArrayValue {
                    depthMap = self.convertMultiArrayToPixelBuffer(multiArray)
                }
                
                DispatchQueue.main.async {
                    completion(depthMap)
                }
            } catch {
                print("DEBUG: Model prediction failed: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    private func prepareModelInput(from pixelBuffer: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        // If already correct size, return as is
        if sourceWidth == targetWidth && sourceHeight == targetHeight {
            return pixelBuffer
        }
        
        // Create resized pixel buffer
        var resizedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32BGRA,
            nil,
            &resizedBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = resizedBuffer else {
            print("DEBUG: Failed to create resized pixel buffer")
            return nil
        }
        
        // Use vImage for high-quality resizing
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
        }
        
        guard let sourceBase = CVPixelBufferGetBaseAddress(pixelBuffer),
              let destBase = CVPixelBufferGetBaseAddress(outputBuffer) else {
            return nil
        }
        
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        
        var sourceBuffer = vImage_Buffer(
            data: sourceBase,
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: sourceBytesPerRow
        )
        
        var destBuffer = vImage_Buffer(
            data: destBase,
            height: vImagePixelCount(targetHeight),
            width: vImagePixelCount(targetWidth),
            rowBytes: destBytesPerRow
        )
        
        // Use high-quality scaling
        let error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        
        if error != kvImageNoError {
            print("DEBUG: vImage scaling failed with error: \(error)")
            return nil
        }
        
        return outputBuffer
    }
    
    private func convertMultiArrayToPixelBuffer(_ multiArray: MLMultiArray) -> CVPixelBuffer? {
        // Get dimensions
        let shape = multiArray.shape
        guard shape.count >= 2 else { return nil }
        
        let height = shape[0].intValue
        let width = shape.count > 1 ? shape[1].intValue : shape[0].intValue
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("DEBUG: Failed to create pixel buffer from MLMultiArray")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        guard let baseAddr = baseAddress else { return nil }
        
        let bufferPointer = baseAddr.assumingMemoryBound(to: Float32.self)
        
        // Copy data from MLMultiArray to CVPixelBuffer
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let depthValue = multiArray[index].floatValue
                let bufferIndex = y * (bytesPerRow / MemoryLayout<Float32>.size) + x
                bufferPointer[bufferIndex] = depthValue
            }
        }
        
        return buffer
    }
}
