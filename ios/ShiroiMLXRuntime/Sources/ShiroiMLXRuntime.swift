import Foundation
import StableDiffusion

public struct ShiroiMLXRuntimeInfo: Sendable {
    public let modelID: String
    public let defaultSteps: Int
    public let defaultCFG: Float
    public let backend: String

    public init() {
        let configuration = StableDiffusionConfiguration.presetSDXLTurbo
        let parameters = configuration.defaultParameters()
        modelID = configuration.id
        defaultSteps = parameters.steps
        defaultCFG = parameters.cfgWeight
        backend = "MLX / Metal GPU"
    }
}
