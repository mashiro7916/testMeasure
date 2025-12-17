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
            // Display image with lines (full screen)
            if let image = arManager.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .clipped()
                    .edgesIgnoringSafeArea(.all)
            } else {
                // Fallback to AR view if no image
                ARViewContainer(arManager: arManager)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Overlay info
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
                }
                .padding()
                
                Spacer()
                
                // Line list with distances (bottom overlay)
                if !arManager.detectedLines.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(arManager.detectedLines.enumerated()), id: \.offset) { index, line in
                                HStack {
                                    Text("Line \(index + 1)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text(String(format: "%.2f cm", line.length3D * 100))
                                        .font(.headline)
                                        .foregroundColor(.yellow)
                                    
                                    Text(String(format: "(%.3f m)", line.length3D))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(Color.black.opacity(0.3))
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
