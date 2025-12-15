//
//  DepthModelManager.swift
//  testMeasure
//
//  Created by jacky72503 on 2025/12/15.
//

import Foundation
import CoreML
import Vision
import CoreVideo

class DepthModelManager {
    private var visionModel: VNCoreMLModel?
    
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
            // MLModel(contentsOf:) supports .mlpackage, .mlmodelc, and .mlmodel formats
            let model = try MLModel(contentsOf: url)
            self.visionModel = try VNCoreMLModel(for: model)
            print("DEBUG: Successfully loaded Depth Anything V2 model from \(url.lastPathComponent)")
        } catch {
            print("DEBUG: Failed to load model: \(error)")
            print("DEBUG: Error details: \(error.localizedDescription)")
        }
    }
    
    func estimateDepth(from pixelBuffer: CVPixelBuffer, completion: @escaping (CVPixelBuffer?) -> Void) {
        guard let visionModel = visionModel else {
            print("DEBUG: Model not loaded, cannot estimate depth")
            completion(nil)
            return
        }
        
        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let error = error {
                print("DEBUG: Depth estimation error: \(error)")
                completion(nil)
                return
            }
            
            guard let results = request.results as? [VNPixelBufferObservation],
                  let depthMap = results.first?.pixelBuffer else {
                print("DEBUG: No depth map in results")
                completion(nil)
                return
            }
            
            completion(depthMap)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("DEBUG: Failed to perform depth estimation: \(error)")
            completion(nil)
        }
    }
}
