//
//  ContentView.swift
//  testMeasure
//
//  Created by jacky72503 on 2025/12/15.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var arManager = ARDataManager()
    
    var body: some View {
        ZStack {
            // AR Camera View (background)
            ARViewContainer(arManager: arManager)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Top info bar
                HStack {
                    Text("Lines: \(arManager.detectedLines.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    if arManager.selectedLineIndex >= 0 {
                        Text(String(format: "Length: %.2f cm", arManager.measuredLength * 100))
                            .font(.headline)
                            .foregroundColor(.yellow)
                            .padding(8)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                    }
                }
                .padding()
                
                Spacer()
                
                // Main display with line detection overlay
                if let image = arManager.displayImage {
                    GeometryReader { geometry in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.6)
                            .border(Color.white, width: 2)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        // Handle tap to select line
                                        let imageSize = CGSize(
                                            width: geometry.size.width,
                                            height: geometry.size.height * 0.6
                                        )
                                        arManager.selectLineNear(point: value.location, imageSize: imageSize)
                                    }
                            )
                    }
                    .frame(height: 400)
                }
                
                Spacer()
                
                // Line selection list
                if !arManager.detectedLines.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(arManager.detectedLines.enumerated()), id: \.offset) { index, line in
                                Button(action: {
                                    arManager.selectLine(at: index)
                                }) {
                                    VStack {
                                        Text("Line \(index + 1)")
                                            .font(.caption)
                                        Text(String(format: "%.0f px", line.length2D))
                                            .font(.caption2)
                                    }
                                    .padding(8)
                                    .background(index == arManager.selectedLineIndex ? Color.green : Color.blue.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 60)
                }
                
                // Measurement result
                if arManager.selectedLineIndex >= 0 {
                    VStack(spacing: 8) {
                        Text("Measured Length")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack {
                            Text(String(format: "%.2f", arManager.measuredLength * 100))
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.green)
                            Text("cm")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        
                        Text(String(format: "(%.3f m)", arManager.measuredLength))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
