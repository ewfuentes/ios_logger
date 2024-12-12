//
//  LogManager.swift
//  logger
//
//  Created by Erick Fuentes on 12/10/24.
//

import Foundation
import CoreMotion
import AVFoundation

struct Record: Codable {
    let time: Double
    let number: Int?
    let sensor: IMUMeasurement?
    let gps: GPSMeasurement?
    let frames: [FrameInfo]?
    
    init (time: Double,
          sensor: IMUMeasurement? = nil,
          gps: GPSMeasurement? = nil,
          number: Int? = nil,
          frames: [FrameInfo]? = nil) {
        self.time = time
        self.sensor = sensor
        self.gps = gps
        self.number = number
        self.frames = frames
    }
}

enum IMUSensorType: String, Codable {
    case accelerometer
    case gyroscope
}

struct IMUMeasurement: Codable {
    let type: IMUSensorType
    let values: [Double]
}

struct GPSMeasurement: Codable {
    let latitude: Double
    let longitude: Double
    let heading_deg: Double
    let altitude_m: Double
    let accuracy: Double
    let vertical_accuracy_m: Double
    let heading_accuracy_deg: Double
}

enum ColorFormat: String, Codable {
    case rgb
    case gray
}

struct FrameInfo: Codable {
    let cameraInd: Int
    let time_s: Double
    let colorFormat: ColorFormat
    let depthScale: Double?
    let exposureTimeSeconds: Double?
    let calibration: CameraParameters
    
}



struct CameraParameters: Codable {
    let focalLengthX: Float
    let focalLengthY: Float
    let principalPointX: Float
    let principalPointY: Float
//    let distortionModel: Double
//    let distortionCoefficients: [Double]
    
}


class LogManager: ObservableObject {
    private var logDir: URL?
    private var jsonData: FileHandle?
    private var dispatchQueue = DispatchQueue(label: "log_manager_queue", qos: .userInitiated)
    
    deinit {
        if jsonData != nil {
            do {
                try jsonData?.close()
            } catch {
                print("Failed to close json file \(error)")
            }
        }
    }
    
    func startLog() {
        logDir = getLogDirectory()
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: logDir!, withIntermediateDirectories: true)
            let jsonDataPath = logDir?.appendingPathComponent("data.jsonl")
            fm.createFile(atPath: jsonDataPath!.relativePath, contents: nil)
            
            jsonData = try FileHandle(forWritingTo: jsonDataPath!)
        } catch {
            print("Error creating log directory: \(error)")
        }
        print("Creating log in \(logDir!)")
    }
    
    func endLog() {
        print("Closing log in \(logDir!)")
        do {
            try jsonData?.synchronize()
            try jsonData?.close()
        } catch {
            print("Failed to close json file \(error)")
        }
        jsonData = nil
        logDir = nil
    }
    
    private func writeRecordToLog(_ record: Record) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
//            print("Encoding record: \(record)")
            let jsonLine = try encoder.encode(record)
            try self.jsonData?.write(contentsOf: jsonLine)
            try self.jsonData?.write(contentsOf: "\r\n".data(using: .utf8)!)
        } catch {
            print("Failed to encode Record \(error) \(record)")
        }
    }
    
    func handleAccelMeasurement(meas: CMAccelerometerData) {
        dispatchQueue.async {
            let record = Record(
                time: meas.timestamp,
                sensor: IMUMeasurement(
                    type: .accelerometer,
                    values: [
                        meas.acceleration.x,
                        meas.acceleration.y,
                        meas.acceleration.z])
            )
            self.writeRecordToLog(record)
        }
    }
    
    func handleGyroMeasurement(meas: CMGyroData) {
        dispatchQueue.async {
            let record = Record(
                time: meas.timestamp,
                sensor: IMUMeasurement(
                    type: .gyroscope,
                    values: [
                        meas.rotationRate.x,
                        meas.rotationRate.y,
                        meas.rotationRate.z])
            )
            
            self.writeRecordToLog(record)
        }
    }
    
    func handleGPSMeasurement(meas: [CLLocation]) {
        dispatchQueue.async {
            let bootTime: Date = Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
            for m in meas {
                let time_since_boot_s: TimeInterval = m.timestamp.timeIntervalSince(bootTime)
                let record = Record(
                    time: time_since_boot_s,
                    gps: GPSMeasurement(
                        latitude: m.coordinate.latitude,
                        longitude: m.coordinate.longitude,
                        heading_deg: m.course,
                        altitude_m: m.altitude,
                        accuracy: m.horizontalAccuracy,
                        vertical_accuracy_m: m.verticalAccuracy,
                        heading_accuracy_deg: m.courseAccuracy
                    )
                )
                self.writeRecordToLog(record)
            }
        }
    }
    
    func handleFrames(
        frameNumber: Int,
        video: AVCaptureSynchronizedSampleBufferData,
        depth: AVCaptureSynchronizedDepthData
    ) {
        let calib = depth.depthData.cameraCalibrationData
        let record = Record(
            time: video.timestamp.seconds,
            number: frameNumber,
            frames: [
                // RGB Frame Info
                FrameInfo(cameraInd: 0,
                          time_s: video.timestamp.seconds,
                          colorFormat: .rgb,
                          depthScale: nil,
                          exposureTimeSeconds: 1 / 30.0,
                          calibration: CameraParameters(
                            focalLengthX: calib!.intrinsicMatrix[0, 0],
                            focalLengthY: calib!.intrinsicMatrix[1, 1],
                            principalPointX: calib!.intrinsicMatrix[2, 0],
                            principalPointY: calib!.intrinsicMatrix[2, 1])),
                // Depth Frame info
                FrameInfo(cameraInd: 1,
                          time_s: depth.timestamp.seconds,
                          colorFormat: .gray,
                          depthScale: 1.0,
                          exposureTimeSeconds: nil,
                          calibration: CameraParameters(
                            focalLengthX: calib!.intrinsicMatrix[0, 0] / 6.0,
                            focalLengthY: calib!.intrinsicMatrix[1, 1] / 6.0,
                            principalPointX: calib!.intrinsicMatrix[2, 0] / 6.0,
                            principalPointY: calib!.intrinsicMatrix[2, 1] / 6.0))
            ]
        )
        
        dispatchQueue.async {
            self.writeRecordToLog(record)
        }
        
    }
    
    func getDepthMapFolder() -> URL? {
        guard let logDir = logDir else { return nil }
        
        return logDir.appendingPathComponent("frames2")
    }
    
    func getCurrentLogDirectory() -> URL? {
        return logDir
    }
    
    private func getLogDirectory() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let folderName = dateFormatter.string(from: Date())
        let fileURL = documentsDirectory.appendingPathComponent(folderName)
        return fileURL
    }
}
