import SwiftUI

/// Large page title that lives in scroll/List content (not the sticky nav bar).
struct ScrollablePageTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Clears the pinned navigation title so `ScrollablePageTitle` (or equivalent
    /// in-content title) can scroll with the page.
    /// - Parameter hideBar: On iOS, hide the empty navigation bar so content sits near the top.
    func scrollableNavigationTitle(hideBar: Bool = false) -> some View {
        self
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(ScrollableTitleBarVisibility(hidden: hideBar))
            #endif
    }
}

#if os(iOS)
private struct ScrollableTitleBarVisibility: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if hidden {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}
#endif

extension View {
    /// List row chrome for an in-content page title (avoids sticky section headers).
    func scrollableListTitleRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            #if os(iOS)
            .listRowSeparator(.hidden)
            #endif
            .listRowBackground(Color.clear)
    }
}
