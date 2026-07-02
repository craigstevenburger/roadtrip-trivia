import CoreLocation
import Foundation

enum MotionState {
    case stopped
    case moving
}

/// Debounced stop/moving detection built on CoreLocation speed samples —
/// drives the Phase 4 pause/resume nudge in GameCoordinator. Purely a
/// suggestion: manual pause/resume (docs/api-contract.md) always works
/// regardless of authorization state, so failures here are silent no-ops.
final class RestStopDetector: NSObject, CLLocationManagerDelegate {
    var onMotionChange: ((MotionState) -> Void)?

    private let manager = CLLocationManager()
    private let classifier = MotionClassifier()
    private var fallbackTimer: Timer?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = self
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdating()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        classifier.reset()
    }

    private func beginUpdating() {
        manager.startUpdatingLocation()
        fallbackTimer?.invalidate()
        // CoreLocation isn't guaranteed to keep delivering updates once the
        // device is stationary (distanceFilter is off, but the OS can still
        // throttle), so re-check the debounce against the last known speed
        // on a timer too — otherwise a real stop could go undetected.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, let state = self.classifier.reevaluate(at: Date()) else { return }
            self.onMotionChange?(state)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        beginUpdating()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if let state = classifier.recordSample(speed: max(0, location.speed), at: Date()) {
            onMotionChange?(state)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors (tunnels, poor signal) — the fallback timer
        // keeps evaluating off the last known sample.
    }
}

/// Pure state machine over (speed, timestamp) samples — kept separate from
/// CLLocationManager so it's testable without a live location source.
private final class MotionClassifier {
    private enum Classification: Equatable {
        case stopped
        case moving
        case ambiguous
    }

    private let stoppedThreshold: CLLocationSpeed = 0.9 // ~2 mph
    private let movingThreshold: CLLocationSpeed = 4.0 // ~9 mph
    private let stoppedDebounce: TimeInterval = 90 // a real rest stop, not a red light
    private let movingDebounce: TimeInterval = 20 // snappy once back on the road

    private var lastSpeed: CLLocationSpeed = 0
    private var candidate: Classification = .ambiguous
    private var candidateSince: Date?
    private var confirmed: Classification = .ambiguous

    /// Feeds a fresh sample. Returns a MotionState only on the call where
    /// the debounced state actually flips.
    @discardableResult
    func recordSample(speed: CLLocationSpeed, at date: Date) -> MotionState? {
        lastSpeed = speed
        return classify(at: date)
    }

    /// Re-runs the debounce against the last known speed without a fresh
    /// sample (see the fallback timer in RestStopDetector).
    @discardableResult
    func reevaluate(at date: Date) -> MotionState? {
        classify(at: date)
    }

    func reset() {
        lastSpeed = 0
        candidate = .ambiguous
        candidateSince = nil
        confirmed = .ambiguous
    }

    private func classify(at date: Date) -> MotionState? {
        let next: Classification
        if lastSpeed < stoppedThreshold {
            next = .stopped
        } else if lastSpeed > movingThreshold {
            next = .moving
        } else {
            next = .ambiguous
        }

        if next != candidate {
            candidate = next
            candidateSince = date
        }

        guard next != .ambiguous, next != confirmed, let since = candidateSince else { return nil }
        let debounce = next == .stopped ? stoppedDebounce : movingDebounce
        guard date.timeIntervalSince(since) >= debounce else { return nil }

        confirmed = next
        return next == .stopped ? .stopped : .moving
    }
}
