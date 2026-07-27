import Foundation

/// Sizes folders/files by shelling out to `du` rather than walking the tree in
/// Swift — `du` is a tuned C implementation and is dramatically faster on
/// folders with tens of thousands of files (e.g. Xcode DerivedData).
enum SizeCalculator {
    /// Runs `du -sk <path>` and returns the size in bytes, or nil on failure
    /// (e.g. permission denied) — callers surface that as `.failed`, not a crash.
    ///
    /// `du` commonly hits "Operation not permitted" on individual
    /// sub-entries it can't read (routine under another app's
    /// Container/Application Support) and writes one line per hit to
    /// stderr, while still exiting with a correct top-level summary on
    /// stdout — so stdout is parsed regardless of exit status, exactly as
    /// before. Critically, stderr is discarded straight to `/dev/null`
    /// rather than piped: piping it and never reading it (the previous
    /// bug here) meant enough permission errors — trivially reached
    /// recursing into another app's sandboxed Container — filled the pipe's
    /// kernel buffer and made `du` block on writing to it forever, which
    /// looked exactly like App Cleaner's size column spinning forever,
    /// since `sizeAll` below only runs a handful of these concurrently and
    /// everything queues up behind the one stuck call. Verified fixed
    /// end-to-end against a real 24GB Container that previously triggered
    /// this.
    ///
    /// The timeout is a second, independent line of defense for the rarer
    /// case of a path that hangs for an unrelated reason (an unresponsive
    /// network mount, say) — past the deadline, kill it; a single bad path
    /// degrades to "failed to measure," not a stuck scan.
    static func size(of url: URL, timeoutSeconds: TimeInterval = 20) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog)

        // Read to EOF before waiting on exit — `du -sk` only ever emits one
        // short line on stdout, so this can't deadlock on *that* pipe
        // filling, and reading first means a watchdog-triggered terminate()
        // reliably unblocks this call instead of racing it.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let firstField = output.split(separator: "\t").first ?? output.split(separator: " ").first ?? ""
        guard let kb = Int64(firstField.trimmingCharacters(in: .whitespaces)) else { return nil }
        return kb * 1024
    }

    /// Sizes many items concurrently (bounded), publishing each result to
    /// `onSized` as soon as it's known so the UI fills in progressively
    /// instead of blocking on the slowest item.
    static func sizeAll(_ urls: [URL], maxConcurrent: Int = 5, onSized: @escaping @Sendable (URL, Int64?) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = urls.makeIterator()

            func startNext() {
                guard let url = iterator.next() else { return }
                group.addTask {
                    let n = size(of: url)
                    onSized(url, n)
                }
            }

            for _ in 0..<maxConcurrent { startNext() }
            while await group.next() != nil {
                startNext()
            }
        }
    }
}
