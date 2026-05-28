import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var records: [Record] = []
    @State private var selectedRecord: Record?
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteSerial = ""

    // Edit form values
    @State private var editName = ""
    @State private var editGender = "男"
    @State private var editAge = ""
    @State private var editSerial = ""
    @State private var editTime = ""
    @State private var editDept = ""
    @State private var editBed = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
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

                Text("共 \(records.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("暂无记录")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(records) {
                    TableColumn("姓名") { Text($0.name).font(.system(size: 12)) }
                        .width(64)
                    TableColumn("性别/年龄") {
                        Text("\($0.gender)/\($0.age)")
                            .font(.system(size: 12))
                    }
                    .width(72)
                    TableColumn("流水号") {
                        Text($0.serialNumber).font(.system(size: 11, design: .monospaced))
                    }
                    .width(110)
                    TableColumn("采血时间") { Text($0.collectionTime).font(.system(size: 11)) }
                        .width(120)
                    TableColumn("科室") { (r: Record) in Text(r.department).font(.system(size: 12)) }
                        .width(60)
                    TableColumn("床号") { (r: Record) in Text(r.bedNumber).font(.system(size: 12)) }
                        .width(50)
                    TableColumn("录入时间") { Text($0.savedAt).font(.system(size: 11)) }
                        .width(120)
                    TableColumn("原始OCR文本") {
                        Text($0.rawOCRText.replacingOccurrences(of: "\n", with: " | "))
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .width(160)
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
                    .width(50)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { records = state.db.fetchRecent() }
        .sheet(isPresented: $showEditSheet) { editSheet }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                _ = state.db.deleteRecord(serial: pendingDeleteSerial)
                state.ocr.deleteImage(serialNumber: pendingDeleteSerial)
                records = state.db.fetchRecent()
            }
        } message: {
            Text("流水号 \(pendingDeleteSerial) 的记录和图片将被永久删除，不可恢复。")
        }
    }

    // MARK: - Edit

    private func openEdit(_ record: Record) {
        selectedRecord = record
        editName = record.name
        editGender = (record.gender == "女") ? "女" : "男"
        editAge = record.age
        editSerial = record.serialNumber
        editTime = record.collectionTime
        editDept = record.department
        editBed = record.bedNumber
        showEditSheet = true
    }

    private func saveEdit() {
        let name = editName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let serial = editSerial.trimmingCharacters(in: .whitespaces)
        _ = state.db.upsert(
            name: name, gender: editGender, age: editAge,
            serialNumber: serial,
            collectionTime: editTime, department: editDept,
            bedNumber: editBed,
            rawOCRText: selectedRecord?.rawOCRText ?? ""
        )
        records = state.db.fetchRecent()
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
                .frame(width: 64, alignment: .trailing)
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
                .frame(width: 64, alignment: .trailing)
            Picker("", selection: value) {
                Text("男").tag("男")
                Text("女").tag("女")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }
}
