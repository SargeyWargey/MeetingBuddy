import Foundation
import Network

/// Monitors network connectivity and provides offline/online status
@MainActor
class NetworkMonitor: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var isConnected = false
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    @Published private(set) var isExpensive = false
    
    // MARK: - Private Properties
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    // MARK: - Initialization
    init() {
        startMonitoring()
    }
    
    deinit {
        monitor.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring network connectivity
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updateConnectionStatus(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Stops monitoring network connectivity
    func stopMonitoring() {
        monitor.cancel()
    }
    
    /// Checks if the device has internet connectivity
    var hasInternetConnection: Bool {
        return isConnected
    }
    
    /// Checks if the connection is suitable for cloud transcription
    var isSuitableForCloudTranscription: Bool {
        return isConnected && !isExpensive
    }
    
    // MARK: - Private Methods
    
    private func updateConnectionStatus(_ path: NWPath) {
        let wasConnected = isConnected
        
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        
        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = nil
        }
        
        // Post notification if connection status changed
        if wasConnected != isConnected {
            NotificationCenter.default.post(name: .networkStatusChanged, object: self)
        }
    }
}

// MARK: - Connection Type Extension
extension NWInterface.InterfaceType {
    var displayName: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Other"
        @unknown default:
            return "Unknown"
        }
    }
}