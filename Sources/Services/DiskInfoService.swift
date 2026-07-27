import Foundation

/// Volume free/total space for the header stat.
enum DiskInfoService {
    struct VolumeStats {
        let freeBytes: Int64
        let totalBytes: Int64
    }

    static func stats() -> VolumeStats? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let free = values.volumeAvailableCapacity,
              let total = values.volumeTotalCapacity else { return nil }
        return VolumeStats(freeBytes: Int64(free), totalBytes: Int64(total))
    }
}
