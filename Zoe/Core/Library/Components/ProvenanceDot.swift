import SwiftUI

struct ProvenanceDot: View {
    let state: VerificationState

    var body: some View {
        Group {
            switch state {
            case .verifying:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.mini)
            default:
                Circle()
                    .fill(dotColor)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }

    private var dotColor: Color {
        switch state {
        case .signed, .authentic: return Color(.systemGreen)
        case .unsigned:           return Color(.systemYellow)
        case .tampered:           return Color(.systemRed)
        case .notVerified:        return Color(.systemGray)
        case .verifying:          return .clear  // never reached — handled above
        }
    }
}
