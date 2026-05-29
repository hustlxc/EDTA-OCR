import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var records: [Record] = []
    @State private var searchText = ""
    @State private var selectedRecordID: Record.ID?
    @State private var selectedRecord: Record?
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteSerial = ""

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
                TextField("搜索姓名、流水号、子弹头编号、科室、床号或 OCR 文本", text: $searchText)
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
                        TableColumn("流水号") {
                            Text($0.serialNumber).font(.system(size: 11, design: .monospaced))
                        }
                        .width(120)
                        TableColumn("子弹头编号") {
                            Text($0.bulletNumber).font(.system(size: 11, design: .monospaced))
                        }
                        .width(92)
                        TableColumn("采血时间") { Text($0.collectionTime).font(.system(size: 11)) }
                            .width(128)
                        TableColumn("科室") { (r: Record) in Text(r.department).font(.system(size: 12)) }
                            .width(76)
                        TableColumn("床号") { (r: Record) in Text(r.bedNumber).font(.system(size: 12)) }
                            .width(56)
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
        .sheet(isPresented: $showEditSheet) { editSheet }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                _ = state.db.deleteRecord(serial: pendingDeleteSerial)
                state.ocr.deleteImage(serialNumber: pendingDeleteSerial)
                refreshRecords()
            }
        } message: {
            Text("流水号 \(pendingDeleteSerial) 的记录和图片将被永久删除，不可恢复。")
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
            let ok = state.db.exportCSV(to: url.path)
            if !ok {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = "CSV 写入失败，请检查磁盘空间和权限。"
                alert.runModal()
            }
        }
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
        if let path = state.ocr.capturedImagePath(serialNumber: record.serialNumber),
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 170)
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
            .frame(height: 150)
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
        selectedRecord = record
        editName = record.name
        editGender = (record.gender == "女") ? "女" : "男"
        editAge = record.age
        editSerial = record.serialNumber
        editBullet = record.bulletNumber
        editTime = record.collectionTime
        editDept = record.department
        editBed = record.bedNumber
        showEditSheet = true
    }

    private func saveEdit() {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let serial = editSerial.trimmingCharacters(in: .whitespaces)
        guard !serial.isEmpty else { return }
        let bullet = editBullet.trimmingCharacters(in: .whitespaces)
        guard !bullet.isEmpty else { return }
        // If serial number changed, delete the old record first to avoid duplicates
        if let oldSerial = selectedRecord?.serialNumber, oldSerial != serial {
            _ = state.db.deleteRecord(serial: oldSerial)
        }
        _ = state.db.upsert(
            name: name, gender: editGender, age: editAge,
            serialNumber: serial,
            bulletNumber: bullet,
            collectionTime: editTime, department: editDept,
            bedNumber: editBed,
            rawOCRText: selectedRecord?.rawOCRText ?? ""
        )
        refreshRecords()
        selectedRecordID = records.first(where: { $0.serialNumber == serial })?.id
        showEditSheet = false
    }

    // MARK: - Delete

    private func confirmDelete(_ record: Record) {
        pendingDeleteSerial = record.serialNumber
        showDeleteConfirm = true
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
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
                    editRow("流水号:", $editSerial)
                    editRow("子弹头编号:", $editBullet)
                    editRow("采血时间:", $editTime)
                    editRow("科室:", $editDept)
                    editRow("床号:", $editBed)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("取消") {
                    showEditSheet = false
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
        .frame(width: 420, height: 440)
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
