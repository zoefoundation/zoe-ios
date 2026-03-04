import SwiftUI

struct ProvenancePill: View {
    let state: VerificationState

    var body: some View {
        Text(state.rawValue)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
