@main
struct OutsideStartupTests {
    static func main() {
        precondition(!OutsideStartupPolicy.canRestoreData(holding: false, acknowledgements: 0, lastError: ""), "Ready without a location is not a completed startup")
        precondition(!OutsideStartupPolicy.canRestoreData(holding: true, acknowledgements: 0, lastError: ""), "A pending first send is not an acknowledgement")
        precondition(!OutsideStartupPolicy.canRestoreData(holding: true, acknowledgements: 5, lastError: "Disconnected"), "Old successes must not hide a current failure")
        precondition(!OutsideStartupPolicy.canRestoreData(holding: false, acknowledgements: 5, lastError: ""), "A cleared session is not active")
        precondition(OutsideStartupPolicy.canRestoreData(holding: true, acknowledgements: 1, lastError: ""), "A successful active send permits the cellular handoff test")
        precondition(OutsideStartupPolicy.validCoordinates(latitude: -90, longitude: 180))
        precondition(!OutsideStartupPolicy.validCoordinates(latitude: 90.1, longitude: 0))
        precondition(!OutsideStartupPolicy.validCoordinates(latitude: 0, longitude: -180.1))
        precondition(!OutsideStartupPolicy.validCoordinates(latitude: .nan, longitude: 0))
        precondition(!OutsideStartupPolicy.validCoordinates(latitude: 0, longitude: .infinity))
        print("Outside startup: all ten regression checks passed")
    }
}
