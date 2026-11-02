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
    func scrollableNavigationTitle() -> some View {
        self
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

extension View {
    /// List row chrome for an in-content page title (avoids sticky section headers).
    func scrollableListTitleRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            #if os(iOS)
            .listRowSeparator(.hidden)
            #endif
            .listRowBackground(Color.clear)
    }
}
