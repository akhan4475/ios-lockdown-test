@main
struct SessionAlertTests {
    static func main() {
        var policy = SessionAlertPolicy()
        precondition(!policy.failure(), "Idle sessions must not notify")
        policy.begin(at: 100)
        precondition(policy.failure(), "The first failed send must warn immediately")
        precondition(!policy.failure(), "Repeated failed sends must not spam alerts")
        let recovered = policy.success(at: 101)
        precondition(recovered.recovered && recovered.rearm, "Recovery rearms the watchdog")
        let healthy = policy.success(at: 102)
        precondition(!healthy.recovered && !healthy.rearm, "Healthy sends do not produce notifications each second")
        precondition(policy.success(at: 106).rearm, "Successful sends periodically replace the timeout")
        precondition(policy.failure(), "A new outage after recovery must alert")
        policy.end()
        precondition(!policy.active && !policy.failure(), "Clear disables failure monitoring")
        let stopped = policy.success(at: 107)
        precondition(!stopped.recovered && !stopped.rearm, "An in-flight send after Clear cannot rearm monitoring")
        policy.begin(at: 200)
        let first = policy.success(at: 201)
        precondition(!first.recovered, "The first acknowledgement is not a recovery event")
        let stale = policy.success(at: 230)
        precondition(stale.recovered && stale.rearm, "A long update gap must clear a stale warning and rearm")
        policy.begin(at: 300)
        precondition(policy.failure(), "Switching targets starts a fresh alert episode")
        print("Session alerts: all twelve regression checks passed")
    }
}
