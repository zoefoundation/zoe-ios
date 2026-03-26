import SwiftUI

struct ProvenancePill: View {
    let state: VerificationState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: pillIcon)
                    .font(.system(size: 12))
                Text(pillLabel)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(pillColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(pillColor.opacity(borderOpacity), lineWidth: 1.5)
            }
        }
        .accessibilityLabel("Provenance: \(state.pillShortLabel). Tap for details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AX.MediaDetail.verdictPill)
    }

    private var pillColor: Color {
        switch state {
        case .authentic, .signed: return Color(.systemGreen)
        case .tampered:           return Color(.systemRed)
        case .notVerified:        return Color(.systemGray)
        case .pending:            return Color(.systemOrange)
        case .unsigned, .verifying: return Color(.systemGray)
        }
    }

    private var borderOpacity: Double {
        switch state {
        case .notVerified, .pending: return 0.35
        default:                     return 0.45
        }
    }

    private var pillIcon: String {
        switch state {
        case .authentic, .signed: return "checkmark"
        case .tampered:           return "xmark"
        case .notVerified:        return "minus"
        case .pending:            return "arrow.up.circle"
        case .unsigned, .verifying: return "minus"
        }
    }

    private var pillLabel: String {
        switch state {
        case .authentic, .signed: return "Authentic"
        case .tampered:           return "Tampered"
        case .notVerified:        return "Not Verified"
        case .pending:            return "Pending Upload"
        case .unsigned:           return "Unsigned"
        case .verifying:          return "Verifying"
        }
    }
}
