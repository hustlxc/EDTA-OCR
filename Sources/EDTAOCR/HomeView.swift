import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false
    @State private var apiKeyInput = ""
    @FocusState private var isKeyFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EDTA 采血管 OCR 录入系统")
                        .font(.system(size: 24, weight: .bold))
                    Text("拍照、识别、核对、保存")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { state.screen = .history }) {
                    Label("历史记录", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)

            Divider()

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Button(action: { state.screen = .camera }) {
                        Label("开始拍照识别", systemImage: "camera.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 260, height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])

                    VStack(alignment: .leading, spacing: 12) {
                        metricRow(icon: "checkmark.seal", title: "系统状态", value: "就绪", color: .green)
                        metricRow(icon: "tray.full", title: "已录入记录", value: "\(state.recordCount) 条", color: .blue)
                        engineSelector
                        metricRow(
                            icon: state.hasAPIKey ? "sparkles" : "wand.and.stars.inverse",
                            title: "AI 增强",
                            value: state.hasAPIKey ? "已启用" : "未配置",
                            color: state.hasAPIKey ? .purple : .secondary
                        )
                    }
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("工作流程")
                        .font(.system(size: 15, weight: .semibold))

                    VStack(alignment: .leading, spacing: 14) {
                        workflowRow(step: "1", icon: "camera", title: "采集图像", subtitle: "对准采血管标签后拍照")
                        workflowRow(step: "2", icon: "text.viewfinder", title: "本地 OCR", subtitle: "Vision 识别标签字段")
                        workflowRow(step: "3", icon: "checklist.checked", title: "人工核对", subtitle: "补全子弹头编号后保存入库")
                    }

                    Divider().padding(.vertical, 2)

                    Button(showSettings ? "收起 AI 设置" : "配置 DeepSeek AI") {
                        if showSettings {
                            showSettings = false
                        } else {
                            apiKeyInput = state.apiKey
                            showSettings = true
                            isKeyFieldFocused = true
                        }
                    }
                    .buttonStyle(.link)

                    if showSettings {
                        settingsPanel
                    }
                }
                .frame(maxWidth: 460, alignment: .leading)
            }
            .padding(32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var engineSelector: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text("OCR 引擎")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { state.ocrEngine },
                set: { state.setOCREngine($0) }
            )) {
                ForEach(OCREngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            if state.ocrEngine == .paddleOCR {
                if state.paddleOCR?.isLoading == true {
                    ProgressView().scaleEffect(0.5)
                } else if state.paddleOCR?.isReady == true {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                } else if let err = state.paddleOCR?.loadError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.system(size: 12))
                        .help(err)
                }
            }
        }
        .font(.system(size: 13))
    }

    private func metricRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.system(size: 13))
    }

    private func workflowRow(step: String, icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DeepSeek API Key")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                SecureField("sk-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 300)
                    .focused($isKeyFieldFocused)
                    .onSubmit { saveKey() }

                Button("保存") { saveKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if !state.apiKey.isEmpty {
                    Button("清除") {
                        state.saveAPIKey("")
                        apiKeyInput = ""
                        showSettings = false
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }

            Link("获取 API Key: platform.deepseek.com",
                 destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                .font(.system(size: 11))

            Text("也可使用环境变量 DEEPSEEK_API_KEY。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        state.saveAPIKey(key)
        showSettings = false
    }
}
