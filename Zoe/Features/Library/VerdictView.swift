import SwiftUI
import CryptoKit

@MainActor
struct VerdictView: View {
    let item: LibraryItem

    @State private var isExpanded = false
    @State private var showShareSheet = false
    @State private var contentHashExcerpt = "computing…"
    @State private var heroVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var verdictState: VerificationState {
        VerificationState(rawValue: item.verificationState) ?? .notVerified
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                Divider()
                metadataSection
                technicalDetailSection
                shareReportButton
            }
            .padding()
        }
        .accessibilityIdentifier(AX.Verdict.screenView)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fireHaptic()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                heroVisible = true
            }
        }
        .task { await computeContentHash() }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [reportString])
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(verdictState.verdictColor.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: verdictState.verdictIconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(verdictState.verdictColor)
            }
            Text(verdictState.rawValue.capitalized)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(verdictState.verdictColor)
            Text(verdictState.verdictDescription)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .accessibilityIdentifier(verdictStatusIdentifier)
        .accessibilityLabel("\(verdictState.rawValue.capitalized). \(verdictState.verdictDescription)")
        .opacity(heroVisible ? 1 : 0)
        .offset(y: heroVisible ? 0 : 24)
    }

    private var verdictStatusIdentifier: String {
        switch verdictState {
        case .authentic, .signed: return AX.Verdict.statusAuthentic
        case .tampered:           return AX.Verdict.statusTampered
        case .unsigned:           return AX.Verdict.statusUnsigned
        default:                  return AX.Verdict.statusNotVerified
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 0) {
            metadataRow(label: "Signed", value: formattedSigningTime)
                .accessibilityIdentifier(AX.Verdict.signingTime)
            metadataRow(label: "Source", value: item.source)
            metadataRow(label: "Key", value: kidExcerpt)
                .accessibilityIdentifier(AX.Verdict.kidExcerpt)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 15))
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var formattedSigningTime: String {
        guard let date = item.verdictSigningTime else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }

    private var kidExcerpt: String {
        guard let kid = item.kid, !kid.isEmpty else { return "—" }
        return String(kid.prefix(8)) + "…"
    }

    // MARK: - Technical Detail

    private var technicalDetailSection: some View {
        DisclosureGroup("Technical detail", isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                technicalRow(label: "Key ID", value: item.kid ?? "—", mono: true)
                technicalRow(label: "Algorithm", value: "ECDSA P-256")
                technicalRow(label: "Schema", value: "zoe.media.v1")
                technicalRow(label: "Content hash", value: contentHashExcerpt, mono: true)
            }
            .padding(.top, 8)
        }
    }

    private func technicalRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.system(size: 13))
    }

    // MARK: - Share Report

    private var shareReportButton: some View {
        Button("Share Report") {
            showShareSheet = true
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(.systemBlue))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(AX.Verdict.shareReportButton)
    }

    private var reportString: String {
        """
        Zoe Provenance Report
        =====================
        Verdict:     \(verdictState.rawValue.capitalized)
        Description: \(verdictState.verdictDescription)
        Signed:      \(formattedSigningTime)
        Source:      \(item.source)
        Key:         \(kidExcerpt)
        Generated:   \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))
        """
    }

    // MARK: - Helpers

    private func fireHaptic() {
        guard let type = verdictState.verdictHapticType else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    private func computeContentHash() async {
        guard let data = try? Data(contentsOf: item.resolvedMediaURL) else {
            contentHashExcerpt = "unavailable"
            return
        }
        let digest = SHA256.hash(data: data)
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        contentHashExcerpt = String(hex.prefix(16)) + "…"
    }
}
