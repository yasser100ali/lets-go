import Foundation
import CoreHaptics
import UIKit
import OSLog

/// Turns you can feel through a pocket: one buzz for left, two for right, three when you're here.
final class WalkHaptics {
    private var engine: CHHapticEngine?
    private let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "haptics")

    static func count(for way: Turn.Way) -> Int {
        switch way {
        case .left: 1
        case .right: 2
        case .arrive: 3
        case .straight: 0
        }
    }

    func play(_ way: Turn.Way) {
        let n = Self.count(for: way)
        guard n > 0 else { return }
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = ready() {
            do {
                let events = (0..<n).map { i in
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                        ],
                        relativeTime: Double(i) * 0.32,
                        duration: 0.18
                    )
                }
                let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                log.error("Haptic pattern failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // No Core Haptics: taps from the plain generator, spaced out.
        let tap = UIImpactFeedbackGenerator(style: .heavy)
        for i in 0..<n {
            Task {
                try? await Task.sleep(for: .milliseconds(320 * i))
                tap.impactOccurred()
            }
        }
    }

    private func ready() -> CHHapticEngine? {
        if let engine { return engine }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            try e.start()
            engine = e
            return e
        } catch {
            log.error("Haptic engine failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
