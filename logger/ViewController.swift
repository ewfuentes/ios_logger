import UIKit
import AVFoundation
import CoreMotion

class ViewController: UIViewController, AVCaptureDepthDataOutputDelegate {
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var depthDataOutput: AVCaptureDepthDataOutput?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var currentOutputMode: OutputMode = .rgb
    var depthImageView: UIImageView?
    var motionManager: CMMotionManager?
    var isRecording = false
    var dataLog: [(timestamp: Double, accelerometer: CMAcceleration?, gyroscope: CMRotationRate?, depthData: AVDepthData?)] = []
    var startTime: Double?
    
    enum OutputMode {
        case rgb
        case depth
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        
        // Check if the device supports depth data output
        guard videoCaptureDevice.activeFormat.supportedDepthDataFormats.count > 0 else {
            print("No supported depth data formats available on this device.")
            return
        }
        
        do {
            try videoCaptureDevice.lockForConfiguration()
            videoCaptureDevice.activeDepthDataFormat = videoCaptureDevice.activeFormat.supportedDepthDataFormats.first
            videoCaptureDevice.unlockForConfiguration()
        } catch {
            print("Failed to configure depth data format: \(error)")
            return
        }
        
        // Set up the video preview layer
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let videoPreviewLayer = videoPreviewLayer else { return }
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = view.layer.bounds
        view.layer.addSublayer(videoPreviewLayer)
        
