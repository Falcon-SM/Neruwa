import AVFoundation
import Foundation

@MainActor
final class AmplifiedSpeechPlayer {
    enum PlaybackError: LocalizedError {
        case invalidAudioBuffer
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .invalidAudioBuffer:
                "音声データを生成できませんでした。"
            case .emptyAudio:
                "生成された音声データが空でした。"
            }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var equalizer: AVAudioUnitEQ?
    private var playingFile: AVAudioFile?
    private var activeToken: UUID?
    private var renderContinuation: CheckedContinuation<URL, Error>?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var renderJob: SpeechRenderJob?
    private var cachedFiles: [String: URL] = [:]
    private var cachedFileOrder: [String] = []
    private let maximumCachedFiles = 32

    var isActive: Bool {
        activeToken != nil
            || synthesizer.isSpeaking
            || playerNode?.isPlaying == true
    }

    func play(
        utterance: AVSpeechUtterance,
        cacheKey: String,
        gainDecibels: Float
    ) async throws {
        stop()
        let token = UUID()
        activeToken = token

        do {
            let url: URL
            if let cachedURL = cachedFiles[cacheKey],
               FileManager.default.fileExists(atPath: cachedURL.path) {
                url = cachedURL
            } else {
                url = try await render(utterance: utterance, token: token)
                guard activeToken == token else { throw CancellationError() }
                cache(url: url, forKey: cacheKey)
            }

            try await playFile(
                at: url,
                gainDecibels: gainDecibels,
                token: token
            )
            guard activeToken == token else { throw CancellationError() }
            activeToken = nil
        } catch {
            if activeToken == token {
                stop()
            }
            throw error
        }
    }

    func stop() {
        activeToken = nil
        synthesizer.stopSpeaking(at: .immediate)
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        equalizer = nil
        playingFile = nil
        engine = nil
        renderJob = nil

        if let continuation = renderContinuation {
            renderContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    private func render(
        utterance: AVSpeechUtterance,
        token: UUID
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("neruwa-speech-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let job = SpeechRenderJob(url: url)
        renderJob = job

        return try await withCheckedThrowingContinuation { continuation in
            renderContinuation = continuation
            synthesizer.write(utterance) { [weak self, job] buffer in
                let result = job.append(buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.activeToken == token else { return }
                    switch result {
                    case .success(false):
                        break
                    case .success(true):
                        self.finishRendering(job: job, token: token)
                    case .failure(let error):
                        self.failRendering(error: error, token: token)
                    }
                }
            }
        }
    }

    private func finishRendering(job: SpeechRenderJob, token: UUID) {
        guard activeToken == token,
              renderJob === job,
              let continuation = renderContinuation else { return }
        renderJob = nil
        renderContinuation = nil

        guard job.hasAudio else {
            continuation.resume(throwing: PlaybackError.emptyAudio)
            return
        }
        continuation.resume(returning: job.url)
    }

    private func failRendering(error: Error, token: UUID) {
        guard activeToken == token,
              let continuation = renderContinuation else { return }
        renderJob = nil
        renderContinuation = nil
        continuation.resume(throwing: error)
    }

    private func playFile(
        at url: URL,
        gainDecibels: Float,
        token: UUID
    ) async throws {
        let file = try AVAudioFile(forReading: url)
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 0)
        equalizer.globalGain = min(max(gainDecibels, -12), 18)
        playerNode.volume = gainDecibels <= -90 ? 0 : 1

        engine.attach(playerNode)
        engine.attach(equalizer)
        engine.connect(
            playerNode,
            to: equalizer,
            format: file.processingFormat
        )
        engine.connect(
            equalizer,
            to: engine.mainMixerNode,
            format: file.processingFormat
        )

        self.engine = engine
        self.playerNode = playerNode
        self.equalizer = equalizer
        playingFile = file

        try engine.start()
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation
            playerNode.scheduleFile(
                file,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishPlayback(token: token)
                }
            }
            playerNode.play()
        }
    }

    private func finishPlayback(token: UUID) {
        guard activeToken == token,
              let continuation = playbackContinuation else { return }
        playbackContinuation = nil
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        equalizer = nil
        playingFile = nil
        engine = nil
        continuation.resume()
    }

    private func cache(url: URL, forKey key: String) {
        if let oldURL = cachedFiles.updateValue(url, forKey: key),
           oldURL != url {
            try? FileManager.default.removeItem(at: oldURL)
        }
        cachedFileOrder.removeAll { $0 == key }
        cachedFileOrder.append(key)

        while cachedFileOrder.count > maximumCachedFiles {
            let expiredKey = cachedFileOrder.removeFirst()
            if let expiredURL = cachedFiles.removeValue(forKey: expiredKey) {
                try? FileManager.default.removeItem(at: expiredURL)
            }
        }
    }
}

private final class SpeechRenderJob: @unchecked Sendable {
    let url: URL

    private let lock = NSLock()
    private var file: AVAudioFile?
    private(set) var hasAudio = false
    private var didFinish = false

    init(url: URL) {
        self.url = url
    }

    func append(_ buffer: AVAudioBuffer) -> Result<Bool, Error> {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return .success(true) }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            return .failure(AmplifiedSpeechPlayer.PlaybackError.invalidAudioBuffer)
        }
        guard pcmBuffer.frameLength > 0 else {
            didFinish = true
            file = nil
            return .success(true)
        }

        do {
            if file == nil {
                file = try AVAudioFile(
                    forWriting: url,
                    settings: pcmBuffer.format.settings
                )
            }
            try file?.write(from: pcmBuffer)
            hasAudio = true
            return .success(false)
        } catch {
            didFinish = true
            file = nil
            return .failure(error)
        }
    }
}
