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
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(arManager: arManager)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var arManager: ARDataManager
        
        init(arManager: ARDataManager) {
            self.arManager = arManager
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Capture RGB image and depth data continuously
            arManager.captureFrame(frame: frame)
        }
    }
}

