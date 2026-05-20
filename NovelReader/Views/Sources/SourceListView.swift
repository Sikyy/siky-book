import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SourceListView: View {
    @Query(sort: \BookSource.name) private var sources: [BookSource]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingImport = false
    @State private var showingURLInput = false
    @State private var sourceURL = ""
    @State private var isLoadingURL = false
    @State private var importCount: Int?
    @State private var importError: String?
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    emptyState
                } else {
                    ForEach(sources) { source in
                        sourceRow(source)
                    }
                    .onDelete(perform: deleteSources)
                }
            }
            .navigationTitle("书源管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingURLInput = true
                        } label: {
                            Label("从网址导入", systemImage: "link")
                        }
                        Button {
                            showingImport = true
                        } label: {
                            Label("从文件导入", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                DocumentPicker(contentTypes: [.json, .plainText]) { url in
                    importSourceFile(url: url)
                }
            }
            .alert("输入书源网址", isPresented: $showingURLInput) {
                TextField("https://...", text: $sourceURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) { sourceURL = "" }
                Button("导入") { importFromURL() }
                    .disabled(sourceURL.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("支持 JSON 格式的书源链接")
            }
            .alert("导入结果", isPresented: $showingResult) {
                Button("确定") {}
            } message: {
                if let error = importError {
                    Text("导入失败：\(error)")
                } else if let count = importCount {
                    Text("成功导入 \(count) 个书源")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("暂无书源")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("点击右上角从网址或文件导入书源")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text(source.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let group = source.sourceGroup {
                        Text(group)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { source.enabled = $0 }
            ))
            .labelsHidden()
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sources[index])
        }
    }

    private func importFromURL() {
        let urlString = sourceURL.trimmingCharacters(in: .whitespaces)
        sourceURL = ""
        guard !urlString.isEmpty else { return }
        isLoadingURL = true

        Task {
            do {
                let json = try await NetworkClient.shared.fetchString(url: urlString)
                let service = SourceImportService(modelContext: modelContext)
                let count = try service.importJSON(json)
                importCount = count
                importError = nil
            } catch {
                importError = error.localizedDescription
                importCount = nil
            }
            isLoadingURL = false
            showingResult = true
        }
    }

    private func importSourceFile(url: URL) {
        let service = SourceImportService(modelContext: modelContext)
        do {
            let count = try service.importFromFile(url: url)
            importCount = count
            importError = nil
        } catch {
            importError = error.localizedDescription
            importCount = nil
        }
        showingResult = true
    }
}
