import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var records: [Record] = []

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

            // Records table
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
                    TableColumn("ID") { Text("\($0.id)").font(.system(size: 12)) }
                        .width(40)
                    TableColumn("姓名") { Text($0.name).font(.system(size: 12)) }
                        .width(70)
                    TableColumn("性别") { Text($0.gender).font(.system(size: 12)) }
                        .width(40)
                    TableColumn("年龄") { Text($0.age).font(.system(size: 12)) }
                        .width(40)
                    TableColumn("条形码") { Text($0.barcode).font(.system(size: 11, design: .monospaced)) }
                        .width(120)
                    TableColumn("采血时间") { Text($0.collectionTime).font(.system(size: 11)) }
                        .width(130)
                    TableColumn("科室") { Text($0.department).font(.system(size: 12)) }
                        .width(70)
                    TableColumn("床号") { Text($0.bedNumber).font(.system(size: 12)) }
                        .width(55)
                    TableColumn("录入时间") { Text($0.createdAt).font(.system(size: 11)) }
                        .width(130)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { records = state.db.fetchRecent() }
    }
}
