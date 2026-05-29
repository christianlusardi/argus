import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.appTextPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }
}

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appTextPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appTextTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appAccent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DeltaBadge: View {
    let pct: Double  // 0.15 = +15%

    var body: some View {
        let isPositive = pct >= 0
        let arrow = isPositive ? "↑" : "↓"
        let color = isPositive
            ? Color(red: 0.9, green: 0.3, blue: 0.3)
            : Color(red: 0.3, green: 0.9, blue: 0.4)
        Text("\(arrow)\(String(format: "%.0f", abs(pct * 100)))%")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
    }
}

struct TokenStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.appTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

enum ChartCrosshair {
    static let lineColor = Color.appTextSecondary.opacity(0.55)
    static let lineDash = StrokeStyle(lineWidth: 1, dash: [4, 3])

    @ViewBuilder
    static func verticalLine(plotRect: CGRect, xPos: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: xPos, y: plotRect.minY))
            p.addLine(to: CGPoint(x: xPos, y: plotRect.maxY))
        }
        .stroke(lineColor, style: lineDash)
    }

    @ViewBuilder
    static func horizontalLine(plotRect: CGRect, yPos: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: plotRect.minX, y: yPos))
            p.addLine(to: CGPoint(x: plotRect.maxX, y: yPos))
        }
        .stroke(lineColor, style: lineDash)
    }

    @ViewBuilder
    static func point(xPos: CGFloat, yPos: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .position(x: xPos, y: yPos)
    }

    static func tooltip<C: View>(
        plotRect: CGRect,
        xPos: CGFloat,
        yPos: CGFloat,
        @ViewBuilder content: () -> C
    ) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 0.5))
            .position(
                x: min(max(xPos + 56, plotRect.minX + 56), plotRect.maxX - 56),
                y: max(yPos - 26, plotRect.minY + 18)
            )
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.appAccent)
            Text("Loading metrics…")
                .foregroundStyle(Color.appTextSecondary)
                .font(.callout)
        }
    }
}

struct ErrorView: View {
    let message: String
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.orange)
            Text("Could not load stats")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Retry") { store.loadData() }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.appAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .font(.system(size: 13, weight: .medium))
        }
    }
}
