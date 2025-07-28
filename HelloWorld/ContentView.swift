//
//  ContentView.swift
//  HelloWorld
//
//  Created by Joshua Sargent on 7/27/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recordingManager = RecordingManager()
    
    var body: some View {
        TabView {
            RecordingView(recordingManager: recordingManager)
                .tabItem {
                    Image(systemName: "mic.circle")
                    Text("Record")
                }
            
            RecordingsListView(recordingManager: recordingManager)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Recordings")
                }
        }
    }
}

#Preview {
    ContentView()
}
