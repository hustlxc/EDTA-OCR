import SwiftUI

struct ReviewView: View {
    @Environment(AppState.self) private var state
    @State private var showSaveSuccess = false

    // Editable field values
    @State private var fieldValues: [String: String] = [:]

    private let fieldOrder = ["姓名", "性别", "年龄", "流水号", "采血时间", "科室", "床号"]
    private let fieldLabels: [String: String] = [
        "姓名": "姓名", "性别": "性别", "年龄": "年龄",
        "流水号": "流水号", "采血时间": "采血时间",
        "科室": "科室", "床号": "床号"
    ]
    private let genderOptions = ["男", "女"]

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: { state.reset(); state.screen = .camera }) {
                    Label("重新拍照", systemImage: "arrow.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(.link)

                Spacer()

                Text("审核识别结果")
                    .font(.system(size: 15, weight: .semibold))

                if state.isExtractingWithAI {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("AI 识别中...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if state.aiError != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(state.aiError ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    .help(state.aiError ?? "")
                } else if state.aiExtractedFields != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                        Text("AI 已识别")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                    }
                }

                Spacer()

                // OCR retry button
                if !state.isExtractingWithAI && state.capturedImagePath != nil {
                    Button(action: { Task { @MainActor in await retryOCR() } }) {
                        Label("OCR 识别", systemImage: "text.viewfinder")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("用 Vision OCR 重新识别图像")
                }

                // AI retry button
                if state.hasAPIKey && !state.isExtractingWithAI && !state.ocrResults.isEmpty {
                    Button(action: { Task { await retryAI() } }) {
                        Label("AI 识别", systemImage: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.borderless)
                    .help("用 DeepSeek AI 重新识别")
                }

                Color.clear.frame(width: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            // Main content
            HStack(spacing: 0) {
                // Left: Captured image
                VStack {
                    if let image = state.capturedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 440, maxHeight: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(maxWidth: 440, maxHeight: 520)
                            .overlay(Text("无图片").foregroundStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)

                // Right: Editable form
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(fieldOrder, id: \.self) { field in
                            FieldRow(
                                label: fieldLabels[field] ?? field,
                                value: Binding(
                                    get: { fieldValues[field] ?? state.extractedFields[field]?.value ?? "" },
                                    set: { fieldValues[field] = $0 }
                                ),
                                confidence: state.extractedFields[field]?.confidence ?? "low",
                                isInferred: state.extractedFields[field]?.isInferred ?? false,
                                isAIExtracted: state.aiExtractedFields?[field] != nil,
                                isGender: field == "性别"
                            )
                        }

                        Divider().padding(.vertical, 8)

                        // Raw OCR text
                        VStack(alignment: .leading, spacing: 4) {
                            Text("原始 OCR 文本:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ScrollView {
                                Text(state.ocrResults.map(\.text).joined(separator: "\n"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                }
                .frame(width: 420)
                .background(Color(nsColor: .windowBackgroundColor))
            }

            // Bottom buttons
            HStack {
                Button(action: { state.screen = .camera }) {
                    Text("重新拍照")
                        .frame(width: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button(action: saveRecord) {
                    Label("确认保存", systemImage: "square.and.arrow.down.fill")
                        .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncFieldValues() }
        .sheet(isPresented: $showSaveSuccess) {
            saveSuccessSheet
        }
    }

    private func syncFieldValues() {
        for field in fieldOrder {
            if fieldValues[field] == nil {
                fieldValues[field] = state.extractedFields[field]?.value ?? ""
            }
        }
    }

    private func retryOCR() async {
        guard let imagePath = state.capturedImagePath else { return }
        let results = await state.ocr.recognize(fromPath: imagePath)
        state.ocrResults = results
        let fields = state.extractor.extract(from: results)
        state.extractedFields = fields
        for (key, field) in fields {
            fieldValues[key] = field.value
        }
    }

    private func retryAI() async {
        state.isExtractingWithAI = true
        state.aiError = nil

        let rawText = state.ocrResults.map(\.text).joined(separator: "\n")
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

            for (key, field) in fields {
                state.extractedFields[key] = field
                fieldValues[key] = field.value
            }
            state.aiExtractedFields = fields
        } catch {
            state.aiError = error.localizedDescription
        }

        state.isExtractingWithAI = false
    }

    private func saveRecord() {
        let name = fieldValues["姓名"]?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "验证提示"
            alert.informativeText = "姓名不能为空，请填写后再保存。"
            alert.runModal()
            return
        }

        let gender = fieldValues["性别"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let age = fieldValues["年龄"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let serial = fieldValues["流水号"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let time = fieldValues["采血时间"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let dept = fieldValues["科室"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let bed = fieldValues["床号"]?.trimmingCharacters(in: .whitespaces) ?? ""

        // Check for existing record (image + DB)
        let imageExists = !serial.isEmpty && state.ocr.imageExistsInCaptures(serialNumber: serial)
        let recordExists = state.db.serialExists(serial)

        if imageExists || recordExists {
            let alert = NSAlert()
            alert.messageText = "数据已存在"
            alert.informativeText = "流水号 \(serial) 的记录已存在。\n\n是否覆盖原有的图像和数据？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                return
            }
        }

        // Copy image to captures/
        if !serial.isEmpty, let tempPath = state.capturedImagePath {
            _ = state.ocr.saveToCaptures(sourceTempPath: tempPath, serialNumber: serial)
        }

        let rawText = state.ocrResults.map(\.text).joined(separator: "\n")

        let ok = state.db.upsert(
            name: name, gender: gender, age: age, serialNumber: serial,
            collectionTime: time, department: dept, bedNumber: bed,
            rawOCRText: rawText
        )

        if ok {
            state.lastSavedRecord = Record(
                id: 0, name: name, gender: gender, age: age,
                serialNumber: serial, collectionTime: time,
                department: dept, bedNumber: bed,
                rawOCRText: rawText, savedAt: ""
            )
            showSaveSuccess = true
        } else {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = "数据库写入失败，请重试。"
            alert.runModal()
        }
    }

    private var saveSuccessSheet: some View {
        VStack(spacing: 0) {
            // Title bar for dragging
            HStack {
                Spacer()
                Text("保存成功")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                    .padding(.top, 28)

                Text("记录已保存")
                    .font(.system(size: 18, weight: .bold))

                VStack(alignment: .leading, spacing: 6) {
                    infoRow("姓名:", fieldValues["姓名"] ?? "")
                    infoRow("性别:", fieldValues["性别"] ?? "")
                    infoRow("年龄:", fieldValues["年龄"] ?? "")
                    infoRow("流水号:", fieldValues["流水号"] ?? "")
                    infoRow("科室:", fieldValues["科室"] ?? "")
                    infoRow("床号:", fieldValues["床号"] ?? "")
                    infoRow("采血时间:", fieldValues["采血时间"] ?? "")
                }
                .font(.system(size: 13))
                .padding(.horizontal, 32)

                HStack(spacing: 16) {
                    Button("继续录入") {
                        showSaveSuccess = false
                        state.reset()
                        state.screen = .home
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(width: 120)

                    Button("查看历史") {
                        showSaveSuccess = false
                        state.screen = .history
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(width: 120)
                }
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 400, height: 440)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Field Row

struct FieldRow: View {
    let label: String
    @Binding var value: String
    let confidence: String
    let isInferred: Bool
    let isAIExtracted: Bool
    let isGender: Bool

    private let genderOptions = ["男", "女"]

    var body: some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 64, alignment: .trailing)

            if isGender {
                Picker("", selection: $value) {
                    Text("男").tag("男")
                    Text("女").tag("女")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            } else {
                TextField("", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .frame(maxWidth: 220)
            }

            confidenceIcon
                .frame(width: 50)
        }
    }

    @ViewBuilder
    private var confidenceIcon: some View {
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("未识别")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        } else if isAIExtracted {
            Text("AI")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.purple))
        } else if isInferred {
            Text("推测")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().stroke(.orange, lineWidth: 1))
        } else {
            Circle()
                .fill(confidenceColor)
                .frame(width: 10, height: 10)
        }
    }

    private var confidenceColor: Color {
        switch confidence {
        case "high":   return .green
        case "medium": return .orange
        default:       return .red
        }
    }
}
