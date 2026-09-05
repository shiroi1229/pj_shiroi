import Foundation
import MLXStableDiffusion

public struct ShiroiMLXCapabilities: Sendable {
    public let modelID: String
    public let defaultSteps: Int
    public let defaultCFG: Float

    public init() {
        let configuration = StableDiffusionConfiguration.presetSDXLTurbo
        let parameters = configuration.defaultParameters()
        modelID = configuration.id
        defaultSteps = parameters.steps
        defaultCFG = parameters.cfgWeight
    }
}
