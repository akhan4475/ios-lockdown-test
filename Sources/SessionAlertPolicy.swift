struct SessionAlertPolicy {
    static let watchdogDelay: Double = 25
    static let refreshInterval: Double = 5
    private(set) var active = false
    private var warned = false
    private var lastSuccess: Double?
    private var lastArm: Double?

    mutating func begin(at now: Double) {
        active = true
        warned = false
        lastSuccess = nil
        lastArm = now
    }

    mutating func failure() -> Bool {
        guard active, !warned else { return false }
        warned = true
        lastArm = nil
        return true
    }

    mutating func success(at now: Double) -> (recovered: Bool, rearm: Bool) {
        guard active else { return (false, false) }
        let quiet = lastSuccess.map { now - $0 >= watchdogDelay - refreshInterval } ?? false
        let recovered = warned || quiet
        let rearm = recovered || (lastArm.map { now - $0 >= refreshInterval } ?? true)
        warned = false
        lastSuccess = now
        if rearm { lastArm = now }
        return (recovered, rearm)
    }

    mutating func end() {
        active = false
        warned = false
        lastSuccess = nil
        lastArm = nil
    }
}
