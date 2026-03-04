import SwiftUI

struct CaptureView: View {
    var body: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity, minHeight: 260)
                .overlay {
                    Text("Camera Placeholder")
                        .foregroundStyle(.white)
                }
        }
        .padding()
    }
}
