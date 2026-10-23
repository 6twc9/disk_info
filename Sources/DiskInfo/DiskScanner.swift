import Foundation
import Darwin

/// Progress snapshot emitted during multi-threaded disk scanning
struct ScanProgress: Sendable {
    let scannedFiles: Int
    let scannedBytes: Int64
    let currentPath: String
    let permissionDeniedCount: Int
}

/// High-speed concurrent POSIX directory scanner designed for macOS
final class FastDiskScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var _scannedFiles: Int = 0
    private var _scannedBytes: Int64 = 0
    private var _permissionDeniedCount: Int = 0
    private var _currentPath: String = ""

    /// Maximum children retained individually per folder before grouping remaining small items into "Smaller Items"
    /// Keeps the UI tree ultra-responsive even on 2M+ file drives while preserving 100% accurate total sizes.
    private let maxIndividualChildrenPerDirectory = 48

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }

    func snapshot() -> ScanProgress {
        lock.lock()
        defer { lock.unlock() }
        return ScanProgress(
            scannedFiles: _scannedFiles,
            scannedBytes: _scannedBytes,
            currentPath: _currentPath,
            permissionDeniedCount: _permissionDeniedCount
        )
    }

    private func addStats(files: Int, bytes: Int64, path: String? = nil, denied: Int = 0) {
        lock.lock()
        _scannedFiles += files
        _scannedBytes += bytes
        _permissionDeniedCount += denied
        if let path = path {
            _currentPath = path
        }
        lock.unlock()
    }

    /// Scans `rootPath` and builds a sorted `DiskNode` hierarchy.
    /// Avoids crossing filesystem boundaries (`st_dev`) when scanning `/` so `/Volumes/*` or `/System/Volumes/Data` aren't double-counted.
    func scan(rootPath: String) async -> (root: DiskNode?, permissionDeniedCount: Int) {
        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0 else {
            return (nil, 1)
        }
        let rootDev = rootStat.st_dev
        let isScanningRoot = (rootPath == "/")

        // Read top-level entries to fan out across CPU cores
        let rootName = rootPath == "/" ? "Macintosh HD" : (rootPath as NSString).lastPathComponent
        let rootNode = DiskNode(
            name: rootName.isEmpty ? rootPath : rootName,
            path: rootPath,
            isDirectory: true,
            colorHue: 0.56
        )

        let topEntries = listEntries(at: rootPath, rootDev: rootDev, isScanningRoot: isScanningRoot)
        let queue = DispatchQueue(label: "com.diskinfo.scanner.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var topChildren: [DiskNode] = []

        for (index, entry) in topEntries.enumerated() {
            if isCancelled { break }
            let baseHue = DaisyPalette.rootHues[index % DaisyPalette.rootHues.count]

            if entry.isDirectory {
                group.enter()
                queue.async { [weak self] in
                    defer { group.leave() }
                    guard let self = self, !self.isCancelled else { return }
                    if let childNode = self.scanDirectoryRecursive(
                        path: entry.path,
                        name: entry.name,
                        rootDev: rootDev,
                        isScanningRoot: isScanningRoot,
                        depth: 1,
                        hue: baseHue
                    ) {
                        resultLock.lock()
                        topChildren.append(childNode)
                        resultLock.unlock()
                    }
                }
            } else {
                let fileNode = DiskNode(
                    name: entry.name,
                    path: entry.path,
                    isDirectory: false,
                    size: entry.size,
                    fileCount: 1,
                    colorHue: baseHue
                )
                addStats(files: 1, bytes: entry.size)
                resultLock.lock()
                topChildren.append(fileNode)
                resultLock.unlock()
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global(qos: .userInitiated)) {
                continuation.resume()
            }
        }

        if isCancelled {
            return (nil, snapshot().permissionDeniedCount)
        }

        finalizeNode(rootNode, rawChildren: topChildren, depth: 0)
        return (rootNode, snapshot().permissionDeniedCount)
    }

    private struct RawEntry {
        let name: String
        let path: String
        let isDirectory: Bool
        let size: Int64
    }

    private func listEntries(at dirPath: String, rootDev: dev_t, isScanningRoot: Bool) -> [RawEntry] {
        guard let dir = opendir(dirPath) else {
            // macOS external volumes set `.Trashes` to mode 0311 (-wx--x--t), which blocks opendir(".Trashes")
            // while still allowing access to `.Trashes/<uid>`.
            if (dirPath as NSString).lastPathComponent == ".Trashes" {
                let uidStr = String(getuid())
                let userTrashPath = "\(dirPath)/\(uidStr)"
                var st = stat()
                if lstat(userTrashPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                    return [RawEntry(name: "\(uidStr) (垃圾桶)", path: userTrashPath, isDirectory: true, size: 0)]
                }
            }
            if errno == EACCES || errno == EPERM {
                addStats(files: 0, bytes: 0, denied: 1)
            }
            return []
        }
        defer { closedir(dir) }

        var entries: [RawEntry] = []
        let prefix = dirPath == "/" ? "" : dirPath

        while let ent = readdir(dir) {
            if isCancelled { break }

            let nameLen = Int(ent.pointee.d_namlen)
            // Skip "." and ".."
            if nameLen == 1 && ent.pointee.d_name.0 == 46 { continue }
            if nameLen == 2 && ent.pointee.d_name.0 == 46 && ent.pointee.d_name.1 == 46 { continue }

            let name: String = withUnsafePointer(to: ent.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: nameLen + 1) { cStr in
                    String(cString: cStr)
                }
            }

            let fullPath = "\(prefix)/\(name)"

            // Skip virtual/firmlink mount points when scanning root `/` to avoid scanning external drives or duplicate `/System/Volumes/Data`
            if isScanningRoot {
                if fullPath == "/Volumes" || fullPath == "/dev" || fullPath == "/System/Volumes/Data" || fullPath == "/net" || fullPath == "/home" {
                    continue
                }
            }

            var st = stat()
            guard lstat(fullPath, &st) == 0 else { continue }

            let mode = st.st_mode & S_IFMT
            // Skip symbolic links and special device nodes
            if mode == S_IFLNK || mode == S_IFSOCK || mode == S_IFIFO || mode == S_IFCHR || mode == S_IFBLK {
                continue
            }

            if mode == S_IFDIR {
                // Prevent crossing into external mounted volumes unless scanning `/Volumes` explicitly
                if isScanningRoot && st.st_dev != rootDev && !fullPath.hasPrefix("/System") && !fullPath.hasPrefix("/Users") && !fullPath.hasPrefix("/Applications") && !fullPath.hasPrefix("/Library") && !fullPath.hasPrefix("/private") && !fullPath.hasPrefix("/usr") && !fullPath.hasPrefix("/opt") {
                    continue
                }
                entries.append(RawEntry(name: name, path: fullPath, isDirectory: true, size: 0))
            } else if mode == S_IFREG {
                // Use actual allocated blocks (`st_blocks * 512`) so sparse files / cloud placeholders don't report fake terabytes,
                // falling back to logical size if blocks == 0 and st_size > 0
                let allocatedSize = Int64(st.st_blocks) * 512
                let logicalSize = Int64(st.st_size)
                let effectiveSize = allocatedSize > 0 ? allocatedSize : logicalSize
                entries.append(RawEntry(name: name, path: fullPath, isDirectory: false, size: effectiveSize))
            }
        }

        return entries
    }

    private func scanDirectoryRecursive(
        path: String,
        name: String,
        rootDev: dev_t,
        isScanningRoot: Bool,
        depth: Int,
        hue: Double
    ) -> DiskNode? {
        if isCancelled { return nil }

        if depth <= 3 {
            addStats(files: 0, bytes: 0, path: path)
        }

        let entries = listEntries(at: path, rootDev: rootDev, isScanningRoot: isScanningRoot)
        var childNodes: [DiskNode] = []
        childNodes.reserveCapacity(min(entries.count, 64))

        var localFiles = 0
        var localBytes: Int64 = 0

        // For shallow depths (<= 2), parallelize large subdirectories
        if depth <= 2 && entries.count > 4 {
            let subQueue = DispatchQueue(label: "com.diskinfo.sub.\(depth)", attributes: .concurrent)
            let subGroup = DispatchGroup()
            let subLock = NSLock()

            for (idx, entry) in entries.enumerated() {
                if isCancelled { break }
                let childHue = (hue + Double(idx % 7) * 0.018).truncatingRemainder(dividingBy: 1.0)
                if entry.isDirectory {
                    subGroup.enter()
                    subQueue.async { [weak self] in
                        defer { subGroup.leave() }
                        guard let self = self, !self.isCancelled else { return }
                        if let subNode = self.scanDirectoryRecursive(
                            path: entry.path,
                            name: entry.name,
                            rootDev: rootDev,
                            isScanningRoot: isScanningRoot,
                            depth: depth + 1,
                            hue: childHue
                        ) {
                            subLock.lock()
                            childNodes.append(subNode)
                            subLock.unlock()
                        }
                    }
                } else {
                    localFiles += 1
                    localBytes += entry.size
                    let fileNode = DiskNode(
                        name: entry.name,
                        path: entry.path,
                        isDirectory: false,
                        size: entry.size,
                        fileCount: 1,
                        colorHue: childHue
                    )
                    subLock.lock()
                    childNodes.append(fileNode)
                    subLock.unlock()
                }
            }
            subGroup.wait()
        } else {
            for (idx, entry) in entries.enumerated() {
                if isCancelled { break }
                let childHue = (hue + Double(idx % 5) * 0.012).truncatingRemainder(dividingBy: 1.0)
                if entry.isDirectory {
                    if let subNode = scanDirectoryRecursive(
                        path: entry.path,
                        name: entry.name,
                        rootDev: rootDev,
                        isScanningRoot: isScanningRoot,
                        depth: depth + 1,
                        hue: childHue
                    ) {
                        childNodes.append(subNode)
                    }
                } else {
                    localFiles += 1
                    localBytes += entry.size
                    childNodes.append(DiskNode(
                        name: entry.name,
                        path: entry.path,
                        isDirectory: false,
                        size: entry.size,
                        fileCount: 1,
                        colorHue: childHue
                    ))
                }
            }
        }

        if localFiles > 0 || localBytes > 0 {
            addStats(files: localFiles, bytes: localBytes)
        }

        let node = DiskNode(
            name: name,
            path: path,
            isDirectory: true,
            colorHue: hue
        )
        finalizeNode(node, rawChildren: childNodes, depth: depth)
        return node
    }

    private func finalizeNode(_ node: DiskNode, rawChildren: [DiskNode], depth: Int) {
        // Sort largest to smallest
        let sorted = rawChildren.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        var totalSize: Int64 = 0
        var totalFiles: Int = 0

        for child in sorted {
            totalSize += child.size
            totalFiles += child.fileCount
        }

        node.size = totalSize
        node.fileCount = max(1, totalFiles)

        // Assign distinct hues to top-level children so each major folder has its own color family
        if depth == 0 {
            for (idx, child) in sorted.enumerated() {
                let rootHue = DaisyPalette.rootHues[idx % DaisyPalette.rootHues.count]
                recolorSubtree(child, baseHue: rootHue)
            }
        }

        if sorted.count > maxIndividualChildrenPerDirectory {
            var kept = Array(sorted.prefix(maxIndividualChildrenPerDirectory))
            let remainder = sorted.dropFirst(maxIndividualChildrenPerDirectory)
            let remSize = remainder.reduce(Int64(0)) { $0 + $1.size }
            let remFiles = remainder.reduce(0) { $0 + $1.fileCount }

            if remSize > 0 {
                let aggregated = DiskNode(
                    name: "其他較小項目 (\(remainder.count) 項)",
                    path: node.path,
                    isDirectory: false,
                    size: remSize,
                    fileCount: remFiles,
                    parent: node,
                    colorHue: node.colorHue,
                    isAggregatedSmallerItems: true
                )
                kept.append(aggregated)
            }
            for child in kept {
                child.parent = node
            }
            node.children = kept
        } else {
            for child in sorted {
                child.parent = node
            }
            node.children = sorted
        }
    }

    private func recolorSubtree(_ node: DiskNode, baseHue: Double) {
        node.colorHue = baseHue
        for (idx, child) in node.children.enumerated() {
            let childHue = (baseHue + Double(idx % 6) * 0.015).truncatingRemainder(dividingBy: 1.0)
            recolorSubtree(child, baseHue: childHue)
        }
    }
}
