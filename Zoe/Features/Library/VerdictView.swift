import SwiftUI

@MainActor
struct VerdictView: View {
    let item: LibraryItem

    var body: some View {
        Text("Verdict")
            .navigationTitle("")
            .accessibilityIdentifier(AX.Verdict.screenView)
    }
}
