//
//  ContentView 2.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import SwiftUI

struct ContentView: View {
    @State private var logIMU = false
    @State private var logGPS = false
    @State private var logCameraDepth = false
    @State private var isRecording = false

    // Instantiate managers
    @StateObject var imuLoggingManager = IMULoggingManager()
    @StateObject var gpsLoggingManager = GPSLoggingManager()
    @StateObject var cameraDepthManager = CameraDepthManager()

    var body: some View {
        NavigationView {
            VStack {
                Text("Welcome to Logger App")
                    .font(.title)
                    .padding()
                
                CameraPreviewView(cameraDepthManager: cameraDepthManager)
                                    .frame(height: 300) // Set the height as desired
                                    .cornerRadius(10)
                                    .padding()

                // Button to start or stop logging based on user selection
                Button(action: {
                    toggleRecording()
                }) {
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                        .font(.headline)
                        .padding()
                        .background(isRecording ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()

                // Navigation link to settings page
                NavigationLink(destination: SettingsView(logIMU: $logIMU, logGPS: $logGPS, logCameraDepth: $logCameraDepth)) {
                    Text("Settings")
                        .font(.headline)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Logger App")
            .onAppear {
                // Start GPS updates and IMU updates when view appears
                gpsLoggingManager.startUpdatingLocation()
                imuLoggingManager.startIMUUpdates()
            }
        }
    }

    func toggleRecording() {
        isRecording.toggle()

        if isRecording {
            if logIMU {
                imuLoggingManager.toggleRecording()
            }
            if logGPS {
                gpsLoggingManager.toggleRecording()
            }
            if logCameraDepth {
                cameraDepthManager.toggleRecording()
                cameraDepthManager.startSession()
            }
            print("Started logging selected streams.")
        } else {
            if logIMU {
                imuLoggingManager.toggleRecording()
            }
            if logGPS {
                gpsLoggingManager.toggleRecording()
            }
            if logCameraDepth {
                cameraDepthManager.toggleRecording()
                cameraDepthManager.stopSession()
            }
            print("Stopped logging selected streams.")
        }
    }
}
