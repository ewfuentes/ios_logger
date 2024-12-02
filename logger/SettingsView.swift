//
//  SettingsView.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import SwiftUI

struct SettingsView: View {
    @Binding var logIMU: Bool
    @Binding var logGPS: Bool
    @Binding var logCameraDepth: Bool

    var body: some View {
        Form {
            Section(header: Text("Select Streams to Log")) {
                Toggle("Log IMU Data", isOn: $logIMU)
                Toggle("Log GPS Data", isOn: $logGPS)
                Toggle("Log Camera Depth Data", isOn: $logCameraDepth)
            }
        }
        .navigationTitle("Settings")
    }
}
