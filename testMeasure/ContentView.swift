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
            ARViewContainer(arManager: arManager)
                .edgesIgnoringSafeArea(.all)
            
            // Display OpenCV grayscale image in corner
            VStack {
                Spacer()
                HStack {
                    if let grayImage = arManager.opencvGrayscaleImage {
                        Image(uiImage: grayImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 150)
                            .border(Color.white, width: 2)
                            .overlay(
                                Text("OpenCV Gray")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.6)),
                                alignment: .topLeading
                            )
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }
}

#Preview {
    ContentView()
}
