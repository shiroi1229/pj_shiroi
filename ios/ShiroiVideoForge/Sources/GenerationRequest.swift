import Foundation

struct GenerationRequest: Sendable {
    var prompt: String
    var negativePrompt: String
    var duration: Double = 3.0
    var fps: Int = 24
    var width: Int = 512
    var height: Int = 512
    var seed: UInt32 = 1229
}
