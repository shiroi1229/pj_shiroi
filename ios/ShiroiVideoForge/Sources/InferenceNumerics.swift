import Foundation

/// Aggregate tensor health only; no image or raw latent data is exported.
struct InferenceNumerics: Sendable {
    let count: Int
    let nonFiniteCount: Int
    let maximumAbsoluteValue: Double
    var isValid: Bool { count > 0 && nonFiniteCount == 0 }
    static func inspect(_ values: [Float]) -> InferenceNumerics {
        var nonFinite = 0
        var maximum = 0.0
        for value in values {
            if value.isFinite { maximum = max(maximum, abs(Double(value))) }
            else { nonFinite += 1 }
        }
        return InferenceNumerics(count: values.count, nonFiniteCount: nonFinite, maximumAbsoluteValue: maximum)
    }
}
