import SwiftUI

struct RenameGroupSheet: View {
    let group: String
    @ObservedObject var services: ServiceStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var errorMessage: String?

    init(group: String, services: ServiceStore) {
        self.group = group
        self.services = services
        _name = State(initialValue: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名分组")
                .font(.system(size: 16, weight: .semibold))

            TextField("分组名称", text: $name)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func save() {
        if services.renameGroup(group, to: name) {
            dismiss()
        } else {
            errorMessage = "名称不能为空，也不能与现有分组重名"
        }
    }
}
