import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var apiKeyInput = ""

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

            VStack(spacing: 8) {
                Text("状态: 就绪")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("已录入: \(state.recordCount) 条")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if state.hasAPIKey {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                        Text("DeepSeek AI 增强已启用")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("AI 识别未配置")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 32)

            HStack(spacing: 24) {
                Button("查看历史记录") {
                    state.screen = .history
                }
                .font(.system(size: 13))
                .buttonStyle(.link)

                Button("AI 设置") {
                    apiKeyInput = state.apiKey
                    showSettings = true
                }
                .font(.system(size: 13))
                .buttonStyle(.link)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("DeepSeek AI 设置")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .semibold))
                    Text("输入 DeepSeek API Key 以启用 AI 智能识别")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("保存") {
                            let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
                            state.saveAPIKey(key)
                            showSettings = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Text("API Key 存储在本地钥匙串中，不会上传至任何第三方")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Link("获取 API Key → DeepSeek 官网",
                     destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                    .font(.system(size: 11))

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("或通过环境变量设置:")
                        .font(.system(size: 11))
                    Text("export DEEPSEEK_API_KEY=sk-your-key-here")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(20)
            .frame(width: 420)
        }
        .frame(width: 420, height: 320)
    }
}
