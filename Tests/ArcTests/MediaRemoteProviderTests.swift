import XCTest
import ArcCore
@testable import Arc

final class MediaRemoteProviderTests: XCTestCase {
    @MainActor func testCancelledCommandCannotFailRestartedListener() async throws {
        var command: Process?
        let provider = MediaRemoteProvider { arguments in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["20"]
            if arguments.first == "send" { command = process }
            return process
        }
        defer { provider.stop() }
        let unexpected = expectation(description: "Old command must not report unavailable")
        unexpected.isInverted = true
        let reader = Task {
            for await state in provider.updates {
                if state == .unavailable { unexpected.fulfill() }
            }
        }
        defer { reader.cancel() }
        provider.start()
        provider.send(.next)
        let oldCommand = try XCTUnwrap(command)
        let callback = try XCTUnwrap(oldCommand.terminationHandler)
        let failure = try failedProcess()
        // Queue the callback before stop: clearing the handler alone cannot
        // invalidate work already waiting for the main actor.
        callback(failure)
        provider.stop()
        XCTAssertNil(oldCommand.terminationHandler)
        provider.start()
        await fulfillment(of: [unexpected], timeout: 0.2)
    }

    @MainActor func testCurrentCommandFailureStillReportsUnavailable() async throws {
        let provider = MediaRemoteProvider { arguments in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments.first == "send" ? "/usr/bin/false" : "/bin/sleep")
            process.arguments = arguments.first == "send" ? [] : ["20"]
            return process
        }
        defer { provider.stop() }
        let failed = expectation(description: "Current command reports unavailable")
        let reader = Task {
            for await state in provider.updates {
                if state == .unavailable { failed.fulfill() }
            }
        }
        defer { reader.cancel() }
        provider.start()
        provider.send(.next)
        await fulfillment(of: [failed], timeout: 2)
    }

    private func failedProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
        try process.run()
        process.waitUntilExit()
        return process
    }
}
