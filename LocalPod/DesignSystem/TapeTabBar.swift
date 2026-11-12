import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The signature tape-deck tab bar. Import, Inbox and Diagnostics moved into
/// Settings, so only the two core destinations remain; the labels still mirror
/// the root screens so `app.buttons["资料库"]` keeps working while the system
/// bar is hidden.
struct TapeTabBar: View {
    @Binding var selection: Int

    private struct Item: Identifiable {
        let tag: Int
        let title: String
        let icon: String
        let activeIcon: String
        var id: Int { tag }
    }

    private var items: [Item] {
        [
            Item(tag: 0, title: L10n.string("资料库"), icon: "books.vertical", activeIcon: "books.vertical.fill"),
            Item(tag: 1, title: L10n.string("tab.playback"), icon: "play.circle", activeIcon: "play.circle.fill")
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 7)
        .padding(.bottom, 4)
        .background {
            TapeTheme.cream
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TapeTheme.ink)
                .frame(height: TapeTheme.stroke)
        }
    }

    private func tabButton(_ item: Item) -> some View {
        let isActive = selection == item.tag
        return Button {
            guard selection != item.tag else { return }
            TapeTheme.tapHaptic()
            withAnimation(TapeTheme.spring) {
                selection = item.tag
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isActive {
                        Circle()
                            .fill(TapeTheme.acid)
                            .overlay(Circle().strokeBorder(TapeTheme.ink, lineWidth: TapeTheme.stroke))
                            .shadow(color: TapeTheme.ink, radius: 0, x: 2, y: 2)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    Image(systemName: isActive ? item.activeIcon : item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isActive ? TapeTheme.ink : TapeTheme.muted)
                        .frame(width: 32, height: 32)
                }
                .frame(width: 34, height: 34)

                Text(item.title)
                    .font(TapeType.tab)
                    .foregroundStyle(isActive ? TapeTheme.ink : TapeTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(isActive ? .isSelected : AccessibilityTraits())
        }
        .buttonStyle(TapeTabPressStyle())
    }
}

private struct TapeTabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(TapeTheme.press, value: configuration.isPressed)
    }
}
