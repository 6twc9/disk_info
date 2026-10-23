import Foundation
import SwiftUI

/// Represents a mounted volume / disk on macOS
struct VolumeInfo: Identifiable, Hashable {
    var id: URL { url }
    let name: String
    let url: URL
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isInternal: Bool
    let isRemovable: Bool

    var usedCapacity: Int64 {
        max(0, totalCapacity - availableCapacity)
    }

    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(1.0, Double(usedCapacity) / Double(totalCapacity))
    }

    static func fetchMountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsBrowsableKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }

            let available: Int64
            if let importantAvail = values.volumeAvailableCapacityForImportantUsage, importantAvail > 0 {
                available = Int64(importantAvail)
            } else {
                available = Int64(values.volumeAvailableCapacity ?? 0)
            }

            let isInternal = values.volumeIsInternal ?? (url.path == "/")
            let isRemovable = values.volumeIsRemovable ?? false

            volumes.append(VolumeInfo(
                name: name,
                url: url,
                totalCapacity: total,
                availableCapacity: available,
                isInternal: isInternal,
                isRemovable: isRemovable
            ))
        }

        // Also offer User Home directory as a quick target
        return volumes
    }
}

/// Represents a file or folder node in the scanned hierarchy
final class DiskNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var size: Int64
    var fileCount: Int
    var children: [DiskNode]
    weak var parent: DiskNode?
    var colorHue: Double
    let isAggregatedSmallerItems: Bool

    init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        fileCount: Int = 1,
        children: [DiskNode] = [],
        parent: DiskNode? = nil,
        colorHue: Double = 0.55,
        isAggregatedSmallerItems: Bool = false
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = fileCount
        self.children = children
        self.parent = parent
        self.colorHue = colorHue
        self.isAggregatedSmallerItems = isAggregatedSmallerItems
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Breadcrumb trail from root down to this node
    var breadcrumbs: [DiskNode] {
        var list: [DiskNode] = []
        var curr: DiskNode? = self
        while let node = curr {
            list.append(node)
            curr = node.parent
        }
        return list.reversed()
    }

    /// Percentage relative to parent node (or 100% if root)
    func percentage(relativeTo reference: DiskNode?) -> Double {
        let base = reference?.size ?? parent?.size ?? size
        guard base > 0 else { return 0 }
        return Double(size) / Double(base) * 100.0
    }

    /// Remove a deleted child node and bubble size reduction up to ancestors
    func removeChild(_ target: DiskNode) {
        guard let idx = children.firstIndex(where: { $0.id == target.id }) else { return }
        let removedSize = target.size
        let removedCount = target.fileCount
        children.remove(at: idx)

        var curr: DiskNode? = self
        while let node = curr {
            node.size = max(0, node.size - removedSize)
            node.fileCount = max(0, node.fileCount - removedCount)
            curr = node.parent
        }
    }

    static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Visual color helper for DaisyDisk-style rich radial palettes
enum DaisyPalette {
    static let rootHues: [Double] = [
        0.56, // Ocean Blue
        0.45, // Teal / Cyan
        0.34, // Emerald Green
        0.12, // Amber / Gold
        0.04, // Coral Orange
        0.94, // Rose / Crimson
        0.78, // Purple / Violet
        0.65  // Indigo
    ]

    static func color(hue: Double, depth: Int, isHovered: Bool = false, isSelected: Bool = false, isSmallGroup: Bool = false) -> Color {
        if isSmallGroup {
            return Color(white: isHovered ? 0.50 : 0.36)
        }
        let clampedDepth = min(max(depth, 1), 6)
        // Deeper rings become slightly lighter and slightly less saturated, matching DaisyDisk aesthetics
        let saturation = max(0.45, 0.82 - Double(clampedDepth - 1) * 0.06)
        let brightness = min(0.98, 0.78 + Double(clampedDepth - 1) * 0.04 + (isHovered ? 0.12 : 0.0) + (isSelected ? 0.08 : 0.0))
        return Color(hue: hue.truncatingRemainder(dividingBy: 1.0), saturation: saturation, brightness: brightness)
    }
}
