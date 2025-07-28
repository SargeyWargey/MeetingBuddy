import XCTest
import Network
@testable import HelloWorld

@MainActor
final class NetworkMonitorTests: XCTestCase {
    
    var networkMonitor: NetworkMonitor!
    
    override func setUp() {
        super.setUp()
        networkMonitor = NetworkMonitor()
    }
    
    override func tearDown() {
        networkMonitor.stopMonitoring()
        networkMonitor = nil
        super.tearDown()
    }
    
    func testInitialState() {
        // Test that NetworkMonitor initializes with default values
        XCTAssertFalse(networkMonitor.isExpensive)
        XCTAssertNil(networkMonitor.connectionType)
        // Note: isConnected may vary based on actual network state during testing
    }
    
    func testStartAndStopMonitoring() {
        // Test that monitoring can be started and stopped without crashing
        networkMonitor.startMonitoring()
        networkMonitor.stopMonitoring()
        
        // Should be able to restart monitoring
        networkMonitor.startMonitoring()
    }
    
    func testHasInternetConnection() {
        // Test that hasInternetConnection returns the same as isConnected
        XCTAssertEqual(networkMonitor.hasInternetConnection, networkMonitor.isConnected)
    }
    
    func testIsSuitableForCloudTranscription() {
        // Test that cloud transcription suitability considers both connection and cost
        let isSuitable = networkMonitor.isSuitableForCloudTranscription
        
        if networkMonitor.isConnected {
            XCTAssertEqual(isSuitable, !networkMonitor.isExpensive)
        } else {
            XCTAssertFalse(isSuitable)
        }
    }
    
    func testConnectionTypeDisplayName() {
        // Test display names for different connection types
        XCTAssertEqual(NWInterface.InterfaceType.wifi.displayName, "Wi-Fi")
        XCTAssertEqual(NWInterface.InterfaceType.cellular.displayName, "Cellular")
        XCTAssertEqual(NWInterface.InterfaceType.wiredEthernet.displayName, "Ethernet")
        XCTAssertEqual(NWInterface.InterfaceType.loopback.displayName, "Loopback")
        XCTAssertEqual(NWInterface.InterfaceType.other.displayName, "Other")
    }
    
    func testNetworkStatusNotification() {
        let expectation = XCTestExpectation(description: "Network status notification")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .networkStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertNotNil(notification.object)
            expectation.fulfill()
        }
        
        // Start monitoring to potentially trigger status changes
        networkMonitor.startMonitoring()
        
        // Wait a short time for potential network status changes
        wait(for: [expectation], timeout: 2.0)
        
        NotificationCenter.default.removeObserver(observer)
    }
}