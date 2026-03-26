import SwiftUI

struct ProvenanceDot: View {
    let state: VerificationState

    var body: some View {
        Group {
            switch state {
            case .verifying, .pending:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.mini)
            default:
                Circle()
                    .fill(state.dotColor)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
