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
                }
                .padding()
                
                Spacer()
                
                // Display image with lines
                if let image = arManager.displayImage {
                    GeometryReader { geometry in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.6)
                            .border(Color.white, width: 2)
                    }
                    .frame(height: 400)
                }
                
                Spacer()
                
                // Line list with distances
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
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
