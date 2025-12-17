//
//  ARViewContainer.swift
//  testMeasure
//
//  Created by jacky72503 on 2025/12/15.
//

import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arManager: ARDataManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR session with LiDAR depth
        let config = ARWorldTrackingConfiguration()
        
        // Enable LiDAR depth if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            print("DEBUG: LiDAR depth enabled")
        } else {
            print("DEBUG: LiDAR not available on this device")
        }
        
        arView.session.run(config)
        arView.session.delegate = context.coordinator
        
        // Store ARView reference in coordinator
        context.coordinator.arView = arView
        
        // Initial update
        DispatchQueue.main.async {
            context.coordinator.updateLines(arManager.detectedLines, frame: arManager.currentFrame)
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No longer needed - using 2D overlay instead of 3D rendering
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(arManager: arManager)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var arManager: ARDataManager
        var arView: ARView?
        private var cameraAnchor: AnchorEntity?
        var lastLineCount: Int = -1  // Changed to internal for access from updateUIView
        
        init(arManager: ARDataManager) {
            self.arManager = arManager
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Capture RGB image and depth data continuously
            arManager.captureFrame(frame: frame)
        }
        
        func updateLines(_ lines: [DetectedLine], frame: ARFrame?) {
            // No longer needed - using 2D overlay instead of 3D rendering
        }
    }
}
