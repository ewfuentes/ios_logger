//
//  CameraDepthManager.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import AVFoundation
import UIKit

class CameraDepthManager: NSObject, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var depthDataOutput: AVCaptureDepthDataOutput?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var depthImageView: UIImageView?
    var isRecording = false
    var depthDataLog: [(timestamp: Double, depthData: AVDepthData?)] = []
    var startTime: Double?
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    func createPreviewView() -> UIView {
        let previewView = UIView(frame: UIScreen.main.bounds)
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
        videoPreviewLayer?.frame = previewView.layer.bounds
        if let videoPreviewLayer = videoPreviewLayer {
            previewView.layer.addSublayer(videoPreviewLayer)
        }
        return previewView
    }
    
    func setupCaptureSession() {
        // Initialize the capture session
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        // Set up the Lidar camera device
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            print("Failed to get the Lidar camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                print("Could not add input to the capture session")
                return
            }
        } catch {
            print("Error creating camera input: \(error)")
            return
        }
        
        // Set up the depth data output
        depthDataOutput = AVCaptureDepthDataOutput()
        guard let depthDataOutput = depthDataOutput else { return }
        let depthDataQueue = DispatchQueue(label: "com.example.depthDataQueue", qos: .userInitiated)
        depthDataOutput.setDelegate(self, callbackQueue: depthDataQueue)
        depthDataOutput.isFilteringEnabled = true // Optional: Apply temporal smoothing
        if captureSession.canAddOutput(depthDataOutput) {
            captureSession.addOutput(depthDataOutput)
        } else {
            print("Could not add depth data output to the capture session")
            return
        }
        
        // Set up the video data output
        videoDataOutput = AVCaptureVideoDataOutput()
        guard let videoDataOutput = videoDataOutput else { return }
        let videoDataQueue = DispatchQueue(label: "com.example.videoDataQueue", qos: .userInitiated)
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add video data output to the capture session")
            return
        }
    }
    
    func startSession() {
        guard let captureSession = captureSession else { return }
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        guard let captureSession = captureSession else { return }
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.stopRunning()
            }
        }
    }
    
    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startTime = CFAbsoluteTimeGetCurrent()
            depthDataLog.removeAll()
            print("Started recording depth data")
        } else {
            saveDepthDataLog()
            print("Stopped recording depth data and saved to disk")
        }
    }
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        print("Received depth data at timestamp: \(timestamp.seconds)")
        
        if isRecording {
            logDepthData(depthData: depthData)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer")
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        DispatchQueue.main.async {
            self.depthImageView?.image = image
        }
    }
    
    func logDepthData(depthData: AVDepthData) {
        let timestamp = CFAbsoluteTimeGetCurrent() - (startTime ?? CFAbsoluteTimeGetCurrent())
        depthDataLog.append((timestamp: timestamp, depthData: depthData))
    }
    
    func saveDepthDataLog() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("depthDataLog.csv")
        
        var csvText = "timestamp\n"
        for entry in depthDataLog {
            let line = "\(entry.timestamp)\n"
            csvText.append(line)
        }
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Depth data saved to: \(fileURL.path)")
        } catch {
            print("Failed to save depth data: \(error)")
        }
    }
}
