import Foundation

@main
enum InferenceNumericsTests {
    static func main() throws {
        var passed = 0
        func check(_ name: String, _ success: Bool) throws {
            guard success else { throw Failure.failed(name) }
            passed += 1; print("PASS \(name)")
        }
        try check("ordinary finite latent", InferenceNumerics.inspect([-2, 0, 3]).isValid)
        try check("empty tensor rejected", !InferenceNumerics.inspect([]).isValid)
        try check("NaN rejected", !InferenceNumerics.inspect([.nan]).isValid)
        try check("positive infinity rejected", !InferenceNumerics.inspect([.infinity]).isValid)
        try check("negative infinity rejected", !InferenceNumerics.inspect([-.infinity]).isValid)
        try check("nonfinite count exact", InferenceNumerics.inspect([.nan, .infinity, 1, -.infinity]).nonFiniteCount == 3)
        try check("largest finite float preserved", InferenceNumerics.inspect([Float.greatestFiniteMagnitude]).isValid)
        try check("maximum magnitude correct", InferenceNumerics.inspect([-3, 2, 1]).maximumAbsoluteValue == 3)
        print("\(passed) numerical-health checks passed. This is not a model inference test.")
    }
    enum Failure: Error { case failed(String) }
}
