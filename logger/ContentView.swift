//
//  ContentView 2.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import SwiftUI

struct ContentView: View {
    @State private var logIMU = true
    @State private var logGPS = true
    @State private var logCameraDepth = true
    @State private var isRecording = false

    // Instantiate managers
    @StateObject var logManager = LogManager()
    @StateObject var imuLoggingManager = IMULoggingManager()
    @StateObject var gpsLoggingManager = GPSLoggingManager()
    @StateObject var cameraDepthManager = CameraDepthManager()

    var body: some View {
        VStack {
            Text("Welcome to Logger App")
                .font(.title)
                .padding()
            
            CameraPreviewView(cameraDepthManager: cameraDepthManager)
                                .cornerRadius(10)
                                .padding()

            // Button to start or stop logging based on user selection
            Button(action: {
                try? toggleRecording()
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
            
            imuLoggingManager.startIMUUpdates()
            imuLoggingManager.logManager = self.logManager
            gpsLoggingManager.logManager = self.logManager
            cameraDepthManager.logManager = self.logManager
        }
        .onChange(of: logCameraDepth, initial: true) { _, newValue in
            if newValue {
                cameraDepthManager.startSession()
            } else {
                cameraDepthManager.stopSession()
            }
        }
        .onChange(of: logGPS, initial: true) { _, newValue in
            if newValue {
                gpsLoggingManager.startUpdatingLocation()
            } else {
//                    gpsLoggingManager.locationManager.stopUpdatingLocation()
            }
        }
        .onChange(of: logIMU) {_, newValue in
            if newValue {
                imuLoggingManager.startIMUUpdates()
            } else {
                imuLoggingManager.stopIMUUpdates()
            }
        }
    }

    func toggleRecording() throws {
        isRecording.toggle()

        if isRecording {
            logManager.startLog()
            
            if logIMU {
                imuLoggingManager.toggleRecording()
            }
            if logGPS {
                gpsLoggingManager.toggleRecording()
            }
            if logCameraDepth {
                cameraDepthManager.setRecordingStatus(logPath: logManager.getCurrentLogDirectory())
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
                cameraDepthManager.setRecordingStatus(logPath: nil)
            }
            logManager.endLog()
            print("Stopped logging selected streams.")
        }
    }
}
