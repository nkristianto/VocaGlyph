import SwiftUI

public struct CustomConfirmationDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(title: String, message: String, confirmTitle: String, cancelTitle: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.navy)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 2)
            }

            // Buttons
            HStack(spacing: 12) {
                Spacer()
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.navy)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#F2EFE9"))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#EE6B6E"))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 400)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 8)
    }
}
