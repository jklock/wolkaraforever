import Foundation

// A launch that cannot be authorized must end in a bounded refusal that names the
// cause, never in a wait, a retry loop or an unlaunched guest reported as ready.
// This drives the real PacketServiceProbe for the one cause a Mac-side process can
// reach without a device: no usable protected enrollment.
@main struct PacketBlockedTests {
    static func main() {
        let probe = PacketServiceProbe(), done = DispatchSemaphore(value:0)
        var report = ""
        // The output sink is never used: the probe refuses before a single packet
        // is written, which is itself part of what this asserts.
        probe.startAuthorization(deviceIdentifier:"fixture-device-with-no-enrollment",
                                output:{ _ in
            preconditionFailure("a helper with no enrollment must not reach the network")
        }, completion:{ text in
            report = text; done.signal()
        })
        precondition(done.wait(timeout:.now()+5) == .success,"the refusal was not bounded")
        precondition(probe.blockedState == "notEnrolled",
            "a missing enrollment must report notEnrolled, got \(String(describing:probe.blockedState))")
        precondition(!probe.authorizationReady,"a refused launch must never report readiness")
        // A retryable service outage and a missing enrollment are different
        // causes: only the first may be retried by the route.
        precondition(!probe.serviceUnavailable,"a missing enrollment is not a retryable outage")
        precondition(report.contains("enrollment"),"the report must name enrollment: \(report)")
        precondition(probe.arenaService != nil,"the helper must still own a preparation service")
        // The probe is single-use: a second attempt on the same instance cannot
        // attach, so a stale session can never prepare memory later.
        let second = DispatchSemaphore(value:0)
        var secondReport = ""
        probe.startAuthorization(deviceIdentifier:"fixture-device-with-no-enrollment",
                                output:{ _ in true }, completion:{ text in
            secondReport = text; second.signal()
        })
        precondition(second.wait(timeout:.now()+5) == .success,"the second attempt was not bounded")
        precondition(secondReport.contains("already used"),"a used probe must refuse: \(secondReport)")
        print("PASS: no enrollment ends in a bounded notEnrolled refusal, no readiness, no retry, no packets and no second attach")
    }
}
