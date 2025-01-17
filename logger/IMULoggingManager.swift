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
    var startTime: Double?
    var logManager: LogManager?
    
    init() {
        // Set up motion manager
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.01
        motionManager?.gyroUpdateInterval = 0.01
    }
    
    func startIMUUpdates() {
        if let motionManager = motionManager, motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
                if let data = data, self.isRecording {
                    self.logManager?.handleAccelMeasurement(meas: data)
                }
            }
        }
        
        if let motionManager = motionManager, motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: OperationQueue.main) { (data, error) in
                if let data = data, self.isRecording {
                    self.logManager?.handleGyroMeasurement(meas: data)
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
    }
}
