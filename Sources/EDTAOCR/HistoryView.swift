import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var records: [Record] = []
    @State private var searchText = ""
    @State private var selectedRecordID: Record.ID?
    @State private var editingRecord: Record?
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteBullet = ""
    @State private var isAIExtracting = false
    @State private var aiEditError: String?

    // Edit form values
    @State private var editName = ""
    @State private var editGender = "男"
    @State private var editAge = ""
    @State private var editSerial = ""
    @State private var editBullet = ""
    @State private var editTime = ""
    @State private var editDept = ""
    @State private var editBed = ""

    private var canSaveEdit: Bool {
        !editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !editSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !editBullet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { state.screen = .home }) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(.link)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("历史记录")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Button(action: refreshRecords) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")

                Button(action: exportCSV) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("导出 CSV")
                .disabled(records.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索姓名、住院号、子弹头编号、科室、床号或 OCR 文本", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Text("共 \(records.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "暂无记录" : "没有匹配记录")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    Table(records, selection: $selectedRecordID) {
                        TableColumn("姓名") { Text($0.name).font(.system(size: 12)) }
                            .width(70)
                        TableColumn("性别") { Text($0.gender).font(.system(size: 12)) }
                            .width(40)
                        TableColumn("年龄") { Text($0.age).font(.system(size: 12)) }
                            .width(44)
                        TableColumn("住院号") {
                            Text($0.serialNumber).font(.system(size: 11, design: .monospaced))
                        }
                        .width(120)
                        TableColumn("子弹头编号") {
                            Text($0.bulletNumber).font(.system(size: 11, design: .monospaced))
                        }
                        .width(92)
                        TableColumn("采血时间") { Text($0.collectionTime).font(.system(size: 11)) }
                            .width(128)
                        TableColumn("科室/床号") { r in
                            Text("\(r.department)/\(r.bedNumber)").font(.system(size: 12))
                        }
                        .width(100)
                        TableColumn("盒·孔") { r in
                            if let pos = boxPosition(for: r) {
                                Text("\(pos.box)-\(pos.hole)").font(.system(size: 11, design: .monospaced))
                            } else { Text("-").foregroundStyle(.secondary) }
                        }
                        .width(60)
                        TableColumn("录入时间") { Text($0.savedAt).font(.system(size: 11)) }
                            .width(128)
                        TableColumn("操作") { row in
                            HStack(spacing: 6) {
                                Button(action: { openEdit(row) }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .help("编辑")

                                Button(action: { confirmDelete(row) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("删除")
                            }
                        }
                        .width(58)
                    }
                    .tableStyle(.bordered(alternatesRowBackgrounds: true))
                    .padding(8)

                    Divider()

                    recordDetail
                        .frame(width: 300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshRecords() }
        .onChange(of: searchText) { _, _ in refreshRecords() }
        .sheet(item: $editingRecord) { record in editSheet(for: record) }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                _ = state.db.deleteRecord(bullet: pendingDeleteBullet)
                state.ocr.deleteImage(bulletNumber: pendingDeleteBullet)
                refreshRecords()
            }
        } message: {
            Text("子弹头编号 \(pendingDeleteBullet) 的记录和图片将被永久删除，不可恢复。")
        }
    }

    private var currentRecord: Record? {
        if let selectedRecordID,
           let selected = records.first(where: { $0.id == selectedRecordID }) {
            return selected
        }
        return records.first
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "导出 CSV"
        panel.nameFieldStringValue = "EDTA_OCR_\(ISO8601DateFormatter().string(from: Date()).prefix(10)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let ok = state.db.exportCSV(to: url.path,
                minBullet: state.minBulletNumber,
                firstBox: state.firstBoxNumber,
                firstHole: state.firstHolePosition)
            if !ok {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = "CSV 写入失败，请检查磁盘空间和权限。"
                alert.runModal()
            }
        }
    }

    private func boxPosition(for record: Record) -> (box: Int, hole: Int)? {
        guard let minBullet = state.minBulletNumber,
              state.firstBoxNumber > 0,
              state.firstHolePosition >= 1,
              state.firstHolePosition <= 81,
              let bulletNum = BoxPositionCalculator.parseBulletNumber(record.bulletNumber) else {
            return nil
        }
        return BoxPositionCalculator.calculate(
            bulletNumber: bulletNum,
            minBullet: minBullet,
            firstBox: state.firstBoxNumber,
            firstHole: state.firstHolePosition
        )
    }

    private func refreshRecords() {
        records = state.db.search(searchText)
        if let selectedRecordID,
           records.contains(where: { $0.id == selectedRecordID }) {
            return
        }
        selectedRecordID = records.first?.id
    }

    @ViewBuilder
    private var recordDetail: some View {
        if let record = currentRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.name.isEmpty ? "未命名记录" : record.name)
                                .font(.system(size: 17, weight: .semibold))
                            Text(record.serialNumber)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("子弹头编号: \(record.bulletNumber.isEmpty ? "未填写" : record.bulletNumber)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: { openEdit(record) }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("编辑")
                    }

                    capturedImage(for: record)

                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("性别", record.gender)
                        detailRow("年龄", record.age)
                        detailRow("子弹头编号", record.bulletNumber)
                        detailRow("采血时间", record.collectionTime)
                        detailRow("科室", record.department)
                        detailRow("床号", record.bedNumber)
                        detailRow("录入时间", record.savedAt)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("原始 OCR 文本")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(record.rawOCRText.isEmpty ? "无" : record.rawOCRText)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Button(role: .destructive, action: { confirmDelete(record) }) {
                        Label("删除记录和图片", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(14)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("选择一条记录查看详情")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func capturedImage(for record: Record) -> some View {
        if let path = state.ocr.capturedImagePath(bulletNumber: record.bulletNumber),
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 255)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("未找到采集图片")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 225)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value.isEmpty ? "未填写" : value)
                .font(.system(size: 12, weight: value.isEmpty ? .regular : .medium))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Edit

    private func openEdit(_ record: Record) {
        editingRecord = record
    }

    private func saveEdit() {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let serial = editSerial.trimmingCharacters(in: .whitespaces)
        guard !serial.isEmpty else { return }
        let bullet = editBullet.trimmingCharacters(in: .whitespaces)
        guard !bullet.isEmpty else { return }
        // If bullet number changed, delete the old record first to avoid duplicates
        guard let record = editingRecord else { return }
        if let oldBullet = editingRecord?.bulletNumber, oldBullet != bullet {
            _ = state.db.deleteRecord(bullet: oldBullet)
        }
        _ = state.db.upsert(
            name: name, gender: editGender, age: editAge,
            serialNumber: serial,
            bulletNumber: bullet,
            collectionTime: editTime, department: editDept,
            bedNumber: editBed,
            rawOCRText: record.rawOCRText
        )
        refreshRecords()
        selectedRecordID = records.first(where: { $0.bulletNumber == bullet })?.id
        editingRecord = nil
    }

    private func runAIExtraction() async {
        guard let record = editingRecord else { return }
        guard let imagePath = state.ocr.capturedImagePath(bulletNumber: record.bulletNumber) else {
            aiEditError = "未找到截图文件"
            return
        }
        isAIExtracting = true
        aiEditError = nil

        do {
            let aiFields = try await state.qwenVL.extract(
                fromImagePath: imagePath, apiKey: state.qwenAPIKey, model: state.qwenModel
            )
            let mirror = Mirror(reflecting: aiFields)
            for child in mirror.children {
                guard let label = child.label, let value = child.value as? String, !value.isEmpty else { continue }
                switch label {
                case "姓名":     editName = value
                case "性别":     editGender = (value == "女") ? "女" : "男"
                case "年龄":     editAge = value
                case "住院号":   editSerial = value
                case "采血时间": editTime = value
                case "科室":     editDept = value
                case "床号":     editBed = value
                default: break
                }
            }
        } catch {
            aiEditError = error.localizedDescription
        }
        isAIExtracting = false
    }

    // MARK: - Delete

    private func confirmDelete(_ record: Record) {
        pendingDeleteBullet = record.bulletNumber
        showDeleteConfirm = true
    }

    // MARK: - Edit Sheet

    private func editSheet(for record: Record) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("编辑记录")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editRow("姓名:", $editName)
                    editRowGender("性别:", $editGender)
                    editRow("年龄:", $editAge)
                    editRow("住院号:", $editSerial)
                    editRow("子弹头编号:", $editBullet)
                    editRow("采血时间:", $editTime)
                    editRow("科室:", $editDept)
                    editRow("床号:", $editBed)
                }
                .padding(20)
            }

            // AI re-extraction from captured image
            if state.hasQwenAPIKey && state.ocr.imageExistsInCaptures(bulletNumber: record.bulletNumber) {
                VStack(spacing: 6) {
                    if isAIExtracting {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("AI 识别中...").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    } else if let err = aiEditError {
                        Text(err).font(.system(size: 11)).foregroundStyle(.red)
                    }
                    Button(action: { Task { await runAIExtraction() } }) {
                        Label("AI 识别（从截图）", systemImage: "sparkles")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAIExtracting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button("取消") {
                    editingRecord = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(width: 100)

                Button("保存修改") {
                    saveEdit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 120)
                .disabled(!canSaveEdit)
            }
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 528)
    }

    @ViewBuilder
    private func editRow(_ label: String, _ value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 82, alignment: .trailing)
            TextField("", text: value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .frame(maxWidth: 240)
        }
    }

    @ViewBuilder
    private func editRowGender(_ label: String, _ value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 82, alignment: .trailing)
            Picker("", selection: value) {
                Text("男").tag("男")
                Text("女").tag("女")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }
}
