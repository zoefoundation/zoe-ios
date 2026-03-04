import SwiftUI

struct ProvenanceDot: View {
    let state: VerificationState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .authentic:   return .green
        case .tampered:    return .red
        case .signed:      return .blue
        case .unsigned:    return .gray
        case .verifying:   return .yellow
        case .notVerified: return .secondary
        }
    }
}
