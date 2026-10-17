import SwiftUI

/// How tall the map's sheet is. It snaps to one of these after a drag.
enum SheetDetent: CaseIterable, Hashable {
    case peek, half, full

    func height(in available: CGFloat) -> CGFloat {
        switch self {
        case .peek: 200
        case .half: max(320, available * 0.5)
        case .full: available - 12
        }
    }
}

/// An Apple Maps-style sheet that floats above the tab bar: glass, rounded, and
/// draggable by its header. The content scrolls only when the sheet is all the way up.
struct MapSheet<Header: View, Content: View>: View {
    @Binding var detent: SheetDetent
    var available: CGFloat
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        let base = detent.height(in: available)
        let height = min(available - 12, max(140, base - drag))
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Palette.muted.opacity(0.45))
                    .frame(width: 36, height: 5)
                    .padding(.top, 7)
                    .padding(.bottom, 8)
                header()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(base: base))
            .onTapGesture { if detent == .peek { detent = .half } }

            ScrollView {
                content()
                    .padding(.bottom, 16)
            }
            .scrollDisabled(detent != .full)
            .scrollIndicators(.hidden)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 30))
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 8)
        .animation(.snappy(duration: 0.3), value: detent)
    }

    private func dragGesture(base: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let target = base - value.predictedEndTranslation.height
                detent = SheetDetent.allCases.min {
                    abs($0.height(in: available) - target) < abs($1.height(in: available) - target)
                } ?? detent
            }
    }
}
