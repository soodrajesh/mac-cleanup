import Foundation

/// Sizes folders/files by shelling out to `du` rather than walking the tree in
/// Swift — `du` is a tuned C implementation and is dramatically faster on
/// folders with tens of thousands of files (e.g. Xcode DerivedData).
enum SizeCalculator {
    /// Runs `du -sk <path>` and returns the size in bytes, or nil on failure
    /// (e.g. permission denied) — callers surface that as `.failed`, not a crash.
    static func size(of url: URL) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let firstField = output.split(separator: "\t").first ?? output.split(separator: " ").first ?? ""
            guard let kb = Int64(firstField.trimmingCharacters(in: .whitespaces)) else { return nil }
            return kb * 1024
        } catch {
            return nil
        }
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
