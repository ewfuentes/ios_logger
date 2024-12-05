import CoreLocation

class GPSLoggingManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let locationManager: CLLocationManager
    @Published var isRecording = false
    @Published var locationLog: [(timestamp: Double, location: CLLocation?)] = []
    private var startTime: Double?
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        
        // Set up location manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.allowsBackgroundLocationUpdates = true // Add if background updates needed
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        // Check authorization status before starting
        let authStatus = locationManager.authorizationStatus
        guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else {
            print("Location authorization not granted")
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    // Add authorization callback
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isRecording {
                startUpdatingLocation()
            }
        default:
            locationManager.stopUpdatingLocation()
            print("Location authorization denied")
        }
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
        print("logging location!");
        let timestamp = CFAbsoluteTimeGetCurrent() - (startTime ?? CFAbsoluteTimeGetCurrent())
        locationLog.append((timestamp: timestamp, location: location))
    }
    
    func saveLocationLog() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("locationLog.csv")
        
        var csvText = "timestamp_s,latitude,longitude,altitude_m,horiz_accuracy_m,vert_accuracy_m,speed_mps,speed_accuracy_mps,course_deg_rel_due_north,course_acc_deg\n"
        for entry in locationLog {
            if let location = entry.location {
                let line = "\(entry.timestamp),\(location.coordinate.latitude),\(location.coordinate.longitude),\(location.altitude),\(location.horizontalAccuracy),\(location.verticalAccuracy),\(location.speed),\(location.speedAccuracy),\(location.course),\(location.courseAccuracy)\n"
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
