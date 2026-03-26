enum VerificationState: String, CaseIterable {
    case signed
    case unsigned
    case authentic
    case tampered
    case notVerified
    case verifying
    case pending    // signed locally, proof upload to server pending (e.g. captured offline)
}

extension VerificationState {
    var accessibilityLabel: String {
        switch self {
        case .signed:      return "Signed"
        case .unsigned:    return "Unsigned — signing failed at capture time"
        case .authentic:   return "Authentic"
        case .tampered:    return "Tampered — content was modified after signing"
        case .notVerified: return "Not Verified — no provenance signature found"
        case .verifying:   return "verifying provenance"
        case .pending:     return "Pending — upload in progress"
        }
    }

    var pillShortLabel: String {
        switch self {
        case .signed:      return "Signed"
        case .unsigned:    return "Unsigned"
        case .authentic:   return "Authentic"
        case .tampered:    return "Tampered"
        case .notVerified: return "Not Verified"
        case .verifying:   return "Verifying"
        case .pending:     return "Pending Upload"
        }
    }
}

import SwiftUI
import UIKit

extension VerificationState {
    var verdictColor: Color {
        switch self {
        case .authentic, .signed: return Color(.systemGreen)
        case .tampered:           return Color(.systemRed)
        case .notVerified:        return Color(.systemGray)
        case .unsigned:           return Color(.systemRed)
        case .pending:            return Color(.systemOrange)
        case .verifying:          return Color(.systemGray)
        }
    }

    var verdictIconName: String {
        switch self {
        case .authentic, .signed: return "checkmark"
        case .tampered:           return "xmark"
        case .notVerified:        return "minus"
        case .unsigned:           return "exclamationmark.triangle"
        case .pending:            return "arrow.up.circle"
        case .verifying:          return "hourglass"
        }
    }

    var verdictDescription: String {
        switch self {
        case .authentic, .signed:
            return "Signed by a genuine attested device. Unmodified since capture."
        case .tampered:
            return "This file has been modified since signing. Content does not match the original."
        case .notVerified:
            return "No Zoe signature found. This does not indicate tampering — provenance cannot be confirmed."
        case .unsigned:
            return "Signing failed at capture time (device key unavailable or revoked). No provenance claim available."
        case .pending:
            return "Signed locally — proof upload pending. Will verify automatically when connected."
        case .verifying:
            return "Verifying provenance…"
        }
    }

    var verdictHapticType: UINotificationFeedbackGenerator.FeedbackType? {
        switch self {
        case .authentic, .signed: return .success
        case .tampered:           return .error
        case .unsigned:           return .error
        case .pending, .notVerified, .verifying: return nil
        }
    }
}

extension VerificationState {
    var dotColor: Color {
        switch self {
        case .signed, .authentic: return Color(.systemGreen)
        case .unsigned:           return Color(.systemRed)
        case .tampered:           return Color(.systemRed)
        case .notVerified:        return Color(.systemGray)
        case .pending:            return Color(.systemOrange)
        case .verifying:          return .clear  // spinner handles display — colour unused
        }
    }
}
