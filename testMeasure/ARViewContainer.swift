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
        // Update 3D lines when detectedLines change
        let currentLines = arManager.detectedLines
        let currentFrame = arManager.currentFrame
        
        print("DEBUG: updateUIView called, detectedLines count: \(currentLines.count), lastLineCount: \(context.coordinator.lastLineCount)")
        
        // Always update if lines have changed or if this is the first update
        if currentLines.count != context.coordinator.lastLineCount || context.coordinator.lastLineCount == -1 {
            context.coordinator.lastLineCount = currentLines.count
            context.coordinator.updateLines(currentLines, frame: currentFrame)
        }
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
            
            // Check if lines have changed and update if needed
            let currentLines = arManager.detectedLines
            if currentLines.count != lastLineCount {
                lastLineCount = currentLines.count
                DispatchQueue.main.async { [weak self] in
                    self?.updateLines(currentLines, frame: frame)
                }
            }
        }
        
        func updateLines(_ lines: [DetectedLine], frame: ARFrame?) {
            guard let arView = arView else {
                print("DEBUG: ARView is nil, cannot update lines")
                return
            }
            
            print("DEBUG: updateLines called with \(lines.count) lines, frame: \(frame != nil ? "available" : "nil")")
            
            // Remove old anchor if exists
            if let oldAnchor = cameraAnchor {
                arView.scene.removeAnchor(oldAnchor)
            }
            
            guard !lines.isEmpty else {
                print("DEBUG: No lines to display")
                return
            }
            
            // Create new anchor for lines (attached to camera)
            let newCameraAnchor = AnchorEntity(.camera)
            arView.scene.addAnchor(newCameraAnchor)
            cameraAnchor = newCameraAnchor
            
            // Create 3D line entities for each detected line
            // IMPORTANT: RealityKit uses different coordinate system than ARKit camera coordinates
            // ARKit camera: X right, Y up, Z forward (positive Z is forward)
            // RealityKit camera anchor: X right, Y up, Z backward (negative Z is forward)
            var entityCount = 0
            for (index, line) in lines.enumerated() {
                // Get original ARKit camera coordinates (Z is positive forward)
                let originalZ1 = line.point3D1.z
                let originalZ2 = line.point3D2.z
                
                // Validate original depth first (before conversion)
                if originalZ1 <= 0 || originalZ2 <= 0 || originalZ1 > 10.0 || originalZ2 > 10.0 {
                    print("DEBUG: Line \(index) has invalid depth (z1=\(originalZ1), z2=\(originalZ2)), skipping")
                    continue
                }
                
                if originalZ1 < 0.1 || originalZ2 < 0.1 {
                    print("DEBUG: Line \(index) too close to camera (z < 0.1m), skipping")
                    continue
                }
                
                // Convert from ARKit camera coordinates to RealityKit coordinates
                // In RealityKit, negative Z is forward, so we need to negate Z
                let point1 = simd_float3(line.point3D1.x, line.point3D1.y, -line.point3D1.z)
                let point2 = simd_float3(line.point3D2.x, line.point3D2.y, -line.point3D2.z)
                
                print("DEBUG: Line \(index): original p1=\(line.point3D1), p2=\(line.point3D2), converted p1=\(point1), p2=\(point2), length=\(line.length3D)m")
                
                print("DEBUG: Line \(index) passed validation, creating entity with converted p1=\(point1), p2=\(point2)")
                
                // Create line entity (YELLOW for detected lines)
                let lineEntity = createLineEntity(from: point1, to: point2, color: .yellow)
                
                // Check if entity was created successfully
                let hasModel = lineEntity.components[ModelComponent.self] != nil
                let hasChildren = lineEntity.children.count > 0
                print("DEBUG: Line \(index) entity check: hasModel=\(hasModel), hasChildren=\(hasChildren), position=\(lineEntity.position), orientation=\(lineEntity.orientation)")
                
                if hasModel || hasChildren {
                    newCameraAnchor.addChild(lineEntity)
                    entityCount += 1
                    print("DEBUG: Line \(index) entity added to anchor. Anchor children count: \(newCameraAnchor.children.count)")
                } else {
                    print("DEBUG: Line \(index) entity creation failed - no model component or children")
                }
            }
            
            print("DEBUG: Created \(entityCount) line entities and added to scene (total lines: \(lines.count))")
            print("DEBUG: Camera anchor position: \(newCameraAnchor.position), children: \(newCameraAnchor.children.count)")
            
            // Verify anchor is in scene
            let anchorsInScene = arView.scene.anchors
            if anchorsInScene.contains(where: { $0 === newCameraAnchor }) {
                print("DEBUG: Camera anchor is in scene")
            } else {
                print("DEBUG: WARNING - Camera anchor is NOT in scene!")
            }
            
            // Print first entity details for debugging
            if let firstEntity = newCameraAnchor.children.first as? ModelEntity {
                print("DEBUG: First entity details - position: \(firstEntity.position), hasModel: \(firstEntity.components[ModelComponent.self] != nil)")
            }
        }
        
        private func createLineEntity(from start: simd_float3, to end: simd_float3, color: UIColor) -> Entity {
            // Calculate line direction and length
            let direction = end - start
            let length = simd_length(direction)
            
            print("DEBUG: Creating line entity: start=\(start), end=\(end), length=\(length)m")
            
            guard length > 0.001 else {
                print("DEBUG: Line too short, skipping")
                return Entity()
            }
            
            // Create a cylinder mesh for the line
            // Cylinder is created along Y-axis by default
            // Increase radius significantly for better visibility
            let lineMesh = MeshResource.generateCylinder(height: length, radius: 0.02) // 2cm radius (very visible)
            
            // Create material with bright yellow color
            var material = SimpleMaterial()
            material.color = .init(tint: UIColor.systemYellow, texture: nil)  // Use systemYellow for brighter color
            material.metallic = 0.0
            material.roughness = 0.0  // Zero roughness for maximum brightness
            
            // Create model entity
            let lineEntity = ModelEntity(mesh: lineMesh, materials: [material])
            
            // Position and orient the line
            // Calculate midpoint
            let midpoint = (start + end) / 2.0
            
            // Calculate rotation to align cylinder (default Y-axis) with line direction
            let normalizedDirection = simd_normalize(direction)
            let defaultAxis = simd_float3(0, 1, 0)  // Cylinder default axis (Y-up)
            
            // Calculate rotation quaternion using look-at method
            let dot = simd_dot(defaultAxis, normalizedDirection)
            
            // Handle edge cases
            if abs(dot - 1.0) < 0.001 {
                // Already aligned, no rotation needed
                lineEntity.position = midpoint
                return lineEntity
            } else if abs(dot + 1.0) < 0.001 {
                // Opposite direction, rotate 180 degrees around X or Z
                let rotation = simd_quatf(angle: Float.pi, axis: simd_float3(1, 0, 0))
                lineEntity.position = midpoint
                lineEntity.orientation = rotation
                return lineEntity
            }
            
            // General case: calculate rotation axis and angle
            let rotationAxis = simd_cross(defaultAxis, normalizedDirection)
            let rotationAngle = acosf(max(-1.0, min(1.0, dot)))
            let rotation = simd_quatf(angle: rotationAngle, axis: simd_normalize(rotationAxis))
            
            // Set position and orientation
            lineEntity.position = midpoint
            lineEntity.orientation = rotation
            
            return lineEntity
        }
    }
}
