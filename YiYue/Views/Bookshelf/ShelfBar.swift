import SwiftUI
import SwiftData

/// 书架页顶部那条书架栏:全部 / 未分组 / 各个自定义书架。
/// 自己做管理:新建、重命名、删除都在这个组件里。
struct ShelfBar: View {
    @Binding var filter: ShelfFilter
    let totalCount: Int
    let unshelvedCount: Int

    @Query(sort: \Shelf.sortIndex) private var shelves: [Shelf]
    @Environment(\.modelContext) private var modelContext

    @State private var editingShelf: Shelf?
    @State private var draftName = ""
    @State private var showingNewShelf = false
    @State private var deletingShelf: Shelf?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", count: totalCount, value: .all)
                chip(title: "未分组", count: unshelvedCount, value: .unshelved)

                ForEach(shelves) { shelf in
                    chip(title: shelf.name, count: count(of: shelf), value: .shelf(shelf.id))
                        .contextMenu {
                            Button {
                                draftName = shelf.name
                                editingShelf = shelf
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deletingShelf = shelf
                            } label: {
                                Label("删除书架", systemImage: "trash")
                            }
                        }
                }

                Button {
                    draftName = ""
                    showingNewShelf = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建书架")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .alert("新建书架", isPresented: $showingNewShelf) {
            TextField("书架名字", text: $draftName)
            Button("取消", role: .cancel) { draftName = "" }
            Button("创建") { createShelf() }
        }
        .alert("重命名书架", isPresented: Binding(
            get: { editingShelf != nil },
            set: { if !$0 { editingShelf = nil } }
        )) {
            TextField("书架名字", text: $draftName)
            Button("取消", role: .cancel) { editingShelf = nil }
            Button("保存") { renameShelf() }
        }
        .alert("删除书架「\(deletingShelf?.name ?? "")」？", isPresented: Binding(
            get: { deletingShelf != nil },
            set: { if !$0 { deletingShelf = nil } }
        )) {
            Button("取消", role: .cancel) { deletingShelf = nil }
            Button("删除", role: .destructive) { deleteShelf() }
        } message: {
            Text("书架里的书不会删掉,会回到「未分组」。")
        }
    }

    private func chip(title: String, count: Int, value: ShelfFilter) -> some View {
        let selected = filter == value
        return Button {
            withAnimation(.snappy(duration: 0.2)) { filter = value }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .opacity(0.55)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if selected {
                    Capsule().fill(Color.white.opacity(0.12))
                } else {
                    Capsule().fill(Color.white.opacity(0.05))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func count(of shelf: Shelf) -> Int {
        allBooks.filter { $0.shelfID == shelf.id }.count
    }

    private var allBooks: [Book] {
        (try? modelContext.fetch(FetchDescriptor<Book>())) ?? []
    }

    private func createShelf() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        draftName = ""
        guard !name.isEmpty else { return }
        let shelf = Shelf(name: name, sortIndex: (shelves.last?.sortIndex ?? -1) + 1)
        modelContext.insert(shelf)
        try? modelContext.save()
        filter = .shelf(shelf.id)
    }

    private func renameShelf() {
        guard let shelf = editingShelf else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        editingShelf = nil
        draftName = ""
        guard !name.isEmpty else { return }
        shelf.name = name
        try? modelContext.save()
    }

    private func deleteShelf() {
        guard let shelf = deletingShelf else { return }
        deletingShelf = nil
        let shelfID = shelf.id
        for book in allBooks where book.shelfID == shelfID { book.shelfID = nil }
        modelContext.delete(shelf)
        try? modelContext.save()
        if filter == .shelf(shelfID) { filter = .all }
    }
}
