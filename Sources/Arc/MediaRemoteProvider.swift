import AppKit
import ArcCore

/// Keeps private API failures in a child process, isolated from the UI.
@MainActor final class MediaRemoteProvider: NowPlayingProviding {
    let updates: AsyncStream<MediaState>
    private let continuation: AsyncStream<MediaState>.Continuation
    private var listener: Process?
    private var reader: Task<Void, Never>?
    private var commands: [UUID: Process] = [:]
    private var generation = 0
    private let processFactory: (([String]) -> Process?)?

    init(processFactory: (([String]) -> Process?)? = nil) {
        self.processFactory = processFactory
        let stream = AsyncStream<MediaState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = stream.stream
        continuation = stream.continuation
    }

    private func process(arguments: [String]) -> Process? {
        if let processFactory { return processFactory(arguments) }
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }

    func start() {
        guard listener == nil else { return }
        guard let process = process(arguments: ["stream", "--no-diff", "--micros", "--allow-missing-title", "--debounce=80"]) else {
            continuation.yield(.unavailable)
            return
        }
        generation += 1
        let currentGeneration = generation
        let pipe = Pipe()
        process.standardOutput = pipe
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.listener = nil
                self.continuation.yield(.unavailable)
            }
        }
        do {
            try process.run()
            listener = process
            let continuation = continuation
            reader = Task.detached(priority: .utility) {
                do {
                    // Async bytes suspend while idle; no polling process or main-thread decoding.
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        guard !Task.isCancelled else { break }
                        guard let data = line.data(using: .utf8) else { continue }
                        let state = try MediaDecoder.decode(data)
                        guard !Task.isCancelled else { break }
                        continuation.yield(state)
                    }
                } catch {
                    if !Task.isCancelled { continuation.yield(.unavailable) }
                }
            }
        } catch { continuation.yield(.unavailable) }
    }

    func stop() {
        generation += 1
        reader?.cancel()
        reader = nil
        listener?.terminationHandler = nil
        if listener?.isRunning == true { listener?.terminate() }
        listener = nil
        for command in commands.values {
            command.terminationHandler = nil
            if command.isRunning { command.terminate() }
        }
        commands.removeAll()
    }

    func send(_ command: MediaCommand) {
        runCommand(arguments: ["send", command.rawValue])
    }

    func seek(to position: TimeInterval) {
        guard position.isFinite, position >= 0,
              position <= Double(Int64.max) / 1_000_000 else { return }
        runCommand(arguments: ["seek", String(Int64((position * 1_000_000).rounded()))])
    }

    private func runCommand(arguments: [String]) {
        guard listener?.isRunning == true, commands.count < 3,
              let process = process(arguments: arguments) else { return }
        let id = UUID()
        let currentGeneration = generation
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let failed = process.terminationStatus != 0
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.commands[id] = nil
                if failed { self.continuation.yield(.unavailable) }
            }
        }
        do {
            try process.run()
            commands[id] = process
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if let pending = self?.commands[id], pending.isRunning { pending.terminate() }
            }
        } catch { continuation.yield(.unavailable) }
    }
}
