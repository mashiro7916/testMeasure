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
            
            // Status overlay
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saved Frames: \(arManager.savedCount)")
                            .font(.headline)
                            .foregroundColor(.white)
                        if arManager.isProcessing {
                            Text("Processing...")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
}
