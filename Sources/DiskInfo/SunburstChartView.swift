import SwiftUI

/// Represents one computed arc segment in the DaisyDisk-style multi-ring Sunburst chart
struct SunburstArc: Identifiable {
    let id = UUID()
    let node: DiskNode
    let depth: Int // 1 ..< maxRings
    let startAngle: Double // radians, 0 at top (-pi/2)
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
}

/// Interactive multi-ring Sunburst visualization inspired by DaisyDisk
struct SunburstChartView: View {
    @ObservedObject var viewModel: DiskAppViewModel
    let focusedNode: DiskNode

    private let maxRings = 5
    private let minSweepRadians = 0.008 // Skip sub-pixel slivers for speed & clarity

    @State private var canvasSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) * 0.45
            let innerHoleRadius = max(58, maxRadius * 0.27)
            let ringThickness = max(18, (maxRadius - innerHoleRadius) / CGFloat(maxRings))
            let arcs = buildArcs(
                root: focusedNode,
                innerHoleRadius: innerHoleRadius,
                ringThickness: ringThickness
            )

            ZStack {
                // High-performance Canvas for multi-ring arcs
                Canvas { context, _ in
                    for arc in arcs {
                        let isHovered = (viewModel.hoveredNode?.id == arc.node.id)
                        let isAncestorOfHovered = isAncestor(arc.node, of: viewModel.hoveredNode)
                        let inBasket = viewModel.isInCollector(arc.node)

                        var path = Path()
                        let rIn = arc.innerRadius + 1.0
                        let rOut = arc.outerRadius - 1.0 + (isHovered ? 3.5 : 0)

                        path.addArc(
                            center: center,
                            radius: rOut,
                            startAngle: .radians(arc.startAngle - .pi / 2),
                            endAngle: .radians(arc.endAngle - .pi / 2),
                            clockwise: false
                        )
                        path.addArc(
                            center: center,
                            radius: rIn,
                            startAngle: .radians(arc.endAngle - .pi / 2),
                            endAngle: .radians(arc.startAngle - .pi / 2),
                            clockwise: true
                        )
                        path.closeSubpath()

                        let fillColor = DaisyPalette.color(
                            hue: arc.node.colorHue,
                            depth: arc.depth,
                            isHovered: isHovered || isAncestorOfHovered,
                            isSmallGroup: arc.node.isAggregatedSmallerItems
                        )

                        context.fill(path, with: .color(inBasket ? fillColor.opacity(0.35) : fillColor))

                        // Subtle dark separator stroke like DaisyDisk
                        context.stroke(
                            path,
                            with: .color(isHovered ? Color.white.opacity(0.9) : Color.black.opacity(0.35)),
                            lineWidth: isHovered ? 1.8 : 0.8
                        )

                        // Draw label on large enough arcs in ring 1 & 2
                        let sweep = arc.endAngle - arc.startAngle
                        if arc.depth <= 2 && sweep > 0.26 && ringThickness > 26 {
                            let midAngle = (arc.startAngle + arc.endAngle) / 2 - .pi / 2
                            let midRadius = (rIn + rOut) / 2
                            let labelPt = CGPoint(
                                x: center.x + CGFloat(cos(midAngle)) * midRadius,
                                y: center.y + CGFloat(sin(midAngle)) * midRadius
                            )
                            let shortName = arc.node.name.count > 13
                                ? String(arc.node.name.prefix(11)) + "…"
                                : arc.node.name
                            let text = Text(shortName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                            context.draw(text, at: labelPt)
                        }
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            if let hit = hitTest(
                                point: event.location,
                                center: center,
                                innerHoleRadius: innerHoleRadius,
                                arcs: arcs
                            ) {
                                viewModel.drillDown(to: hit)
                            } else if hypot(event.location.x - center.x, event.location.y - center.y) <= innerHoleRadius {
                                viewModel.navigateUp()
                            }
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        viewModel.hoveredNode = hitTest(
                            point: location,
                            center: center,
                            innerHoleRadius: innerHoleRadius,
                            arcs: arcs
                        )
                    case .ended:
                        viewModel.hoveredNode = nil
                    }
                }

                // Center Hub (DaisyDisk signature center circle)
                centerHub(radius: innerHoleRadius)
                    .position(center)
            }
        }
    }

    @ViewBuilder
    private func centerHub(radius: CGFloat) -> some View {
        let displayNode = viewModel.hoveredNode ?? focusedNode
        let isHoveringChild = (viewModel.hoveredNode != nil && viewModel.hoveredNode?.id != focusedNode.id)

        Button {
            viewModel.navigateUp()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.19, green: 0.21, blue: 0.26),
                                Color(red: 0.12, green: 0.13, blue: 0.17)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: radius
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

                VStack(spacing: 4) {
                    if focusedNode.parent != nil && !isHoveringChild {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.left.up")
                                .font(.system(size: 10, weight: .bold))
                            Text("回上一層")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    } else if isHoveringChild {
                        Text(String(format: "%.1f%%", displayNode.percentage(relativeTo: focusedNode)))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                    }

                    Text(displayNode.formattedSize)
                        .font(.system(size: max(15, radius * 0.23), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text(displayNode.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: radius * 1.65)

                    Text("\(displayNode.fileCount.formatted()) 個檔案")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .frame(width: radius * 2, height: radius * 2)
        }
        .buttonStyle(.plain)
        .help(focusedNode.parent != nil ? "點擊返回上層目錄 (\(focusedNode.parent!.name))" : "目前已是根目錄")
    }

    // MARK: - Geometry Computation & Hit Testing

    private func buildArcs(
        root: DiskNode,
        innerHoleRadius: CGFloat,
        ringThickness: CGFloat
    ) -> [SunburstArc] {
        guard root.size > 0 else { return [] }
        var result: [SunburstArc] = []
        result.reserveCapacity(220)

        func traverse(
            parent: DiskNode,
            depth: Int,
            startAngle: Double,
            endAngle: Double
        ) {
            guard depth <= maxRings, parent.size > 0 else { return }
            let totalAngle = endAngle - startAngle
            var currentAngle = startAngle

            let rIn = innerHoleRadius + CGFloat(depth - 1) * ringThickness
            let rOut = innerHoleRadius + CGFloat(depth) * ringThickness

            for child in parent.children {
                guard child.size > 0 else { continue }
                let fraction = Double(child.size) / Double(parent.size)
                let sweep = totalAngle * fraction
                guard sweep >= minSweepRadians else {
                    currentAngle += sweep
                    continue
                }

                let nextAngle = currentAngle + sweep
                result.append(SunburstArc(
                    node: child,
                    depth: depth,
                    startAngle: currentAngle,
                    endAngle: nextAngle,
                    innerRadius: rIn,
                    outerRadius: rOut
                ))

                if child.isDirectory && !child.children.isEmpty && depth < maxRings {
                    traverse(
                        parent: child,
                        depth: depth + 1,
                        startAngle: currentAngle,
                        endAngle: nextAngle
                    )
                }

                currentAngle = nextAngle
            }
        }

        traverse(parent: root, depth: 1, startAngle: 0, endAngle: .pi * 2)
        return result
    }

    private func hitTest(
        point: CGPoint,
        center: CGPoint,
        innerHoleRadius: CGFloat,
        arcs: [SunburstArc]
    ) -> DiskNode? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        guard dist > innerHoleRadius else { return nil }

        // Angle from top (0 ..< 2*pi clockwise)
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += .pi * 2 }

        for arc in arcs {
            if dist >= arc.innerRadius && dist <= arc.outerRadius &&
               angle >= arc.startAngle && angle <= arc.endAngle {
                return arc.node
            }
        }
        return nil
    }

    private func isAncestor(_ candidate: DiskNode, of target: DiskNode?) -> Bool {
        var curr = target?.parent
        while let node = curr {
            if node.id == candidate.id { return true }
            curr = node.parent
        }
        return false
    }
}
