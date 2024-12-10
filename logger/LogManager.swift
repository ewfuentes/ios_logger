//
//  LogManager.swift
//  logger
//
//  Created by Erick Fuentes on 12/10/24.
//

import Foundation

class LogManager: ObservableObject {
    private var logDir: URL?
    
    
    func startLog() {
        logDir = getLogDirectory()
        do {
            try FileManager.default.createDirectory(at: logDir!, withIntermediateDirectories: true)
        } catch {
            print("Error creating log directory: \(error)")
        }
        print("Creating log in \(logDir!)")
    }
    
    func endLog() {
        print("Closing log in \(logDir!)")
        logDir = nil
    }
    
    func handleAccelMeasurement() {
        
    }
    
    func handleGyroMeasurement() {
        
    }
    
    func handleGPSMeasurement() {
        
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
        dateFormatter.dateFormat = "yyyyMMDD_HHmmss"
        let folderName = dateFormatter.string(from: Date())
        let fileURL = documentsDirectory.appendingPathComponent(folderName)
        return fileURL
    }
}
