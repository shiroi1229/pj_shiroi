import CryptoKit
import Foundation

/// Constant-memory verification before ZIP extraction or loading native models.
enum ArchiveIntegrity {
    static func verify(at url: URL, expectedBytes: Int64, expectedSHA256: String) throws {
        guard expectedSHA256.count == 64 else { throw IntegrityError.invalidDigest }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            count += Int64(data.count)
            guard count <= expectedBytes else { throw IntegrityError.sizeMismatch }
            hash.update(data: data)
        }
        guard count == expectedBytes else { throw IntegrityError.sizeMismatch }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedSHA256.lowercased() else { throw IntegrityError.hashMismatch }
    }
    enum IntegrityError: LocalizedError {
        case invalidDigest, sizeMismatch, hashMismatch
        var errorDescription: String? {
            "The model archive failed integrity verification. It will not be extracted or loaded. Retry the download."
        }
    }
}
