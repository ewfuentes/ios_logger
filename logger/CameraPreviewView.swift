//
//  CameraPreviewView.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let cameraDepthManager: CameraDepthManager

    func makeUIView(context: Context) -> UIView {
        return cameraDepthManager.createPreviewView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Leave empty since we don't need to update the view dynamically
    }
}
