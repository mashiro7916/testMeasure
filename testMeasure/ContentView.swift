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
        // Only AR camera view with 3D lines
        // Use onChange to force update when lines change
        ARViewContainer(arManager: arManager)
            .edgesIgnoringSafeArea(.all)
            .onChange(of: arManager.detectedLines.count) { newCount in
                print("DEBUG: ContentView detectedLines count changed to \(newCount)")
            }
    }
}

#Preview {
    ContentView()
}
