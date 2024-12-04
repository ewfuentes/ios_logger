//
//  CameraDepthManager.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import AVFoundation
import UIKit
import CoreImage
import CoreVideo

import PNG

//import VideoToolbox


func getPixelFormat(of image: CGImage) {
    // Color space
    if let colorSpace = image.colorSpace {
        print("Color Space: \(colorSpace)")
    } else {
        print("Color Space: None")
    }
    
    // Bits per component
    let bitsPerComponent = image.bitsPerComponent
    print("Bits per Component: \(bitsPerComponent)")
    
    // Bits per pixel
    let bitsPerPixel = image.bitsPerPixel
    print("Bits per Pixel: \(bitsPerPixel)")
    
    // Bitmap info
    let bitmapInfo = image.bitmapInfo
    print("Bitmap Info: \(bitmapInfo)")
    
    // Alpha info
    let alphaInfo = image.alphaInfo
    print("Alpha Info: \(alphaInfo)")
}

func pixelBufferToPNG(_ depthBuffer: [PNG.VA<UInt16>], size: (Int, Int), path: String) throws {
    let layout = PNG.Layout.init(format: .v16(fill: nil, key: nil))
    let image = PNG.Image(packing: depthBuffer, size: size, layout: layout)
    try image.compress(path: path)
}



func convertPixelBufferToMillimetersBuffer(pixelBuffer: CVPixelBuffer) -> ([PNG.VA<UInt16>], (Int, Int))? {
    // Ensure the pixel buffer is 16-bit float format
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat16 else {
        print("Unsupported pixel format")
        return nil
    }
    
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    
    // Create a new CVPixelBuffer for the output in 16-bit integer format
    var outputBuffer = [PNG.VA<UInt16>](repeating: PNG.VA<UInt16>(0), count: width * height)
    
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }
    
    // Access input data
    let inputBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
    let inputBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    
    for y in 0..<height {
        let inputRow = inputBaseAddress.advanced(by: y * inputBytesPerRow).assumingMemoryBound(to: Float16.self)
        
        for x in 0..<width {
            let idx = y * width + x
            let depthInMeters = Float(inputRow[x]) // Convert Float16 to Float
            if depthInMeters.isNaN {
                outputBuffer[idx] = PNG.VA<UInt16>(UInt16.max)
            } else {
                let depthInMillimeters = UInt16((depthInMeters * 1000).rounded(.toNearestOrAwayFromZero))
                outputBuffer[idx] = PNG.VA<UInt16>(depthInMillimeters)
            }
        }
    }
    return (outputBuffer, (width, height))
}


class CameraDepthManager: NSObject, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var depthDataOutput: AVCaptureDepthDataOutput?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var depthImageView: UIImageView?
    var isRecording = false
    var depthDataLog: [(timestamp: Double, depthData: AVDepthData?)] = []
    var startTime: Double?
    private var ciDepthContext = CIContext()
    private var ciContext = CIContext()
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
        
        let preferredWidthResolution = 1920
        
        guard let format = (videoCaptureDevice.formats.last { format in
            format.formatDescription.dimensions.width == preferredWidthResolution &&
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
            !format.isVideoBinned &&
            !format.supportedDepthDataFormats.isEmpty
        }) else {
//            throw ConfigurationError.requiredFormatUnavailable
            print("Could not get required format")
            return
        }


        // Find a match that outputs depth data in the format the app's custom Metal views require.
        guard let depthFormat = (format.supportedDepthDataFormats.last { depthFormat in
            depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
        }) else {
//            throw ConfigurationError.requiredFormatUnavailable
            print("Could not get required format b")
            return
        }


        // Begin the device configuration.
        try? videoCaptureDevice.lockForConfiguration()


        // Configure the device and depth formats.
        videoCaptureDevice.activeFormat = format
        videoCaptureDevice.activeDepthDataFormat = depthFormat


        // Finish the device configuration.
        videoCaptureDevice.unlockForConfiguration()
        
        print("Selected video format: \(videoCaptureDevice.activeFormat)")
        print("Selected depth format: \(String(describing: videoCaptureDevice.activeDepthDataFormat))")

        
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
        depthDataOutput.isFilteringEnabled = false // Optional: Apply temporal smoothing
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
        
//        print("Received depth data at timestamp: \(timestamp.seconds)")
        
        
        if isRecording {
            logDepthData(depthData: depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16))
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer")
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        
//        if isRecording {
//            if let pngData = image.pngData() {
//                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//                let fileURL = documentsURL.appendingPathComponent("color_output.png")
//                try? pngData.write(to: fileURL)
//                print("Color image saved to: \(fileURL)")
//            }
//        }
        
        DispatchQueue.main.async {
            self.depthImageView?.image = image
        }
    }
    
    func logDepthData(depthData: AVDepthData) {
        
        if let (depthBuffer, size) = convertPixelBufferToMillimetersBuffer(pixelBuffer: depthData.depthDataMap) {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsURL.appendingPathComponent("output.png")
            do {
                try pixelBufferToPNG(depthBuffer, size: size, path: fileURL.path())
                print("Image saved to: \(fileURL)")
            } catch {
                print("Failed to save depth data: \(error)")
            }
            
        }
        
//        if let pngData = pixelBufferToPNG(millimeterDepthBuffer!, context: ciContext) {
//            // Save or use the PNG data as needed
//            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//            let fileURL = documentsURL.appendingPathComponent("output.png")
//            try? pngData.write(to: fileURL)
//
//        }
//        let timestamp = CFAbsoluteTimeGetCurrent() - (startTime ?? CFAbsoluteTimeGetCurrent())
        

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
