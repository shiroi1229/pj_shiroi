import SwiftUI

struct PerformanceMetricsView: View {
    let metrics: GenerationMetrics

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    metric("Total", value: seconds(metrics.totalSeconds), symbol: "stopwatch")
                    metric("Core ML", value: seconds(metrics.coreMLSeconds), symbol: "brain")
                }
                GridRow {
                    metric("Metal + HEVC", value: seconds(metrics.metalEncodeSeconds), symbol: "cpu")
                    metric("Save", value: seconds(metrics.saveSeconds), symbol: "internaldrive")
                }
                GridRow {
                    metric("AI / keyframe", value: seconds(metrics.coreMLSecondsPerKeyframe), symbol: "photo.stack")
                    metric("Encode speed", value: String(format: "%.1f fps", metrics.encodeFramesPerSecond), symbol: "speedometer")
                }
                GridRow {
                    metric("Output", value: String(format: "%.1f MB", metrics.outputMegabytes), symbol: "film")
                    metric("Realtime factor", value: String(format: "%.1f×", metrics.realtimeFactor), symbol: "timer")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 16) {
                Label("\(metrics.keyframes) keyframes × \(metrics.diffusionStepsPerKeyframe) steps", systemImage: "point.3.connected.trianglepath.dotted")
                Spacer()
                Label("Thermal \(metrics.thermalBefore) → \(metrics.thermalAfter)", systemImage: "thermometer.medium")
                if metrics.lowPowerModeEnabled {
                    Label("Low Power", systemImage: "battery.25percent")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } label: {
            Label("M4 on-device benchmark", systemImage: "gauge.with.dots.needle.67percent")
                .font(.headline)
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }
}
