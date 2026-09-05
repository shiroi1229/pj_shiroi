import SwiftUI

struct BenchmarkHistoryView: View {
    @EnvironmentObject private var model: ForgeViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if model.benchmarkHistory.isEmpty {
                    Text("Run a generation to start collecting real M4 performance data.")
                        .foregroundStyle(.secondary)
                } else {
                    summary
                    Divider()
                    ForEach(model.benchmarkHistory.prefix(6)) { record in
                        recordRow(record)
                        if record.id != model.benchmarkHistory.prefix(6).last?.id {
                            Divider()
                        }
                    }
                }

                HStack {
                    Button {
                        model.prepareBenchmarkCSV()
                    } label: {
                        Label("Prepare CSV", systemImage: "tablecells")
                    }
                    .disabled(model.benchmarkHistory.isEmpty)

                    if let csvURL = model.benchmarkCSVURL {
                        ShareLink(item: csvURL) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                        }
                    }

                    Spacer()
                    Button(role: .destructive) {
                        model.clearBenchmarkHistory()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(model.benchmarkHistory.isEmpty)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("M4 FBL benchmark history", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
        }
    }

    private var summary: some View {
        let recent = Array(model.benchmarkHistory.prefix(10))
        let avgTotal = recent.map(\.totalSeconds).reduce(0, +) / Double(max(recent.count, 1))
        let avgCoreML = recent.map(\.coreMLSeconds).reduce(0, +) / Double(max(recent.count, 1))
        let avgMetal = recent.map(\.metalEncodeSeconds).reduce(0, +) / Double(max(recent.count, 1))

        return HStack(spacing: 22) {
            summaryMetric("Runs", value: "\(model.benchmarkHistory.count)")
            summaryMetric("Avg total", value: String(format: "%.1f s", avgTotal))
            summaryMetric("Avg Core ML", value: String(format: "%.1f s", avgCoreML))
            summaryMetric("Avg Temporal", value: String(format: "%.2f s", avgMetal))
        }
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
    }

    private func recordRow(_ record: BenchmarkRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.quality.capitalized)
                    .font(.headline)
                Text(record.actualTemporalPath ?? "Legacy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            metric("Total", String(format: "%.1fs", record.totalSeconds))
            metric("Core ML", String(format: "%.1fs", record.coreMLSeconds))
            metric("Temporal", String(format: "%.2fs", record.metalEncodeSeconds))
            metric("Encode", String(format: "%.1ffps", record.encodeFramesPerSecond))

            Spacer()
            Text("\(record.thermalBefore)→\(record.thermalAfter)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }
}
