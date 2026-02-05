import SwiftUI

struct SidebarView: View {
    @Binding var selected: NavigationSelection

    var body: some View {
        List(selection: $selected) {
            ForEach(NavigationSelection.allCases) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
    }
}
