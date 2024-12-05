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
import CoreGraphics
import ImageIO
import PNG

//import VideoToolbox

import CoreGraphics
import CoreVideo
import UniformTypeIdentifiers

func saveDepth16PixelBufferAsTIFFWithoutNormalization(_ pixelBuffer: CVPixelBuffer, to url: URL) {
    // Ensure the pixel buffer has the expected format
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat16 else {
        print("Pixel buffer is not in Depth16 format.")
        return
    }
    
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    
    // Get the base address and dimensions of the pixel buffer
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        print("Failed to get base address of the pixel buffer.")
        return
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
    
    // Create a grayscale color space
    guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
        print("Failed to create grayscale color space.")
        return
    }
    
    // Create a bitmap context with the 16-bit depth data
    let bitsPerComponent = 16 // Depth16 uses 16 bits per component
    let bytesPerRow = rowBytes
    let bitmapInfo = (CGImageAlphaInfo.none.rawValue |
                    CGBitmapInfo.byteOrder16Little.rawValue |
                      CGBitmapInfo.floatInfoMask.rawValue)
    
    guard let context = CGContext(data: baseAddress,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: bitsPerComponent,
                                   bytesPerRow: bytesPerRow,
                                   space: colorSpace,
                                   bitmapInfo: bitmapInfo) else {
        print("Failed to create bitmap context.")
        return
    }
    
    // Create a CGImage from the context
    guard let cgImage = context.makeImage() else {
        print("Failed to create CGImage.")
        return
    }
    
    // Save the CGImage as a TIFF file
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
        print("Failed to create image destination.")
        return
    }
    
    CGImageDestinationAddImage(destination, cgImage, nil)
    if CGImageDestinationFinalize(destination) {
        print("TIFF file successfully saved to \(url).")
    } else {
        print("Failed to save the TIFF file.")
    }
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
    
    private var ciDepthContext: CIContext?
    
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
            print("Stopped recording depth data")
        }
    }
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        
        print("Received depth data at timestamp: \(timestamp.seconds)")
        
        if isRecording {
            logDepthData(depthData: depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16), timestamp: timestamp)
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
    
    func logDepthData(depthData: AVDepthData, timestamp: CMTime) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent("output.tiff")
        saveDepth16PixelBufferAsTIFFWithoutNormalization(depthData.depthDataMap, to: fileURL)
        
    }
}
