//
//  CameraView.swift
//  logger
//
//  Created by Erick Fuentes on 12/1/24.
//

import SwiftUI
import UIKit

struct CameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        return ViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Leave empty since we don't need to update anything
    }
}
