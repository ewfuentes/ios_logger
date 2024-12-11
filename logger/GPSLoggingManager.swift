import CoreLocation

class GPSLoggingManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let locationManager: CLLocationManager
    @Published var isRecording = false
    @Published var locationLog: [(timestamp: Double, location: CLLocation?)] = []
    private var startTime: Double?
    var logManager: LogManager?
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        
        // Set up location manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.allowsBackgroundLocationUpdates = true // Add if background updates needed
        locationManager.pausesLocationUpdatesAutomatically = false
//        locationManager.activityType = .fitness
        
        // print authorization status string
        print("location authorization status:")
        switch locationManager.authorizationStatus {
        case .notDetermined:
            print("Not Determined")
        case .restricted:
            print("Restricted")
        case .denied:
            print("Denied")
        case .authorizedAlways:
            print("Authorized Always")
        case .authorizedWhenInUse:
            print("Authorized When in Use")
        @unknown default:
            print("Unknown")
        }
        print("requesting access")
        locationManager.requestWhenInUseAuthorization()

    }
    
    func startUpdatingLocation() {
        // Check authorization status before starting
        let authStatus = locationManager.authorizationStatus
        guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
            print("Location authorization not granted")
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    // Add authorization callback
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
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
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if isRecording {
            self.logManager?.handleGPSMeasurement(meas: locations)
        }
    }
}
