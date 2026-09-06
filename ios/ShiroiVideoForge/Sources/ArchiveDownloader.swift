import Foundation

/// One download attempt. All mutable state is confined to `stateQueue`.
/// URLSession owns its temporary file only until the delegate returns, so it is
/// moved synchronously there. Only opaque resume data is persisted; never logged.
final class ArchiveDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.shiroi1229.model-download")
    private let destination: URL
    private let resumeURL: URL
    private let progress: @Sendable (Double, String) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var movedFile: URL?
    private var fileError: Error?
    private var cancellationRequested = false
    private var finished = false
    private var lastReported = -1

    init(destination: URL, resumeURL: URL,
         progress: @escaping @Sendable (Double, String) -> Void) {
        self.destination = destination
        self.resumeURL = resumeURL
        self.progress = progress
    }

    func download(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                stateQueue.async {
                    self.continuation = continuation
                    if self.cancellationRequested {
                        self.finish(.failure(CancellationError()))
                        return
                    }
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 120
                    config.timeoutIntervalForResource = 7 * 24 * 3600
                    config.waitsForConnectivity = true
                    config.urlCache = nil
                    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                    self.session = session
                    if let data = try? Data(contentsOf: self.resumeURL), !data.isEmpty {
                        self.task = session.downloadTask(withResumeData: data)
                        self.progress(0, "Resuming model download when supported by the server…")
                    } else {
                        self.task = session.downloadTask(with: url)
                        self.progress(0, "Downloading model to this device…")
                    }
                    self.task?.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        stateQueue.async {
            guard !self.finished, !self.cancellationRequested else { return }
            self.cancellationRequested = true
            guard let task = self.task else { return }
            task.cancel(byProducingResumeData: { data in
                self.stateQueue.async {
                    self.storeResume(data)
                    self.finish(.failure(CancellationError()))
                }
            })
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        stateQueue.async {
            guard !self.finished, !self.cancellationRequested else { return }
            let fraction = totalBytesExpectedToWrite > 0
                ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0
            let percent = Int(fraction * 100)
            guard percent != self.lastReported else { return }
            self.lastReported = percent
            let mb = Double(totalBytesWritten) / 1_000_000
            self.progress(fraction, String(format: "Model download • %.0f MB • %d%%", mb, percent))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Do not defer the move: URLSession removes `location` after this returns.
        stateQueue.sync {
            guard !finished else { return }
            do {
                guard let response = downloadTask.response as? HTTPURLResponse,
                      response.statusCode == 200 || response.statusCode == 206 else {
                    throw DownloadError.http((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: location, to: destination)
                movedFile = destination
            } catch { fileError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            guard !self.finished else { return }
            guard !self.cancellationRequested else { return }
            if let error {
                let data = (error as NSError).userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
                self.storeResume(data)
                self.finish(.failure(error))
            } else if let error = self.fileError {
                self.storeResume(nil)
                self.finish(.failure(error))
            } else if let url = self.movedFile {
                self.storeResume(nil)
                self.finish(.success(url))
            } else {
                self.finish(.failure(DownloadError.missingFile))
            }
        }
    }

    private func storeResume(_ data: Data?) {
        if let data, !data.isEmpty { try? data.write(to: resumeURL, options: .atomic) }
        else { try? FileManager.default.removeItem(at: resumeURL) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished, let continuation else { return }
        finished = true
        self.continuation = nil
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }

    enum DownloadError: LocalizedError {
        case http(Int), missingFile
        var errorDescription: String? {
            switch self {
            case .http(let code): return "Model download failed (HTTP \(code)). Retry the download."
            case .missingFile: return "The download finished without a model archive."
            }
        }
    }
}
