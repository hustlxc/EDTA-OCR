import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var apiKeyInput = ""
    @FocusState private var isKeyFieldFocused: Bool

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
            .padding(.bottom, 20)

            // Inline settings (toggle, no sheet)
            HStack(spacing: 24) {
                Button("查看历史记录") {
                    state.screen = .history
                }
                .font(.system(size: 13))
                .buttonStyle(.link)

                Button(showSettings ? "收起设置" : "AI 设置") {
                    if showSettings {
                        showSettings = false
                    } else {
                        apiKeyInput = state.apiKey
                        showSettings = true
                        isKeyFieldFocused = true
                    }
                }
                .font(.system(size: 13))
                .buttonStyle(.link)
            }

            if showSettings {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DeepSeek API Key")
                        .font(.system(size: 12, weight: .semibold))

                    HStack(spacing: 8) {
                        TextField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 340)
                            .focused($isKeyFieldFocused)
                            .onSubmit {
                                saveKey()
                            }

                        Button("保存") {
                            saveKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        if !state.apiKey.isEmpty {
                            Button("清除") {
                                state.saveAPIKey("")
                                apiKeyInput = ""
                                showSettings = false
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        }
                    }

                    Link("获取 API Key → platform.deepseek.com",
                         destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.system(size: 11))

                    Text("或通过环境变量: export DEEPSEEK_API_KEY=sk-...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        state.saveAPIKey(key)
        showSettings = false
    }
}
