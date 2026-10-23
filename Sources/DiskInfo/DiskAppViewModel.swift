import Foundation
import SwiftUI
import AppKit

enum VisualizationMode: String, CaseIterable, Identifiable {
    case sunburst = "太陽爆發圖 (Sunburst)"
    case treemap = "樹狀矩形圖 (Treemap)"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .sunburst: return "chart.pie.fill"
        case .treemap: return "square.grid.3x2.fill"
        }
    }
}

@MainActor
final class DiskAppViewModel: ObservableObject {
    @Published var volumes: [VolumeInfo] = []
    @Published var selectedTargetURL: URL?

    // Scan state
    @Published var isScanning: Bool = false
    @Published var scannedFilesCount: Int = 0
    @Published var scannedBytesCount: Int64 = 0
    @Published var currentScanningPath: String = ""
    @Published var permissionDeniedCount: Int = 0
    @Published var scanDuration: TimeInterval = 0

    // Hierarchy & Focus state
    @Published var rootNode: DiskNode?
    @Published var focusedNode: DiskNode?
    @Published var hoveredNode: DiskNode?
    @Published var searchQuery: String = ""
    @Published var visualizationMode: VisualizationMode = .sunburst
    @Published var scannedTargetSizes: [String: Int64] = [:]

    // DaisyDisk-style Collector (Basket for staged deletion)
    @Published var collectorItems: [DiskNode] = []
    @Published var isCollectorExpanded: Bool = false
    @Published var statusToastMessage: String?

    private var activeScanner: FastDiskScanner?
    private var progressTimer: Timer?
    private var scanStartTime: Date?
    private var appActiveObserver: NSObjectProtocol?

