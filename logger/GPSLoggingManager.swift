import CoreLocation

class GPSLoggingManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    var locationManager: CLLocationManager?
    var isRecording = false
    var locationLog: [(timestamp: Double, location: CLLocation?)] = []
    var startTime: Double?
    
    override init() {
        super.init()
        
        // Set up location manager
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager?.startUpdatingLocation()
    }
    
    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startTime = CFAbsoluteTimeGetCurrent()
            locationLog.removeAll()
            print("Started recording GPS data")
        } else {
            saveLocationLog()
            print("Stopped recording GPS data and saved to disk")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if isRecording {
            logLocation(location: location)
        }
    }
    
    func logLocation(location: CLLocation) {
        let timestamp = CFAbsoluteTimeGetCurrent() - (startTime ?? CFAbsoluteTimeGetCurrent())
        locationLog.append((timestamp: timestamp, location: location))
    }
    
    func saveLocationLog() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("locationLog.csv")
        
        var csvText = "timestamp,latitude,longitude,altitude,accuracy\n"
        for entry in locationLog {
            if let location = entry.location {
                let line = "\(entry.timestamp),\(location.coordinate.latitude),\(location.coordinate.longitude),\(location.altitude),\(location.horizontalAccuracy)\n"
                csvText.append(line)
            }
        }
        
        do {
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("GPS data saved to: \(fileURL.path)")
        } catch {
            print("Failed to save GPS data: \(error)")
        }
    }
}
