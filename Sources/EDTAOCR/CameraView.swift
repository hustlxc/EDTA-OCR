import SwiftUI

struct CameraView: View {
    @Environment(AppState.self) private var state
    @State private var permissionChecked = false
    @State private var overlayMessage = "按空格键或点击下方按钮拍照"
    @State private var showOverlay = true
    @State private var isCapturing = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: { cancel() }) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(.link)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("摄像头拍照")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                // Spacer to balance
                Color.clear.frame(width: 60)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            // Camera preview
            ZStack {
                if state.camera.isAuthorized && permissionChecked {
                    CameraPreview(session: state.camera.session)
                        .onAppear {
                            state.camera.setupCamera()
                            state.camera.startSession()
                            // Auto-dismiss overlay after 2s
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation { showOverlay = false }
                            }
                        }
                        .onDisappear {
                            state.camera.stopSession()
                        }

                    if showOverlay {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 32))
                            Text(overlayMessage)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                    }
                } else if !permissionChecked {
                    ProgressView("正在检查摄像头权限...")
                        .onAppear {
                            Task {
                                let ok = await state.camera.checkPermission()
                                permissionChecked = true
                                if !ok {
                                    state.screen = .home
                                }
                            }
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("摄像头未授权")
                            .font(.system(size: 16))
                        Text("请在 系统设置 > 隐私与安全性 > 摄像头 中允许访问")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            // Bottom bar
            HStack(spacing: 24) {
                Button(action: cancel) {
                    Text("取消")
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: capture) {
                    Label(isCapturing ? "正在处理" : "拍照识别", systemImage: "camera.fill")
                        .frame(width: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isCapturing)
                .keyboardShortcut(.space, modifiers: [])
            }
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        overlayMessage = "正在识别文字..."
        showOverlay = true
        state.camera.capturePhoto { image in
            guard let image = image else {
                overlayMessage = state.camera.captureError ?? "拍照失败，请重试"
                showOverlay = true
                isCapturing = false
                return
            }
            state.capturedImage = image
            // Save to captures/ for reliable re-reading (not /tmp)
            state.capturedImagePath = state.ocr.saveToLatest(image)

            Task {
                // Step 1: Vision OCR (fast, local)
                let results = await state.recognizeOCR(from: image)
                state.ocrResults = results

                // Step 2: Local heuristic extraction (instant, shown immediately)
                state.extractedFields = state.extractor.extract(from: results)
                state.camera.stopSession()

                // Step 3: DeepSeek AI extraction (async, updates fields when ready)
                if state.hasAPIKey {
                    await runDeepSeekExtraction(results: results)
                }

                isCapturing = false
                state.screen = .review
            }
        }
    }

    private func runDeepSeekExtraction(results: [OCRItem]) async {
        state.isExtractingWithAI = true
        state.aiError = nil

        let rawText = results.map(\.text).joined(separator: "\n")
        guard !rawText.isEmpty else {
            state.isExtractingWithAI = false
            return
        }

        do {
            let aiFields = try await state.deepSeek.extract(
                rawText: rawText, apiKey: state.apiKey
            )

            var fields: [String: ExtractedField] = [:]
            let mirror = Mirror(reflecting: aiFields)
            for child in mirror.children {
                guard let label = child.label,
                      let value = child.value as? String,
                      !value.isEmpty else { continue }
                fields[label] = ExtractedField(value: value, confidence: "high", isInferred: false)
            }

            // Merge: AI results take priority for non-empty values
            for (key, field) in fields {
                state.extractedFields[key] = field
            }
            state.aiExtractedFields = fields
        } catch {
            state.aiError = error.localizedDescription
            // Local extraction remains usable
        }

        state.isExtractingWithAI = false
    }

    private func cancel() {
        state.camera.stopSession()
        state.screen = .home
    }
}