    init() {
        refreshVolumes()
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshVolumes()
            }
        }
    }

    func refreshVolumes() {
        volumes = VolumeInfo.fetchMountedVolumes()
        if selectedTargetURL == nil {
            selectedTargetURL = volumes.first?.url
        }
    }

    /// Refresh volume capacities immediately and again after APFS asynchronous extent reaping completes
    func refreshVolumesWithAPFSDelay() {
        refreshVolumes()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshVolumes()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshVolumes()
        }
    }

    /// Pick any custom directory using NSOpenPanel
    func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.title = "選擇要分析空間的資料夾或磁碟"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            selectedTargetURL = url
            startScan(url: url)
        }
    }

    func startScan(url: URL) {
        cancelScan()
        refreshVolumes()

        selectedTargetURL = url
        isScanning = true
        scannedFilesCount = 0
        scannedBytesCount = 0
        currentScanningPath = url.path
        permissionDeniedCount = 0
        rootNode = nil
        focusedNode = nil
        hoveredNode = nil
        scanStartTime = Date()

        let scanner = FastDiskScanner()
        self.activeScanner = scanner

        // Poll progress at 15fps for smooth UI counter updates
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let active = self.activeScanner else { return }
                let snap = active.snapshot()
                self.scannedFilesCount = snap.scannedFiles
                self.scannedBytesCount = snap.scannedBytes
                self.currentScanningPath = snap.currentPath
                self.permissionDeniedCount = snap.permissionDeniedCount
            }
        }

        let targetPath = url.path
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await scanner.scan(rootPath: targetPath)
            await MainActor.run {
                guard let self = self else { return }
                self.progressTimer?.invalidate()
                self.progressTimer = nil
                self.isScanning = false

                if let start = self.scanStartTime {
                    self.scanDuration = Date().timeIntervalSince(start)
                }

                if let root = result.root {
                    self.rootNode = root
                    self.focusedNode = root
                    self.scannedBytesCount = root.size
                    self.scannedFilesCount = root.fileCount
                    self.permissionDeniedCount = result.permissionDeniedCount
                    self.scannedTargetSizes[targetPath] = root.size
                }
                self.refreshVolumesWithAPFSDelay()
            }
        }
    }

    func cancelScan() {
        activeScanner?.cancel()
        activeScanner = nil
        progressTimer?.invalidate()
        progressTimer = nil
        isScanning = false
    }

    func drillDown(to node: DiskNode) {
        guard !node.isAggregatedSmallerItems else { return }
        if node.isDirectory && !node.children.isEmpty {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                focusedNode = node
                hoveredNode = nil
            }
        } else {
            revealInFinder(node)
        }
    }

    func navigateUp() {
        guard let current = focusedNode, let parent = current.parent else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            focusedNode = parent
            hoveredNode = nil
        }
    }

    // MARK: - Finder & System Integration

    func revealInFinder(_ node: DiskNode) {
        let url = URL(fileURLWithPath: node.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInTerminal(_ node: DiskNode) {
        let dirPath = node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
        let url = URL(fileURLWithPath: dirPath)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func copyPath(_ node: DiskNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
        showToast("已複製路徑：\(node.path)")
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Collector (Staged Cleanup Basket)

    var collectorTotalBytes: Int64 {
        collectorItems.reduce(0) { $0 + $1.size }
    }

    func isInCollector(_ node: DiskNode) -> Bool {
        collectorItems.contains(where: { $0.path == node.path })
    }

    func addToCollector(_ node: DiskNode) {
        guard !node.isAggregatedSmallerItems else { return }
        // Prevent adding root `/` or system folders accidentally
        if node.path == "/" || node.path == "/System" || node.path == "/Applications" || node.path == "/Users" {
            showToast("系統核心目錄受保護，不可加入清理籃")
            return
        }
        // Check if already covered by an ancestor or already in collector
        if collectorItems.contains(where: { node.path == $0.path || node.path.hasPrefix($0.path + "/") }) {
            showToast("此項目已包含在收集籃中")
            return
        }
        // Remove any children already in collector if parent is added
        collectorItems.removeAll(where: { $0.path.hasPrefix(node.path + "/") })
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            collectorItems.append(node)
        }
        showToast("已加入收集籃：\(node.name) (\(node.formattedSize))")
    }

    func removeFromCollector(_ node: DiskNode) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            collectorItems.removeAll(where: { $0.id == node.id || $0.path == node.path })
        }
    }

    func clearCollector() {
        withAnimation {
            collectorItems.removeAll()
        }
    }

    func moveCollectorItemsToTrash() {
        guard !collectorItems.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "確定要清理收集籃中的 \(collectorItems.count) 個項目嗎？"
        let totalStr = ByteCountFormatter.string(fromByteCount: collectorTotalBytes, countStyle: .file)
        alert.informativeText = """
        預計可處理 \(totalStr) 的空間：
        • 「立即永久刪除」：直接從磁碟移除檔案，立即釋放硬碟可用空間（不可還原）。
        • 「移至垃圾桶」：移至 macOS 垃圾桶（需清空垃圾桶後系統才會釋放硬碟空間）。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "立即永久刪除 (直接釋放 \(totalStr))")
        alert.addButton(withTitle: "移至垃圾桶")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
        let isPermanent = (response == .alertFirstButtonReturn)

        performDeletion(items: collectorItems, permanently: isPermanent)
        collectorItems.removeAll()
    }

    func deleteSingleNode(_ node: DiskNode, permanently: Bool) {
        guard !node.isAggregatedSmallerItems else { return }
        if node.path == "/" || node.path == "/System" || node.path == "/Applications" || node.path == "/Users" {
            showToast("系統核心目錄受保護，不可刪除")
            return
        }

        let alert = NSAlert()
        alert.messageText = permanently ? "確定要永久刪除「\(node.name)」嗎？" : "確定要將「\(node.name)」移至垃圾桶嗎？"
        alert.informativeText = permanently
            ? "此操作將直接從磁碟永久移除該項目（\(node.formattedSize)），並立即釋放磁碟空間，無法復原。"
            : "此項目（\(node.formattedSize)）將移至 macOS 垃圾桶，清空垃圾桶後即可釋放硬碟空間。"
        alert.alertStyle = permanently ? .critical : .warning
        alert.addButton(withTitle: permanently ? "立即永久刪除 (\(node.formattedSize))" : "移至垃圾桶")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        performDeletion(items: [node], permanently: permanently)
        removeFromCollector(node)
    }

    private func performDeletion(items: [DiskNode], permanently: Bool) {
        var deletedCount = 0
        var freedBytes: Int64 = 0
        var failedNames: [String] = []

        for item in items {
            let fileURL = URL(fileURLWithPath: item.path)
            do {
                if permanently {
                    try FileManager.default.removeItem(at: fileURL)
                } else {
                    try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                }
                deletedCount += 1
                freedBytes += item.size
                // Update in-memory tree immediately so charts and sidebar reflect freed space
                if focusedNode?.id == item.id {
                    focusedNode = item.parent ?? rootNode
                }
                item.parent?.removeChild(item)
            } catch {
                failedNames.append(item.name)
            }
        }

        if let root = rootNode {
            scannedBytesCount = root.size
            scannedFilesCount = root.fileCount
            scannedTargetSizes[root.path] = root.size
        }

        objectWillChange.send()
        refreshVolumesWithAPFSDelay()

        let freedStr = ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
        if failedNames.isEmpty {
            if permanently {
                showToast("已永久刪除 \(deletedCount) 個項目，立即釋放 \(freedStr) 空間！")
            } else {
                showToast("已將 \(deletedCount) 個項目移至垃圾桶 (\(freedStr))")
            }
        } else {
            showToast("已處理 \(freedStr)，但有 \(failedNames.count) 項因權限不足無法刪除")
        }
    }

    // MARK: - Search / Filter within focused node

    var displayedChildren: [DiskNode] {
        guard let focus = focusedNode else { return [] }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return focus.children }

        // Deep search up to 3 levels under focusedNode when query is entered
        var matches: [DiskNode] = []
        func searchRecursive(_ node: DiskNode, depth: Int) {
            if depth > 4 || matches.count >= 100 { return }
            for child in node.children {
                if !child.isAggregatedSmallerItems && child.name.lowercased().contains(query) {
                    matches.append(child)
                }
                if child.isDirectory {
                    searchRecursive(child, depth: depth + 1)
                }
            }
        }
        searchRecursive(focus, depth: 0)
        return matches.sorted { $0.size > $1.size }
    }

    func showToast(_ message: String) {
        withAnimation {
            statusToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            if self?.statusToastMessage == message {
                withAnimation {
                    self?.statusToastMessage = nil
                }
            }
        }
    }
}
