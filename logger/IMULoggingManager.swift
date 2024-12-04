//
//  IMULoggingManager.swift
//  logger
//
//  Created by Erick Fuentes on 12/2/24.
//


import CoreMotion

class IMULoggingManager: ObservableObject {
    var motionManager: CMMotionManager?
    var isRecording = false
    var imuLog: [(timestamp: Double, accelerometer: CMAcceleration?, gyroscope: CMRotationRate?)] = []
    var startTime: Double?
    
    init() {
        // Set up motion manager
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.1
        motionManager?.gyroUpdateInterval = 0.1
    }
    
    func startIMUUpdates() {
        if let motionManager = motionManager, motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
                if let data = data, self.isRecording {
                    self.logIMUData(accelerometer: data.acceleration, gyroscope: nil)
                }
            }
        }
        
        if let motionManager = motionManager, motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: OperationQueue.main) { (data, error) in
                if let data = data, self.isRecording {
                    self.logIMUData(accelerometer: nil, gyroscope: data.rotationRate)
                }
            }
        }
    }
    
    func stopIMUUpdates() {
        if let motionManager = motionManager, motionManager.isAccelerometerAvailable {
            motionManager.stopAccelerometerUpdates()
        }
        
        if let motionManager = motionManager, motionManager.isGyroAvailable {
            motionManager.stopGyroUpdates()
        }
    }
    
    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startTime = CFAbsoluteTimeGetCurrent()
            imuLog.removeAll()
            print("Started recording IMU data")
        } else {
            saveIMULog()
            print("Stopped recording IMU data and saved to disk")
        }
    }
    
    func logIMUData(accelerometer: CMAcceleration?, gyroscope: CMRotationRate?) {
        let timestamp = CFAbsoluteTimeGetCurrent() - (startTime ?? CFAbsoluteTimeGetCurrent())
        imuLog.append((timestamp: timestamp, accelerometer: accelerometer, gyroscope: gyroscope))
    }
    
    func saveIMULog() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("imuLog.csv")
        
        var csvText = "timestamp,accelerometer_x,accelerometer_y,accelerometer_z,gyroscope_x,gyroscope_y,gyroscope_z\n"
        for entry in imuLog {
            let accel = entry.accelerometer
            let gyro = entry.gyroscope
            let line = "\(entry.timestamp),\(accel?.x ?? 0),\(accel?.y ?? 0),\(accel?.z ?? 0),\(gyro?.x ?? 0),\(gyro?.y ?? 0),\(gyro?.z ?? 0)\n"
            csvText.append(line)
        }
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("IMU data saved to: \(fileURL.path)")
        } catch {
            print("Failed to save IMU data: \(error)")
        }
    }
}
