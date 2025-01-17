//
//  CameraDepthManager.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import AVFoundation
import UIKit


func saveDepth16PixelBufferAsTIFFWithoutNormalization(_ pixelBuffer: CVPixelBuffer, to url: URL) {
    // Ensure the pixel buffer has the expected format
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 else {
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
    let bitsPerComponent = 32 // Depth16 uses 16 bits per component
    let bytesPerRow = rowBytes
    let bitmapInfo = (CGImageAlphaInfo.none.rawValue |
                    CGBitmapInfo.byteOrder32Little.rawValue |
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
//        print("TIFF file successfully saved to \(url).")
    } else {
        print("Failed to save the TIFF file.")
    }
}

func getOutputDirectory() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}


class CameraDepthManager: NSObject, AVCaptureDataOutputSynchronizerDelegate, ObservableObject {
    var captureSession: AVCaptureSession?
    var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var depthDataOutput: AVCaptureDepthDataOutput?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var depthImageView: UIImageView?
    var videoCapture: VideoCapture?
    var logPath: URL?
    var logManager: LogManager?
    var startTime: Double?
    var synchronizerDispatchQueue = DispatchQueue(label: "syncQueue")
    
    private var ciContext = CIContext()
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    private func isRecording() -> Bool {
        return logPath != nil
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
        // fix the focal length
        videoCaptureDevice.setFocusModeLocked(lensPosition: 0.75) { _ in }
        
        
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
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add video data output to the capture session")
            return
        }

        captureSession.commitConfiguration()

        dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        dataOutputSynchronizer?.setDelegate(self, queue: synchronizerDispatchQueue)
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
    
    func setRecordingStatus(logPath: URL?) {
        synchronizerDispatchQueue.async {
            if self.logPath != nil {
                // Stop an existing log one currently exists
                print("Stopped recording depth data")
                self.videoCapture?.finishWriting { outputURL in
                    print("Video saved to \(outputURL?.absoluteString ?? "Unknown location")")
                }
                self.videoCapture = nil
            }
            
            self.logPath = logPath
            
            if self.logPath != nil {
                // Start a new log if required
                self.startTime = CFAbsoluteTimeGetCurrent()
                
                self.videoCapture = VideoCapture()
                let videoFile = self.logPath?.appendingPathComponent("data.mov")
                
                let width = self.videoDataOutput?.videoSettings["Width"] as! Double
                let height = self.videoDataOutput?.videoSettings["Height"] as! Double
                let size = CGSize(width: width, height: height)
                do {
                    try self.videoCapture?.setupWriter(outputFileURL: videoFile!, frameSize: size)
                } catch {
                    print("Unable to create output video file: \(videoFile!)")
                }
                self.videoCapture?.startWriting()
                print("Started recording depth data")
            }
        }
    }
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let videoDataOutput = videoDataOutput else { return }
        guard let depthDataOutput = depthDataOutput else { return }
        
        let videoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData
        let depthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData

        guard let videoData = videoData else {
            print("Could not extract rgb frame from synchronized bundle")
            return
        }
        guard let depthData = depthData else {
            print("Could not extract depth frame from synchronized bundle")
            return
        }

        guard !videoData.sampleBufferWasDropped, !depthData.depthDataWasDropped else {
            print("Incomplete synchronized frame depth dropped? \(videoData.sampleBufferWasDropped) rgb dropped? \(depthData.depthDataWasDropped)")
            return
        }
        
        // print("Recieved Synchronized Frames depth - rgb dt: \(CMTimeGetSeconds(depthData.timestamp - videoData.timestamp))")
        if isRecording() {
            // Note that the frame number from the video capture should be grabbed before a frame is added
            let frameNumber: Int = videoCapture!.frameNumber
            logDepthData(depthData: depthData.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32),
                         frameNumber: frameNumber)
            
            logManager?.handleFrames(frameNumber: frameNumber, video: videoData, depth: depthData)
            videoCapture?.addFrame(pixelBuffer: videoData.sampleBuffer.imageBuffer!, at: videoData.timestamp)
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) else {
            print("Failed to get image buffer from sample buffer")
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return
        }

        let image = UIImage(cgImage: cgImage)

        DispatchQueue.main.async {
            self.depthImageView?.image = image
        }
    }
    
    func logDepthData(depthData: AVDepthData, frameNumber: Int) {
        do {
            let folderPath = logPath?.appendingPathComponent("frames2")
            if !FileManager.default.fileExists(atPath: folderPath!.absoluteString) {
                try FileManager.default.createDirectory(at: folderPath!, withIntermediateDirectories: true)
            }
            
            let fileURL = folderPath!.appendingPathComponent("\(String(format: "%08d", frameNumber)).tiff")
            saveDepth16PixelBufferAsTIFFWithoutNormalization(depthData.depthDataMap, to: fileURL)
        } catch {
            print("Error saving depth data: \(error)")
        }
    }
}


class VideoCapture: NSObject {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var frameNumber: Int = 0
    private var outputURL: URL?
    private var startTime: CMTime?

    func setupWriter(outputFileURL: URL, frameSize: CGSize) throws {
        // Save the output URL for later
        self.outputURL = outputFileURL

        // Initialize the asset writer
        assetWriter = try AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)

        // Configure video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: frameSize.width,
            AVVideoHeightKey: frameSize.height
        ]

        // Create video input
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        // Create a pixel buffer adaptor
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: frameSize.width,
            kCVPixelBufferHeightKey as String: frameSize.height
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        // Add video input to the asset writer
        if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
        } else {
            throw NSError(domain: "VideoCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
    }
    
    func startWriting() {
        guard let assetWriter = assetWriter else { return }

        // Start writing session
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        frameNumber = 0
    }
    
    func addFrame(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if startTime == nil {
            startTime = time
        }
        guard let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else { return }

        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time - startTime!)
        frameNumber += 1
    }
    
    func finishWriting(completion: @escaping (URL?) -> Void) {
        videoInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            if let outputURL = self?.outputURL {
                completion(outputURL)
            } else {
                completion(nil)
            }
        }
    }
}
