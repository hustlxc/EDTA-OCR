import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("EDTA 采血管 OCR 录入系统")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.primary)

                Text("Blood Collection Tube OCR")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)

            Button(action: { state.screen = .camera }) {
                Label("打开摄像头并拍照", systemImage: "camera.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 240, height: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)

            VStack(spacing: 6) {
                Text("状态: 就绪")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("已录入: \(state.recordCount) 条")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)

            Button("查看历史记录") {
                state.screen = .history
            }
            .font(.system(size: 13))
            .buttonStyle(.link)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
