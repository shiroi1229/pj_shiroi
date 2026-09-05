import Foundation

struct BenchmarkRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let totalSeconds: Double
    let coreMLSeconds: Double
    let metalEncodeSeconds: Double
    let saveSeconds: Double
    let outputMegabytes: Double
    let keyframes: Int
    let diffusionStepsPerKeyframe: Int
    let outputFrames: Int
    let fps: Int
    let quality: String
    let requestedTemporalMode: String?
    let actualTemporalPath: String?
    let memoryClass: String
    let thermalBefore: String
    let thermalAfter: String
    let lowPowerModeEnabled: Bool

    init(metrics: GenerationMetrics) {
        id = UUID()
        timestamp = metrics.startedAt
        totalSeconds = metrics.totalSeconds
        coreMLSeconds = metrics.coreMLSeconds
        metalEncodeSeconds = metrics.metalEncodeSeconds
        saveSeconds = metrics.saveSeconds
        outputMegabytes = metrics.outputMegabytes
        keyframes = metrics.keyframes
        diffusionStepsPerKeyframe = metrics.diffusionStepsPerKeyframe
        outputFrames = metrics.outputFrames
        fps = metrics.fps
        quality = metrics.quality.rawValue
        requestedTemporalMode = metrics.requestedTemporalMode.rawValue
        actualTemporalPath = metrics.actualTemporalPath.rawValue
        memoryClass = metrics.memoryClass.rawValue
        thermalBefore = metrics.thermalBefore
        thermalAfter = metrics.thermalAfter
        lowPowerModeEnabled = metrics.lowPowerModeEnabled
    }

    var encodeFramesPerSecond: Double {
        guard metalEncodeSeconds > 0 else { return 0 }
        return Double(outputFrames) / metalEncodeSeconds
    }
}

actor BenchmarkStore {
    static let shared = BenchmarkStore()

    private let maxRecords = 100

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "ShiroiVideoForge/Benchmarks", directoryHint: .isDirectory)
    }

    private var jsonURL: URL {
        directory.appending(path: "benchmarks.json")
    }

    func load() throws -> [BenchmarkRecord] {
        try ensureDirectory()
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return [] }
        let data = try Data(contentsOf: jsonURL)
        return try JSONDecoder.benchmarkDecoder.decode([BenchmarkRecord].self, from: data)
            .sorted { $0.timestamp > $1.timestamp }
    }

    @discardableResult
    func append(_ metrics: GenerationMetrics) throws -> [BenchmarkRecord] {
        var records = try load()
        records.insert(BenchmarkRecord(metrics: metrics), at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        try persist(records)
        return records
    }

    func exportCSV() throws -> URL {
        let records = try load()
        var lines = [
            "timestamp,quality,requested_temporal,actual_temporal,memory_class,total_s,core_ml_s,metal_hevc_s,save_s,output_mb,keyframes,steps_per_keyframe,output_frames,fps,encode_fps,thermal_before,thermal_after,low_power"
        ]
        let iso = ISO8601DateFormatter()
        for record in records {
            lines.append([
                iso.string(from: record.timestamp),
                csv(record.quality),
                csv(record.requestedTemporalMode ?? "legacy"),
                csv(record.actualTemporalPath ?? "legacy"),
                csv(record.memoryClass),
                format(record.totalSeconds),
                format(record.coreMLSeconds),
                format(record.metalEncodeSeconds),
                format(record.saveSeconds),
                format(record.outputMegabytes),
                String(record.keyframes),
                String(record.diffusionStepsPerKeyframe),
                String(record.outputFrames),
                String(record.fps),
                format(record.encodeFramesPerSecond),
                csv(record.thermalBefore),
                csv(record.thermalAfter),
                record.lowPowerModeEnabled ? "true" : "false"
            ].joined(separator: ","))
        }

        try ensureDirectory()
        let url = directory.appending(path: "shiroi-video-forge-benchmarks.csv")
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    func clear() throws {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            try FileManager.default.removeItem(at: jsonURL)
        }
    }

    private func persist(_ records: [BenchmarkRecord]) throws {
        try ensureDirectory()
        let data = try JSONEncoder.benchmarkEncoder.encode(records)
        try data.write(to: jsonURL, options: .atomic)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

private extension JSONEncoder {
    static var benchmarkEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var benchmarkDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
