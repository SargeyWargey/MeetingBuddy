//
//  ContentView.swift
//  HelloWorld
//
//  Created by Joshua Sargent on 7/27/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecordingView()
                .tabItem {
                    Image(systemName: "mic.circle")
                    Text("Record")
                }
            
            RecordingsListView()
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
