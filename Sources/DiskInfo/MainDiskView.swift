import SwiftUI

struct MainDiskView: View {
    @StateObject private var viewModel = DiskAppViewModel()

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 230, ideal: 255, max: 300)
        } detail: {
            ZStack(alignment: .bottom) {
                Color(red: 0.09, green: 0.10, blue: 0.13)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topHeaderBar
                    Divider().overlay(Color.white.opacity(0.08))

                    if viewModel.isScanning {
                        scanningProgressView
                    } else if let focused = viewModel.focusedNode {
                        HSplitView {
                            // Left: Interactive Sunburst or Treemap Visualization
                            ZStack(alignment: .bottomLeading) {
                                Group {
                                    switch viewModel.visualizationMode {
                                    case .sunburst:
                                        SunburstChartView(viewModel: viewModel, focusedNode: focused)
                                    case .treemap:
                                        TreemapChartView(viewModel: viewModel, focusedNode: focused)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                                hoveredInspectorBanner
                            }
                            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                            // Right: DaisyDisk-style Ranked Folder / File Breakdown List
                            rankedDirectoryList(focused: focused)
                                .frame(minWidth: 340, idealWidth: 390, maxWidth: 480, maxHeight: .infinity)
                        }
                    } else {
                        emptyWelcomeView
                    }

                    // Bottom Collector (Cleanup Basket) Dock
                    collectorDockBar
                }

                // Toast Notification
                if let toast = viewModel.statusToastMessage {
                    Text(toast)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.82))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        )
                        .shadow(radius: 8)
                        .padding(.bottom, 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar (Mounted Disks & Quick Targets)

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundStyle(.cyan)
                Text("磁碟與儲存空間")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button {
                    viewModel.refreshVolumes()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("重新整理掛載磁碟")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(viewModel.volumes) { vol in
                        volumeCard(vol)
                    }

                    Divider().padding(.vertical, 4)

                    // Quick Home Directory Shortcut
                    let homeURL = FileManager.default.homeDirectoryForCurrentUser
                    quickFolderButton(
                        title: "個人專屬目錄 (~)",
                        subtitle: homeURL.path,
                        icon: "house.fill",
                        url: homeURL
                    )

                    // Active Custom Folder Card (if user picked a custom folder other than mounted volumes or ~)
                    if let targetURL = viewModel.selectedTargetURL,
                       targetURL != homeURL,
                       !viewModel.volumes.contains(where: { $0.url == targetURL }) {
                        quickFolderButton(
                            title: targetURL.lastPathComponent.isEmpty ? targetURL.path : targetURL.lastPathComponent,
                            subtitle: targetURL.path,
                            icon: "folder.fill",
                            url: targetURL
                        )
                    }

                    // Choose Any Custom Folder
                    Button {
                        viewModel.selectCustomFolder()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 17))
                                .foregroundStyle(.mint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("選擇任意資料夾掃描…")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("指定任意目錄分析佔用空間")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Spacer()

            // Full Disk Access helper banner
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.orange)
                    Text("完整磁碟取用權限")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Text("若掃描系統目錄或 Library 時遇到受保護資料夾，可開啟權限以獲得 100% 精準結果。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("開啟系統隱私設定…") {
                    viewModel.openFullDiskAccessSettings()
                }
                .font(.system(size: 11, weight: .medium))
                .controlSize(.small)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
        }
    }

    private func volumeCard(_ vol: VolumeInfo) -> some View {
        let isSelected = (viewModel.selectedTargetURL == vol.url)
        let usedStr = ByteCountFormatter.string(fromByteCount: vol.usedCapacity, countStyle: .file)
        let availStr = ByteCountFormatter.string(fromByteCount: vol.availableCapacity, countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: vol.totalCapacity, countStyle: .file)
        let scannedBytes = viewModel.scannedTargetSizes[vol.url.path]

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: vol.isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(vol.usedFraction > 0.85 ? .orange : .cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vol.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text("可用 \(availStr) / 共 \(totalStr)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Capacity Gauge Bar
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: vol.usedFraction > 0.85 ? [.orange, .red] : [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, barGeo.size.width * vol.usedFraction))
                }
            }
            .frame(height: 6)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已使用 \(usedStr) (\(Int(vol.usedFraction * 100))%)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let scannedBytes = scannedBytes {
                        Text("實測掃描：\(ByteCountFormatter.string(fromByteCount: scannedBytes, countStyle: .file))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                }
                Spacer()
                Button {
                    viewModel.startScan(url: vol.url)
                } label: {
                    Text((isSelected && viewModel.rootNode != nil) || scannedBytes != nil ? "重新掃描" : "掃描")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.cyan.opacity(0.22)))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(isSelected ? Color.cyan.opacity(0.13) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(isSelected ? Color.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.startScan(url: vol.url)
        }
    }

    private func quickFolderButton(title: String, subtitle: String, icon: String, url: URL) -> some View {
        let isSelected = (viewModel.selectedTargetURL == url)
        let scannedBytes = viewModel.scannedTargetSizes[url.path]
        return Button {
            viewModel.startScan(url: url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.cyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let scannedBytes = scannedBytes {
                        Text("已使用：\(ByteCountFormatter.string(fromByteCount: scannedBytes, countStyle: .file))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                }
                Spacer()
                Text(scannedBytes != nil ? "重新掃描" : "掃描")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.cyan.opacity(0.13) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.cyan.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Top Breadcrumb & Mode Toolbar

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            if let focused = viewModel.focusedNode {
                // Back button
                Button {
                    viewModel.navigateUp()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(focused.parent == nil)

                // Interactive Breadcrumb Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(focused.breadcrumbs.enumerated()), id: \.element.id) { idx, crumb in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    viewModel.focusedNode = crumb
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: idx == 0 ? "internaldrive.fill" : "folder.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(crumb.id == focused.id ? .cyan : .secondary)
                                    Text(crumb.name)
                                        .font(.system(size: 12, weight: crumb.id == focused.id ? .bold : .medium))
                                        .foregroundStyle(crumb.id == focused.id ? .white : .secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(crumb.id == focused.id ? Color.cyan.opacity(0.18) : Color.white.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("請從左側選擇磁碟或資料夾開始掃描")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.focusedNode != nil {
                // Chart Mode Switcher (Sunburst vs Treemap)
                Picker("圖表模式", selection: $viewModel.visualizationMode) {
                    ForEach(VisualizationMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if let target = viewModel.selectedTargetURL {
                    Button {
                        viewModel.startScan(url: target)
                    } label: {
                        Label("重新掃描", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.22))
    }

    // MARK: - Live Multi-threaded Scanning View

    private var scanningProgressView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.cyan.opacity(0.18), lineWidth: 6)
                    .frame(width: 110, height: 110)

                ProgressView()
                    .scaleEffect(1.6)
                    .tint(.cyan)
            }

            Text("正在極速掃描磁碟空間…")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            HStack(spacing: 28) {
                VStack(spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.scannedBytesCount, countStyle: .file))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text("已累計空間")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 36)

                VStack(spacing: 4) {
                    Text(viewModel.scannedFilesCount.formatted())
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.mint)
                    Text("已掃描檔案數")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
            )

            Text(viewModel.currentScanningPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)

            Button("取消掃描") {
                viewModel.cancelScan()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty Welcome State

    private var emptyWelcomeView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .mint, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("DiskInfo — DaisyDisk 風格磁碟空間分析")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("點擊左側任意磁碟、個人專屬目錄，或選擇指定資料夾，即可透過多線程極速找出最佔空間的資料夾。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            HStack(spacing: 14) {
                Button {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    viewModel.startScan(url: home)
                } label: {
                    Label("掃描個人目錄 (~)", systemImage: "house.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button {
                    viewModel.selectCustomFolder()
                } label: {
                    Label("選擇任意資料夾…", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Left Hovered Node Inspector

    @ViewBuilder
    private var hoveredInspectorBanner: some View {
        if let hovered = viewModel.hoveredNode {
            HStack(spacing: 10) {
                Circle()
                    .fill(DaisyPalette.color(hue: hovered.colorHue, depth: 1, isSmallGroup: hovered.isAggregatedSmallerItems))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(hovered.name)
                            .font(.system(size: 12.5, weight: .bold))
                            .lineLimit(1)
                        Text(hovered.formattedSize)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.cyan)
                    }
                    Text(hovered.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.68))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .padding(14)
        }
    }

    // MARK: - Right Column: Ranked Folder & File List

    private func rankedDirectoryList(focused: DiskNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Directory Summary Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(focused.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text("\(focused.fileCount.formatted()) 個檔案 · 掃描耗時 \(String(format: "%.1f", viewModel.scanDuration)) 秒")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(focused.formattedSize)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.cyan)
                }

                // Search bar inside current folder subtree
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("搜尋此目錄下的大型資料夾或檔案…", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(14)
            .background(Color.white.opacity(0.03))

            Divider().overlay(Color.white.opacity(0.08))

            // Permission warning if some folders were skipped
            if viewModel.permissionDeniedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text("有 \(viewModel.permissionDeniedCount) 個受保護目錄因權限不足略過")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("授權") {
                        viewModel.openFullDiskAccessSettings()
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            // Ranked items list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.displayedChildren) { item in
                        directoryRow(item: item, parent: focused)
                    }
                }
                .padding(10)
            }
        }
        .background(Color.black.opacity(0.18))
    }

    private func directoryRow(item: DiskNode, parent: DiskNode) -> some View {
        let isHovered = (viewModel.hoveredNode?.id == item.id)
        let pct = item.percentage(relativeTo: parent)
        let inBasket = viewModel.isInCollector(item)
        let badgeColor = DaisyPalette.color(
            hue: item.colorHue,
            depth: 1,
            isHovered: isHovered,
            isSmallGroup: item.isAggregatedSmallerItems
        )

        return HStack(spacing: 10) {
            // Color pill indicator matching Sunburst segment
            RoundedRectangle(cornerRadius: 4)
                .fill(badgeColor)
                .frame(width: 10, height: 26)

            Image(systemName: item.isAggregatedSmallerItems ? "ellipsis.circle.fill" : (item.isDirectory ? "folder.fill" : "doc.fill"))
                .font(.system(size: 14))
                .foregroundStyle(badgeColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(inBasket ? Color.secondary : Color.white)
                        .strikethrough(inBasket)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text(item.formattedSize)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                // Proportional bar + percentage
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(badgeColor)
                                .frame(width: max(3, geo.size.width * CGFloat(min(1.0, pct / 100.0))))
                        }
                    }
                    .frame(height: 5)

                    Text(String(format: "%.1f%%", pct))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }

            if !item.isAggregatedSmallerItems {
                HStack(spacing: 4) {
                    Button {
                        viewModel.revealInFinder(item)
                    } label: {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中顯示")

                    Button {
                        if inBasket {
                            viewModel.removeFromCollector(item)
                        } else {
                            viewModel.addToCollector(item)
                        }
                    } label: {
                        Image(systemName: inBasket ? "minus.circle.fill" : "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(inBasket ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(inBasket ? "從收集籃移除" : "加入待清理收集籃 (Collector)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.11) : Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.drillDown(to: item)
        }
        .onHover { hovering in
            if hovering {
                viewModel.hoveredNode = item
            } else if viewModel.hoveredNode?.id == item.id {
                viewModel.hoveredNode = nil
            }
        }
        .contextMenu {
            if !item.isAggregatedSmallerItems {
                Button {
                    viewModel.drillDown(to: item)
                } label: {
                    Label(item.isDirectory ? "進入此資料夾" : "在 Finder 顯示", systemImage: "arrow.right.circle")
                }

                Button {
                    viewModel.revealInFinder(item)
                } label: {
                    Label("在 Finder 中顯示 (Reveal in Finder)", systemImage: "folder")
                }

                Button {
                    viewModel.openInTerminal(item)
                } label: {
                    Label("在終端機開啟 (Open in Terminal)", systemImage: "terminal")
                }

                Button {
                    viewModel.copyPath(item)
                } label: {
                    Label("複製完整路徑", systemImage: "doc.on.doc")
                }

                Divider()

                Button {
                    viewModel.addToCollector(item)
                } label: {
                    Label("加入清理收集籃 (Collector)", systemImage: "plus.circle")
                }

                Button {
                    viewModel.deleteSingleNode(item, permanently: false)
                } label: {
                    Label("移至垃圾桶…", systemImage: "trash")
                }

                Button(role: .destructive) {
                    viewModel.deleteSingleNode(item, permanently: true)
                } label: {
                    Label("立即永久刪除 (直接釋放空間)…", systemImage: "trash.slash.fill")
                }
            }
        }
    }

    // MARK: - DaisyDisk-Style Collector (Cleanup Basket) Dock

    private var collectorDockBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.1))

            if viewModel.isCollectorExpanded && !viewModel.collectorItems.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.collectorItems) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                    .foregroundStyle(.orange)
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(item.path)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(item.formattedSize)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                Button {
                                    viewModel.removeFromCollector(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 160)
                .background(Color.black.opacity(0.35))
                Divider().overlay(Color.white.opacity(0.08))
            }

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(viewModel.collectorItems.isEmpty ? Color.white.opacity(0.08) : Color.orange.opacity(0.22))
                            .frame(width: 32, height: 32)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(viewModel.collectorItems.isEmpty ? Color.secondary : Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("清理收集籃 (Collector)")
                                .font(.system(size: 12.5, weight: .bold))
                            if !viewModel.collectorItems.isEmpty {
                                Text("\(viewModel.collectorItems.count) 項")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(
                            viewModel.collectorItems.isEmpty
                            ? "點擊右側清單的「+」或右鍵選單，將不需要的大型資料夾加入待刪清單"
                            : "預計可釋放 \(ByteCountFormatter.string(fromByteCount: viewModel.collectorTotalBytes, countStyle: .file))"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(viewModel.collectorItems.isEmpty ? Color.secondary : Color.orange)
                    }
                }

                Spacer()

                if !viewModel.collectorItems.isEmpty {
                    Button {
                        withAnimation {
                            viewModel.isCollectorExpanded.toggle()
                        }
                    } label: {
                        Label(
                            viewModel.isCollectorExpanded ? "收合清單" : "檢視清單",
                            systemImage: viewModel.isCollectorExpanded ? "chevron.down" : "chevron.up"
                        )
                        .font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered)

                    Button("清空收集籃") {
                        viewModel.clearCollector()
                    }
                    .font(.system(size: 11.5))
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.moveCollectorItemsToTrash()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("清理項目 (釋放 \(ByteCountFormatter.string(fromByteCount: viewModel.collectorTotalBytes, countStyle: .file)))")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.32))
        }
    }
}
