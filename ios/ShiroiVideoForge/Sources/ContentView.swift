import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ForgeViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            leftColumn
                                .frame(width: 390)
                            rightColumn
                                .frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 20) {
                            leftColumn
                            rightColumn
                        }
                    }
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background {
                LinearGradient(
                    colors: [.black.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Shiroi Video Forge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refreshDeviceState()
                    } label: {
                        Label("Refresh device", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text("On-device AI video generation")
                    .font(.title2.bold())
                Text("Core ML + Metal + HEVC • no X2 inference path")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("All on iPad", systemImage: "ipad")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 20) {
            hardwareCard
            promptCard
            modelCard
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 20) {
            settingsCard
            generationCard
            outputLibraryCard
        }
    }

    private var hardwareCard: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow { metricLabel("GPU", "cpu"); Text(model.capabilities.gpuName) }
                GridRow { metricLabel("CPU cores", "gauge.with.dots.needle.67percent"); Text("\(model.capabilities.cpuCores)") }
                GridRow { metricLabel("RAM", "memorychip"); Text(String(format: "%.1f GB • %@", model.capabilities.memoryGB, model.capabilities.memoryClass.rawValue)) }
                GridRow { metricLabel("AI path", "brain"); Text("Core ML → GPU / Neural Engine / CPU") }
                GridRow { metricLabel("Video path", "video"); Text("Metal GPU → HEVC media engine") }
                GridRow { metricLabel("Thermal", "thermometer.medium"); Text(model.capabilities.thermalState) }
                GridRow { metricLabel("Low Power", "battery.25percent"); Text(model.capabilities.lowPowerModeEnabled ? "Enabled" : "Off") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label("This iPad", systemImage: "ipad")
                .font(.headline)
        }
    }

    private func metricLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(.secondary)
    }

    private var promptCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $model.prompt)
                    .frame(minHeight: 126)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                Text("Negative prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("text, watermark, low quality…", text: $model.negativePrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 4)
        } label: {
            Label("Video prompt", systemImage: "pencil.and.outline")
                .font(.headline)
        }
    }

    private var modelCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: model.modelInstalled ? "checkmark.seal.fill" : "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(model.modelInstalled ? .green : .primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.modelInstalled ? "Core ML model installed" : "Model download required")
                            .font(.headline)
                        Text("Apple/Hugging Face • Stable Diffusion 1.5 • 6-bit Core ML")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if !model.modelInstalled {
                    Button {
                        model.installModel()
                    } label: {
                        Label("Install on-device model", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("On-device model", systemImage: "cube")
                .font(.headline)
        }
    }

    private var settingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Quality", selection: $model.quality) {
                    ForEach(GenerationQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 18) {
                    Stepper(value: $model.duration, in: 2...5, step: 1) {
                        LabeledContent("Duration", value: "\(Int(model.duration)) sec")
                    }
                    Picker("FPS", selection: $model.fps) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 7) {
                    LabeledContent("Temporal motion", value: String(format: "%.2f", model.motionStrength))
                    Slider(value: $model.motionStrength, in: 0.15...0.42)
                }

                HStack {
                    Text("Seed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("1229", text: $model.seedText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 130)
                }

                let profile = model.capabilities.profile(for: model.quality)
                Text("Profile: \(profile.keyframes) AI keyframes • \(profile.steps) diffusion steps • \(profile.reduceMemory ? "memory-saver" : "full-memory")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            Label("Generation settings", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private var generationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let output = model.outputURL {
                    VideoPreview(url: output)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                        VStack(spacing: 10) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 36))
                            Text("Generated video will appear here")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }

                HStack(spacing: 12) {
                    Button {
                        model.generate()
                    } label: {
                        Label("Generate \(Int(model.duration))-second video on this iPad", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy || !model.modelInstalled || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if model.isBusy {
                        Button(role: .destructive) {
                            model.cancelGeneration()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                if model.isBusy || model.progress > 0 {
                    ProgressView(value: model.progress)
                    HStack {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.progress * 100))%")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let output = model.outputURL {
                    HStack {
                        Label("512×512 • HEVC MOV • generated locally", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ShareLink(item: output) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("On-device generation", systemImage: "play.rectangle.on.rectangle")
                .font(.headline)
        }
    }

    private var outputLibraryCard: some View {
        GroupBox {
            if model.outputs.isEmpty {
                ContentUnavailableView(
                    "No generated videos yet",
                    systemImage: "film",
                    description: Text("Completed renders are stored locally on this iPad.")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(model.outputs, id: \.self) { url in
                        HStack(spacing: 10) {
                            Button {
                                model.selectOutput(url)
                            } label: {
                                Label(url.lastPathComponent, systemImage: model.outputURL == url ? "play.circle.fill" : "film")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)

                            Spacer()
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                model.deleteOutput(url)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                        if url != model.outputs.last { Divider() }
                    }
                }
            }
        } label: {
            Label("Local output library", systemImage: "externaldrive.fill.badge.checkmark")
                .font(.headline)
        }
    }
}
