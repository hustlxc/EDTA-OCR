import SwiftUI

struct ReviewView: View {
    @Environment(AppState.self) private var state
    @State private var showSaveSuccess = false
    @State private var name = ""
    @State private var gender = "男"
    @State private var age = ""
    @State private var serialNumber = ""
    @State private var bulletNumber = ""
    @State private var collectionTime = ""
    @State private var department = ""
    @State private var bedNumber = ""
    @State private var didLoadFields = false

    private let fieldOrder = ["姓名", "性别", "年龄", "流水号", "子弹头编号", "采血时间", "科室", "床号"]
    private let requiredFields = ["姓名", "流水号", "子弹头编号"]
    private var recognizedFieldCount: Int {
        fieldOrder.filter {
            !value(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var missingRequiredFields: [String] {
        requiredFields.filter {
            value(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var canSave: Bool { missingRequiredFields.isEmpty }

    private var ocrButtonTitle: String {
        state.capturedImagePath == nil ? "无截图路径" : "OCR 识别"
    }

    private var ocrButtonHelp: String {
        state.capturedImagePath == nil
            ? "没有可重新识别的截图路径，请重新拍照"
            : "重新从当前截图执行 OCR"
    }

    private var aiButtonTitle: String {
        if state.isExtractingWithAI { return "AI 识别中" }
        if state.ocrResults.isEmpty { return "无 OCR 文本" }
        return state.hasQwenAPIKey ? "AI 识别" : "AI 未配置"
    }

    private var aiButtonHelp: String {
        if state.isExtractingWithAI { return "正在调用 AI 识别" }
        if state.ocrResults.isEmpty { return "请先完成 OCR 识别" }
        if !state.hasQwenAPIKey { return "请先在首页配置 Qwen VL API Key" }
        return "重新调用 AI 识别并覆盖非空字段"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thin status strip
            HStack(spacing: 8) {
                if state.isExtractingWithAI {
                    ProgressView().scaleEffect(0.6)
                    Text("AI 识别中...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let err = state.aiError {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                    Text(err).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
                } else if state.aiExtractedFields != nil {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
                    Text("AI 已识别").font(.system(size: 11)).foregroundStyle(.purple)
                }
                Spacer()
                Label("\(recognizedFieldCount)/\(fieldOrder.count) 个字段已填充", systemImage: "list.bullet.clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main: image left, form right
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Left: Captured image
                    VStack {
                        if let image = state.capturedImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(Text("无图片").foregroundStyle(.secondary))
                        }
                    }
                    .frame(width: geo.size.width * 0.56)
                    .padding(12)

                    Divider()

                    // Right: Editable form
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("核对字段")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("姓名和流水号为必填项，保存前请核对。")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(recognizedFieldCount)/\(fieldOrder.count)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            FieldRow(
                                label: "姓名",
                                value: $name,
                                confidence: confidence(for: "姓名"),
                                isInferred: isInferred("姓名"),
                                isAIExtracted: isAIExtracted("姓名"),
                                isRequired: true,
                                isGender: false
                            )

                            FieldRow(
                                label: "性别",
                                value: $gender,
                                confidence: confidence(for: "性别"),
                                isInferred: isInferred("性别"),
                                isAIExtracted: isAIExtracted("性别"),
                                isRequired: false,
                                isGender: true
                            )

                            FieldRow(
                                label: "年龄",
                                value: $age,
                                confidence: confidence(for: "年龄"),
                                isInferred: isInferred("年龄"),
                                isAIExtracted: isAIExtracted("年龄"),
                                isRequired: false,
                                isGender: false
                            )

                            FieldRow(
                                label: "流水号",
                                value: $serialNumber,
                                confidence: confidence(for: "流水号"),
                                isInferred: isInferred("流水号"),
                                isAIExtracted: isAIExtracted("流水号"),
                                isRequired: true,
                                isGender: false
                            )

                            FieldRow(
                                label: "子弹头编号",
                                value: $bulletNumber,
                                confidence: "high",
                                isInferred: false,
                                isAIExtracted: false,
                                isRequired: true,
                                isGender: false
                            )

                            FieldRow(
                                label: "采血时间",
                                value: $collectionTime,
                                confidence: confidence(for: "采血时间"),
                                isInferred: isInferred("采血时间"),
                                isAIExtracted: isAIExtracted("采血时间"),
                                isRequired: false,
                                isGender: false
                            )

                            FieldRow(
                                label: "科室",
                                value: $department,
                                confidence: confidence(for: "科室"),
                                isInferred: isInferred("科室"),
                                isAIExtracted: isAIExtracted("科室"),
                                isRequired: false,
                                isGender: false
                            )

                            FieldRow(
                                label: "床号",
                                value: $bedNumber,
                                confidence: confidence(for: "床号"),
                                isInferred: isInferred("床号"),
                                isAIExtracted: isAIExtracted("床号"),
                                isRequired: false,
                                isGender: false
                            )

                            Divider().padding(.vertical, 8)

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
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(16)
                    }
                    .frame(width: geo.size.width * 0.44)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }

            Divider()

            // Bottom bar: all actions
            HStack(spacing: 16) {
                Button(action: { state.reset(); state.screen = .camera }) {
                    Label("重新拍照", systemImage: "camera.fill")
                        .frame(width: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: handleOCRButton) {
                    Label(ocrButtonTitle, systemImage: "text.viewfinder")
                        .frame(width: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help(ocrButtonHelp)

                Button(action: handleAIButton) {
                    Label(aiButtonTitle, systemImage: "sparkles")
                        .frame(width: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(state.isExtractingWithAI || state.ocrResults.isEmpty)
                .help(aiButtonHelp)

                if !canSave {
                    Label("请补全: \(missingRequiredFields.joined(separator: "、"))", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button(action: saveRecord) {
                    Label("确认保存", systemImage: "square.and.arrow.down.fill")
                        .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onKeyPress(.return) {
            if canSave { saveRecord(); return .handled }
            return .ignored
        }
        .onAppear {
            if !didLoadFields {
                syncFieldValues()
                didLoadFields = true
            }
        }
        .sheet(isPresented: $showSaveSuccess) { saveSuccessSheet }
    }

    private func syncFieldValues() {
        name = state.extractedFields["姓名"]?.value ?? ""
        let extractedGender = state.extractedFields["性别"]?.value ?? ""
        gender = extractedGender == "女" ? "女" : "男"
        age = state.extractedFields["年龄"]?.value ?? ""
        serialNumber = state.extractedFields["流水号"]?.value ?? ""
        bulletNumber = state.db.nextBulletNumber()
        collectionTime = state.extractedFields["采血时间"]?.value ?? ""
        department = state.extractedFields["科室"]?.value ?? ""
        bedNumber = state.extractedFields["床号"]?.value ?? ""
    }

    private func value(for field: String) -> String {
        switch field {
        case "姓名": return name
        case "性别": return gender
        case "年龄": return age
        case "流水号": return serialNumber
        case "子弹头编号": return bulletNumber
        case "采血时间": return collectionTime
        case "科室": return department
        case "床号": return bedNumber
        default: return ""
        }
    }

    private func confidence(for field: String) -> String {
        state.extractedFields[field]?.confidence ?? "low"
    }

    private func isInferred(_ field: String) -> Bool {
        state.extractedFields[field]?.isInferred ?? false
    }

    private func isAIExtracted(_ field: String) -> Bool {
        state.aiExtractedFields?[field] != nil
    }

    private func applyExtractedFieldsToForm(_ fields: [String: ExtractedField]) {
        name = fields["姓名"]?.value ?? ""
        if let extractedGender = fields["性别"]?.value, !extractedGender.isEmpty {
            gender = extractedGender == "女" ? "女" : "男"
        }
        age = fields["年龄"]?.value ?? ""
        serialNumber = fields["流水号"]?.value ?? ""
        collectionTime = fields["采血时间"]?.value ?? ""
        department = fields["科室"]?.value ?? ""
        bedNumber = fields["床号"]?.value ?? ""
    }

    private func applyAIFieldsToForm(_ fields: [String: ExtractedField]) {
        if let value = fields["姓名"]?.value { name = value }
        if let value = fields["性别"]?.value, !value.isEmpty { gender = value == "女" ? "女" : "男" }
        if let value = fields["年龄"]?.value { age = value }
        if let value = fields["流水号"]?.value { serialNumber = value }
        if let value = fields["采血时间"]?.value { collectionTime = value }
        if let value = fields["科室"]?.value { department = value }
        if let value = fields["床号"]?.value { bedNumber = value }
    }

    private func handleAIButton() {
        guard state.capturedImagePath != nil else { return }
        guard state.hasQwenAPIKey else {
            let alert = NSAlert()
            alert.messageText = "AI 未配置"
            alert.informativeText = "请回到首页配置 Qwen VL API Key，或通过 QWEN_API_KEY 环境变量启动。"
            alert.addButton(withTitle: "去配置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn { state.screen = .home }
            return
        }
        Task { await retryAI() }
    }

    private func handleOCRButton() {
        guard state.capturedImagePath != nil else {
            let alert = NSAlert()
            alert.messageText = "没有截图路径"
            alert.informativeText = "当前没有可重新识别的截图文件。请返回摄像头重新拍照。"
            alert.addButton(withTitle: "重新拍照")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                state.reset()
                state.screen = .camera
            }
            return
        }
        Task { @MainActor in await retryOCR() }
    }

    private func retryOCR() async {
        guard let imagePath = state.capturedImagePath else { return }
        state.ocrResults = []
        let results = await Task.detached(priority: .userInitiated) {
            await state.recognizeOCR(fromPath: imagePath)
        }.value
        state.ocrResults = results
        let fields = state.extractor.extract(from: results)
        state.extractedFields = fields
        applyExtractedFieldsToForm(fields)
    }

    private func retryAI() async {
        guard let imagePath = state.capturedImagePath else { return }
        state.isExtractingWithAI = true
        state.aiError = nil

        do {
            let aiFields = try await state.qwenVL.extract(fromImagePath: imagePath, apiKey: state.qwenAPIKey, model: state.qwenModel)
            var fields: [String: ExtractedField] = [:]
            let mirror = Mirror(reflecting: aiFields)
            for child in mirror.children {
                guard let label = child.label, let value = child.value as? String, !value.isEmpty else { continue }
                fields[label] = ExtractedField(value: value, confidence: "high", isInferred: false)
            }
            for (key, field) in fields {
                state.extractedFields[key] = field
            }
            applyAIFieldsToForm(fields)
            state.aiExtractedFields = fields
        } catch {
            state.aiError = error.localizedDescription
        }
        state.isExtractingWithAI = false
    }

    private func saveRecord() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let serial = serialNumber.trimmingCharacters(in: .whitespaces)
        let bullet = bulletNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !serial.isEmpty, !bullet.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "验证提示"
            alert.informativeText = "姓名、流水号和子弹头编号不能为空，请填写后再保存。"
            alert.runModal()
            return
        }

        let trimmedGender = gender.trimmingCharacters(in: .whitespaces)
        let trimmedAge = age.trimmingCharacters(in: .whitespaces)
        let time = collectionTime.trimmingCharacters(in: .whitespaces)
        let dept = department.trimmingCharacters(in: .whitespaces)
        let bed = bedNumber.trimmingCharacters(in: .whitespaces)

        let imageExists = !serial.isEmpty && state.ocr.imageExistsInCaptures(serialNumber: serial)
        let recordExists = state.db.serialExists(serial)
        if imageExists || recordExists {
            let alert = NSAlert()
            alert.messageText = "数据已存在"
            alert.informativeText = "流水号 \(serial) 的记录已存在。\n\n是否覆盖原有的图像和数据？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        if !serial.isEmpty, let tempPath = state.capturedImagePath {
            _ = state.ocr.saveToCaptures(sourceTempPath: tempPath, serialNumber: serial)
        }

        let rawText = state.ocrResults.map(\.text).joined(separator: "\n")
        let ok = state.db.upsert(
            name: trimmedName, gender: trimmedGender, age: trimmedAge, serialNumber: serial,
            bulletNumber: bullet,
            collectionTime: time, department: dept, bedNumber: bed,
            rawOCRText: rawText
        )

        if ok {
            state.lastSavedRecord = Record(
                id: 0, name: trimmedName, gender: trimmedGender, age: trimmedAge,
                serialNumber: serial, bulletNumber: bullet, collectionTime: time,
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
            HStack {
                Spacer()
                Text("保存成功").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundColor(.green).padding(.top, 28)
                Text("记录已保存").font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 6) {
                    infoRow("姓名:", name)
                    infoRow("性别:", gender)
                    infoRow("年龄:", age)
                    infoRow("流水号:", serialNumber)
                    infoRow("子弹头编号:", bulletNumber)
                    infoRow("科室:", department)
                    infoRow("床号:", bedNumber)
                    infoRow("采血时间:", collectionTime)
                }
                .font(.system(size: 13)).padding(.horizontal, 32)
                HStack(spacing: 16) {
                    Button("继续录入") { showSaveSuccess = false; state.reset(); state.screen = .camera }
                        .buttonStyle(.borderedProminent).controlSize(.large).frame(width: 120)
                        .keyboardShortcut(.return, modifiers: [])
                    Button("查看历史") { showSaveSuccess = false; state.screen = .history }
                        .buttonStyle(.bordered).controlSize(.large).frame(width: 120)
                }
                .padding(.top, 8).padding(.bottom, 28)
            }
        }
        .frame(width: 400, height: 440)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 86, alignment: .trailing)
            Text(value).fontWeight(.medium)
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
    let isRequired: Bool
    let isGender: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Text(label)
                if isRequired {
                    Text("*").foregroundStyle(.red)
                }
                Text(":")
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 86, alignment: .trailing)

            if isGender {
                Picker("", selection: $value) {
                    Text("男").tag("男")
                    Text("女").tag("女")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            } else {
                EditableTextField(text: $value)
                    .frame(maxWidth: 220)
                    .frame(height: 28)
            }
            confidenceIcon.frame(width: 58, alignment: .leading)

            Button(action: openEditDialog) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("编辑\(label)")
        }
    }

    private func openEditDialog() {
        let alert = NSAlert()
        alert.messageText = "编辑\(label)"
        alert.informativeText = isGender ? "请输入“男”或“女”。" : "修改后点击确定。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        input.stringValue = value
        input.isEditable = true
        input.isSelectable = true
        input.isEnabled = true
        input.usesSingleLineMode = true
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            let newValue = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if isGender {
                value = newValue == "女" ? "女" : "男"
            } else {
                value = newValue
            }
        }
    }

    @ViewBuilder
    private var confidenceIcon: some View {
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("未识别").font(.system(size: 11)).foregroundStyle(.red)
        } else if isAIExtracted {
            Text("AI").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.purple))
        } else if isInferred {
            Text("推测").font(.system(size: 10)).foregroundStyle(.orange)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Capsule().stroke(.orange, lineWidth: 1))
        } else {
            HStack(spacing: 4) {
                Circle().fill(confidenceColor).frame(width: 8, height: 8)
                Text(confidenceText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var confidenceText: String {
        switch confidence {
        case "high": return "高"
        case "medium": return "中"
        default: return "低"
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

// MARK: - AppKit Editable Text Field

struct EditableTextField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.font = .systemFont(ofSize: 14)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.focusRingType = .default
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.isEditable = true
        nsView.isSelectable = true
        nsView.isEnabled = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }
    }
}
