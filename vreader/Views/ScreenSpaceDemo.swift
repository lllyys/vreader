import SwiftUI

/// Debug view that visualizes available screen space, safe areas, and insets.
/// Swap into ContentView.body temporarily to inspect layout boundaries.
struct ScreenSpaceDemo: View {
    var body: some View {
        GeometryReader { fullScreen in
            ZStack {
                // Full screen area (including behind safe areas)
                Color.black
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        Text("Full screen: \(fmt(fullScreen.size))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 4)
                            .ignoresSafeArea()
                    }

                // Safe area (where content should live)
                GeometryReader { safeArea in
                    let insets = fullScreen.safeAreaInsets

                    VStack(spacing: 0) {
                        // Top inset indicator
                        insetBar(
                            label: "top: \(fmt1(insets.top))pt",
                            height: insets.top,
                            color: .red.opacity(0.3)
                        )
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)

                        // Main content area
                        ZStack {
                            Color.blue.opacity(0.08)

                            VStack(spacing: 16) {
                                Text("Usable Content Area")
                                    .font(.title2.bold())

                                Text("\(fmt(safeArea.size))")
                                    .font(.title3.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                Divider().frame(width: 200)

                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                    gridRow("Screen", fmt(fullScreen.size))
                                    gridRow("Safe area", fmt(safeArea.size))
                                    gridRow("Top inset", "\(fmt1(insets.top))pt")
                                    gridRow("Bottom inset", "\(fmt1(insets.bottom))pt")
                                    gridRow("Leading", "\(fmt1(insets.leading))pt")
                                    gridRow("Trailing", "\(fmt1(insets.trailing))pt")
                                }
                                .font(.body.monospacedDigit())

                                Divider().frame(width: 200)

                                VStack(spacing: 4) {
                                    Text("Usable ratio")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    let ratio = fullScreen.size.height > 0
                                        ? (safeArea.size.height / fullScreen.size.height) * 100
                                        : 0
                                    Text("\(fmt1(ratio))%")
                                        .font(.title.bold())
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Bottom inset indicator
                        insetBar(
                            label: "bottom: \(fmt1(insets.bottom))pt",
                            height: insets.bottom,
                            color: .red.opacity(0.3)
                        )
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .bottom)
                    }

                    // Leading / trailing inset markers
                    if insets.leading > 0 {
                        HStack {
                            Color.orange.opacity(0.3)
                                .frame(width: insets.leading)
                                .ignoresSafeArea(edges: .leading)
                            Spacer()
                        }
                    }
                    if insets.trailing > 0 {
                        HStack {
                            Spacer()
                            Color.orange.opacity(0.3)
                                .frame(width: insets.trailing)
                                .ignoresSafeArea(edges: .trailing)
                        }
                    }
                }

                // Corner markers showing screen edges
                cornerMarkers()
            }
        }
    }

    // MARK: - Subviews

    private func insetBar(label: String, height: CGFloat, color: Color) -> some View {
        ZStack {
            color
            if height > 16 {
                Text(label)
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            }
        }
        .frame(height: height)
    }

    private func gridRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func cornerMarkers() -> some View {
        ZStack {
            // Top-left
            VStack { HStack { crosshair(); Spacer() }; Spacer() }
            // Top-right
            VStack { HStack { Spacer(); crosshair() }; Spacer() }
            // Bottom-left
            VStack { Spacer(); HStack { crosshair(); Spacer() } }
            // Bottom-right
            VStack { Spacer(); HStack { Spacer(); crosshair() } }
        }
        .ignoresSafeArea()
    }

    private func crosshair() -> some View {
        Image(systemName: "plus")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
            .padding(4)
    }

    // MARK: - Formatting

    private func fmt(_ size: CGSize) -> String {
        "\(fmt1(size.width)) x \(fmt1(size.height))pt"
    }

    private func fmt1(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
    }
}

#Preview {
    ScreenSpaceDemo()
}