        // Set up the video data output
        videoDataOutput = AVCaptureVideoDataOutput()
        guard let videoDataOutput = videoDataOutput else { return }
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .background))
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add video data output to the capture session")
            return
        }

        
        // Set up the depth data output
        depthDataOutput = AVCaptureDepthDataOutput()
        guard let depthDataOutput = depthDataOutput else { return }
        depthDataOutput.setDelegate(self, callbackQueue: DispatchQueue.main)
        depthDataOutput.isFilteringEnabled = true // Optional: Apply temporal smoothing
        if captureSession.canAddOutput(depthDataOutput) {
            captureSession.addOutput(depthDataOutput)
        } else {
            print("Could not add depth data output to the capture session")
            return
        }
        
        // Connect depth data output to the appropriate connection
        guard let connection = depthDataOutput.connection(with: .depthData) else {
            print("Failed to establish connection for depth data output")
            return
        }
        connection.isEnabled = true
        
        // Set up depth image view
        depthImageView = UIImageView(frame: view.bounds)
        depthImageView?.contentMode = .scaleAspectFit
        depthImageView?.isHidden = true
        if let depthImageView = depthImageView {
            view.addSubview(depthImageView)
        }
        
        // Start the capture session on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        
        // Add a button to switch between RGB and Depth output
        let switchButton = UIButton(type: .system)
        switchButton.setTitle("Switch Output Mode", for: .normal)
        switchButton.addTarget(self, action: #selector(switchOutputMode), for: .touchUpInside)
        switchButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(switchButton)
        
        // Add a button to start/stop recording data
        let recordButton = UIButton(type: .system)
        recordButton.setTitle("Start Recording", for: .normal)
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordButton)

        // Add a button to share the recorded data
        let shareButton = UIButton(type: .system)
        shareButton.setTitle("Share Data", for: .normal)
        shareButton.addTarget(self, action: #selector(shareDataLog), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareButton)
        
        NSLayoutConstraint.activate([
            switchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            switchButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            shareButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shareButton.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: switchButton.topAnchor, constant: -20)
        ])
        
        // Set up the motion manager
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.1
        motionManager?.gyroUpdateInterval = 0.1
        
        // Start accelerometer updates
        if let motionManager = motionManager, motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
                if let data = data, self.isRecording {
                    self.logData(accelerometer: data.acceleration, gyroscope: nil, depthData: nil)
                }
            }
        }
        
        // Start gyroscope updates
        if let motionManager = motionManager, motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: OperationQueue.main) { (data, error) in
                if let data = data, self.isRecording {
                    self.logData(accelerometer: nil, gyroscope: data.rotationRate, depthData: nil)
                }
            }
        }
    }
    
    @objc func switchOutputMode() {
        guard let videoPreviewLayer = videoPreviewLayer else { return }
        guard let depthImageView = depthImageView else { return }
        
        if currentOutputMode == .rgb {
            // Switch to depth output
            currentOutputMode = .depth
            videoPreviewLayer.isHidden = true
            depthImageView.isHidden = false
            print("Switched to Depth Output Mode")
        } else {
            // Switch to RGB output
            currentOutputMode = .rgb
            videoPreviewLayer.isHidden = false
            depthImageView.isHidden = true
            print("Switched to RGB Output Mode")
        }
    }

    @objc func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startTime = CACurrentMediaTime()
            dataLog.removeAll()
            print("Started recording data")
            
        } else {
            saveDataLog()
            print("Stopped recording data and saved to disk")
        }
    }

    
    func logData(accelerometer: CMAcceleration?, gyroscope: CMRotationRate?, depthData: AVDepthData?) {
    let timestamp = CACurrentMediaTime() - (startTime ?? CACurrentMediaTime())
    DispatchQueue.global(qos: .background).async {
        self.dataLog.append((timestamp: timestamp, accelerometer: accelerometer, gyroscope: gyroscope, depthData: depthData))
    }
}
    
    func saveDataLog() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("dataLog.csv")
        
        var csvText = "timestamp,accelerometer_x,accelerometer_y,accelerometer_z,gyroscope_x,gyroscope_y,gyroscope_z\r\n"
        for entry in dataLog {
            let accel = entry.accelerometer
            let gyro = entry.gyroscope
            let line = "\(entry.timestamp),\(accel?.x ?? 0),\(accel?.y ?? 0),\(accel?.z ?? 0),\(gyro?.x ?? 0),\(gyro?.y ?? 0),\(gyro?.z ?? 0)\r\n"
            csvText.append(line)
        }
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Data saved to: \(fileURL.path)")
        } catch {
            print("Failed to save data: \(error)")
        }
    }
    
    @objc func shareDataLog() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let originalFileURL = documentsDirectory.appendingPathComponent("dataLog.csv")
        
        guard FileManager.default.fileExists(atPath: originalFileURL.path) else {
            print("No data log file found to share")
            return
        }

        // Copy the file to the temporary directory for sharing
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("dataLog.csv")
        
        do {
            if FileManager.default.fileExists(atPath: tempFileURL.path) {
                try FileManager.default.removeItem(at: tempFileURL)
            }
            try FileManager.default.copyItem(at: originalFileURL, to: tempFileURL)
        } catch {
            print("Failed to copy file to temporary directory: \(error)")
            return
        }
        
        // Gather RGB frames to share
        let rgbFiles = (try? FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).filter { $0.pathExtension == "jpg" }) ?? []
        
        var itemsToShare: [URL] = [tempFileURL]
        itemsToShare.append(contentsOf: rgbFiles)
        
        let activityViewController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    
    // Simplest version of depthDataOutput
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        print("Received depth data at timestamp: \(timestamp.seconds)")
        
        if isRecording {
            logData(accelerometer: nil, gyroscope: nil, depthData: depthData)
        }
        
        // Convert depth data to a simple grayscale image
        let depthMap = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        var ciImage = CIImage(cvPixelBuffer: depthMap)
        ciImage = ciImage.oriented(.right).transformed(by: CGAffineTransform(scaleX: self.view.bounds.width / CGFloat(width), y: self.view.bounds.height / CGFloat(height)))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            return
        }
        
        let depthImage = UIImage(cgImage: cgImage)
        DispatchQueue.main.async {
            self.depthImageView?.image = depthImage
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording else { return }
        
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
        
        // Save the image to disk
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to get JPEG representation of the RGB frame")
            return
        }

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("rgbFrame_\(Date().timeIntervalSince1970).jpg")

        do {
            try imageData.write(to: fileURL)
            print("RGB frame saved to: \(fileURL.path)")
        } catch {
            print("Failed to save RGB frame: \(error)")
        }
    }
}
