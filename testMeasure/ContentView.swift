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
        ARViewContainer(arManager: arManager)
            .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
