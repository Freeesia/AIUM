import SwiftUI

/// Places the provider sections in columns and stacks each column on its own,
/// so a short section is not padded to the height of a tall neighbor.
///
/// Sections go to columns in reading order (left to right, then the next row
/// of columns). With two columns and a vertical display division, such as the
/// fold of iPhone Duo, the gap between the columns is placed on the division.
///
/// The column count is a layout parameter, so the sections keep their view
/// identity when folding, resizing, or changing text size.
struct DashboardColumnsLayout: Layout {
    var columnCount: Int
    var spacing: CGFloat
    /// Horizontal extent of a vertical display division in this layout's
    /// coordinate space. Zero width when the display is flat.
    var division: ClosedRange<CGFloat>?
    /// Narrowest column allowed when aligning to the division.
    var minimumColumnWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth(subviews: subviews)
        let frames = arrange(width: width, subviews: subviews)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Horizontal extent of each column for the given width.
    func columns(width: CGFloat, count: Int) -> [(x: CGFloat, width: CGFloat)] {
        let count = max(count, 1)
        if count == 2, let split = divisionSplit(width: width) {
            return [(0, split.leftWidth), (split.rightX, width - split.rightX)]
        }
        let columnWidth = max((width - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
        return (0..<count).map { index in
            (CGFloat(index) * (columnWidth + spacing), columnWidth)
        }
    }

    // MARK: - Private

    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard !subviews.isEmpty else { return [] }
        let columns = columns(width: width, count: min(columnCount, subviews.count))
        var columnHeights = Array(repeating: CGFloat.zero, count: columns.count)

        return subviews.indices.map { index in
            let column = index % columns.count
            let (x, columnWidth) = columns[column]
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let y = columnHeights[column] == 0 ? 0 : columnHeights[column] + spacing
            columnHeights[column] = y + height
            return CGRect(x: x, y: y, width: columnWidth, height: height)
        }
    }

    /// Splits around the division when both columns stay wide enough.
    private func divisionSplit(width: CGFloat) -> (leftWidth: CGFloat, rightX: CGFloat)? {
        guard let division else { return nil }
        let center = (division.lowerBound + division.upperBound) / 2
        let leftWidth = min(division.lowerBound, center - spacing / 2)
        let rightX = max(division.upperBound, center + spacing / 2)
        guard leftWidth >= minimumColumnWidth, width - rightX >= minimumColumnWidth else { return nil }
        return (leftWidth, rightX)
    }

    private func idealWidth(subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}

extension DashboardColumnsLayout {
    /// The vertical display division (fold) inside the view, if any.
    static func verticalDivision(in proxy: GeometryProxy) -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let bounds = CGRect(origin: .zero, size: proxy.size)
        return proxy.reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { frame in
                frame.width <= frame.height
                    && frame.midX > bounds.minX && frame.midX < bounds.maxX
            }
            .map { $0.minX...$0.maxX }
    }
}
