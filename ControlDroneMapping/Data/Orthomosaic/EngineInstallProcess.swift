import AppKit
import Darwin
import Foundation

/// Each installer command owns a process group, including compilers and package-manager children.
/// Cancellation stops that group before a retry can touch the same environment.
final class EngineInstallProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var cancelled = false
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.cancel(immediately: true) }
    }
    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String], log: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try self.execute(executable, arguments: arguments, environment: environment, log: log)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel(immediately: Bool = false) {
        lock.lock()
        cancelled = true
        let group = pid
        if group > 0 { kill(-group, immediately ? SIGKILL : SIGTERM) }
        lock.unlock()
        if group > 0 {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                self.lock.lock()
                defer { self.lock.unlock() }
                if self.pid == group { kill(-group, SIGKILL) }
            }
        }
    }

    private func execute(_ executable: URL, arguments: [String], environment: [String: String], log: URL)
        throws
    {
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        try output.seekToEnd()
        try output.write(contentsOf: Data(("\n" + executable.lastPathComponent + "\n").utf8))
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.compactMap { $0 }.forEach { free($0) }
            envp.compactMap { $0 }.forEach { free($0) }
        }
        lock.lock()
        if cancelled {
            lock.unlock()
            throw CancellationError()
        }
        var child: pid_t = 0
        let result = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(
                    &child, executable.path, &actions, &attributes,
                    UnsafeMutablePointer(mutating: args.baseAddress!),
                    UnsafeMutablePointer(mutating: env.baseAddress!))
            }
        }
        if result == 0 { pid = child }
        lock.unlock()
        guard result == 0 else {
            throw MappingError.invalid(
                "Pemasang tidak dapat dijalankan: " + String(cString: strerror(result)))
        }
        // WNOHANG lets cancellation finish killing children before releasing the installation folder.
        var status: Int32 = 0
        var waitResult: pid_t = 0
        repeat {
            waitResult = waitpid(child, &status, WNOHANG)
            if waitResult == 0 { Thread.sleep(forTimeInterval: 0.05) }
        } while waitResult == 0 || (waitResult < 0 && errno == EINTR)
        lock.lock()
        let stopped = cancelled
        if stopped { kill(-child, SIGKILL) }
        pid = 0
        lock.unlock()
        if stopped { throw CancellationError() }
        guard waitResult == child, status == 0 else {
            throw MappingError.invalid(
                "Pemasangan gagal pada \(executable.lastPathComponent). Buka rincian pemasangan untuk melihat penyebabnya."
            )
        }
    }
}
