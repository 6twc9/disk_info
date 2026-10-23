import SwiftUI

struct TreemapRect: Identifiable {
    let id = UUID()
    let node: DiskNode
    let rect: CGRect
}

/// Interactive Treemap (Binary Split Proportional Rectangles) view for comparing block areas at a glance
struct TreemapChartView: View {
    @ObservedObject var viewModel: DiskAppViewModel
    let focusedNode: DiskNode

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 12, dy: 12)
            let tiles = computeTreemap(nodes: focusedNode.children, in: bounds)

            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    let isHovered = (viewModel.hoveredNode?.id == tile.node.id)
                    let inBasket = viewModel.isInCollector(tile.node)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                DaisyPalette.color(
                                    hue: tile.node.colorHue,
                                    depth: 1,
                                    isHovered: isHovered,
                                    isSmallGroup: tile.node.isAggregatedSmallerItems
                                )
                                .opacity(inBasket ? 0.35 : 0.9)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isHovered ? Color.white : Color.black.opacity(0.35), lineWidth: isHovered ? 2 : 1)
                            )

                        if tile.rect.width > 56 && tile.rect.height > 34 {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: tile.node.isDirectory ? "folder.fill" : "doc.fill")
                                        .font(.system(size: 10))
                                    Text(tile.node.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)

                                Text(tile.node.formattedSize)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))

                                if tile.rect.height > 54 {
                                    Text(String(format: "%.1f%%", tile.node.percentage(relativeTo: focusedNode)))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                            .padding(6)
                        }
                    }
                    .frame(width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3))
                    .position(x: tile.rect.midX, y: tile.rect.midY)
                    .onTapGesture {
                        viewModel.drillDown(to: tile.node)
                    }
                    .onHover { hovering in
                        if hovering {
                            viewModel.hoveredNode = tile.node
                        } else if viewModel.hoveredNode?.id == tile.node.id {
                            viewModel.hoveredNode = nil
                        }
                    }
                    .contextMenu {
                        nodeContextMenu(for: tile.node)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nodeContextMenu(for node: DiskNode) -> some View {
        if !node.isAggregatedSmallerItems {
            Button {
                viewModel.revealInFinder(node)
            } label: {
                Label("在 Finder 中顯示 (Reveal in Finder)", systemImage: "folder.badge.gearshape")
            }

            Button {
                viewModel.openInTerminal(node)
            } label: {
                Label("在終端機開啟 (Open in Terminal)", systemImage: "terminal")
            }

            Button {
                viewModel.copyPath(node)
            } label: {
                Label("複製完整路徑", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                viewModel.addToCollector(node)
            } label: {
                Label("加入清理收集籃 (Collector)", systemImage: "trash.circle")
            }
        }
    }

    /// Recursive binary-partition treemap layout that keeps aspect ratios balanced
    private func computeTreemap(nodes: [DiskNode], in rect: CGRect) -> [TreemapRect] {
        let valid = nodes.filter { $0.size > 0 }
        guard !valid.isEmpty, rect.width > 4, rect.height > 4 else { return [] }

        var output: [TreemapRect] = []
        subdivide(nodes: valid, rect: rect, result: &output)
        return output
    }

    private func subdivide(nodes: [DiskNode], rect: CGRect, result: inout [TreemapRect]) {
        guard !nodes.isEmpty else { return }
        if nodes.count == 1 || rect.width < 14 || rect.height < 14 {
            result.append(TreemapRect(node: nodes[0], rect: rect))
            return
        }

        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return }

        // Find split index closest to half of total size
        var running: Int64 = 0
        var splitIndex = 1
        let half = total / 2
        for (idx, n) in nodes.enumerated() {
            running += n.size
            if running >= half {
                splitIndex = max(1, min(nodes.count - 1, idx + 1))
                break
            }
        }

        let leftNodes = Array(nodes[0..<splitIndex])
        let rightNodes = Array(nodes[splitIndex..<nodes.count])
        let leftWeight = Double(leftNodes.reduce(Int64(0)) { $0 + $1.size }) / Double(total)

        if rect.width >= rect.height {
            let leftW = CGFloat(leftWeight) * rect.width
            let r1 = CGRect(x: rect.minX, y: rect.minY, width: leftW, height: rect.height)
            let r2 = CGRect(x: rect.minX + leftW, y: rect.minY, width: rect.width - leftW, height: rect.height)
            subdivide(nodes: leftNodes, rect: r1, result: &result)
            subdivide(nodes: rightNodes, rect: r2, result: &result)
        } else {
            let topH = CGFloat(leftWeight) * rect.height
            let r1 = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topH)
            let r2 = CGRect(x: rect.minX, y: rect.minY + topH, width: rect.width, height: rect.height - topH)
            subdivide(nodes: leftNodes, rect: r1, result: &result)
            subdivide(nodes: rightNodes, rect: r2, result: &result)
        }
    }
}
