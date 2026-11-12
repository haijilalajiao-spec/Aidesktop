import SwiftUI

@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var custom: [AIService] = []
    @Published private(set) var hiddenBuiltins: Set<String> = []
    @Published private(set) var groupOrders: [String: [String]] = [:]
    @Published private(set) var groupOverrides: [String: String] = [:]
    @Published private(set) var collapsedGroups: Set<String> = []
    @Published private(set) var groupSequence: [String] = []

    private let storageKey = "AIWorkbench.CustomServices"
    private let hiddenKey = "AIWorkbench.HiddenBuiltins"
    private let orderKey = "AIWorkbench.GroupOrders"
    private let overrideKey = "AIWorkbench.GroupOverrides"
    private let collapsedKey = "AIWorkbench.CollapsedGroups"
    private let groupSequenceKey = "AIWorkbench.GroupSequence"

    init() {
        load()
        Log.write("services: builtin=\(AIService.all.count) custom=\(custom.count) hidden=\(hiddenBuiltins.count)")
    }

    var services: [AIService] {
        let base = AIService.all.filter { !hiddenBuiltins.contains($0.id) } + custom
        return base.map { service in
            guard let group = groupOverrides[service.id], group != service.group else {
                return service
            }
            return service.withGroup(group)
        }
    }

    var desktopServices: [AIService] { services.filter { $0.kind == .app } }

    var defaultWebID: String? { services.first { $0.kind == .web }?.id }

    /// 某个分组内、按用户自定义顺序排列的服务。
    func services(in group: String) -> [AIService] {
        let items = services.filter { $0.group == group }
        let order = groupOrders[group] ?? []
        let index = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        return items.enumerated().sorted { lhs, rhs in
            let left = index[lhs.element.id] ?? Int.max
            let right = index[rhs.element.id] ?? Int.max
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func move(in group: String, from source: IndexSet, to destination: Int) {
        var ids = services(in: group).map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        groupOrders[group] = ids
        save()
    }

    func moveToGroup(id: String, group: String) {
        guard let service = services.first(where: { $0.id == id }), service.group != group else { return }
        let destination = services(in: group).map(\.id)
        groupOverrides[id] = group
        for key in groupOrders.keys {
            groupOrders[key]?.removeAll { $0 == id }
        }
        groupOrders[group] = destination + [id]
        collapsedGroups.remove(group)
        ensureGroup(group)
        save()
    }

    func isCollapsed(_ group: String) -> Bool {
        collapsedGroups.contains(group)
    }

    func toggleCollapsed(_ group: String) {
        if collapsedGroups.contains(group) {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
        save()
    }

    func move(id: String, in group: String, delta: Int) {
        var ids = services(in: group).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + delta
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        groupOrders[group] = ids
        save()
    }

    var groups: [String] {
        let visibleGroups = Set(services.map(\.group))
        let sequence = groupSequence.isEmpty
            ? ["我的应用"] + AIService.groups
            : groupSequence

        var result: [String] = []
        for group in sequence where visibleGroups.contains(group) && !result.contains(group) {
            result.append(group)
        }
        for group in visibleGroups.sorted() where !result.contains(group) {
            result.append(group)
        }
        return result
    }

    func moveGroup(_ group: String, delta: Int) {
        var sequence = groups
        guard let index = sequence.firstIndex(of: group) else { return }
        let target = index + delta
        guard sequence.indices.contains(target) else { return }
        sequence.swapAt(index, target)
        groupSequence = sequence
        save()
    }

    @discardableResult
    func renameGroup(_ old: String, to newName: String) -> Bool {
        let new = newName.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old, !groups.contains(new) else { return false }

        for service in services where service.group == old {
            groupOverrides[service.id] = new
        }

        if groupSequence.isEmpty {
            groupSequence = ["我的应用"] + AIService.groups
        }
        if let index = groupSequence.firstIndex(of: old) {
            groupSequence[index] = new
        } else if !groupSequence.contains(new) {
            groupSequence.append(new)
        }

        if let orders = groupOrders.removeValue(forKey: old) {
            groupOrders[new] = orders
        }
        if collapsedGroups.remove(old) != nil {
            collapsedGroups.insert(new)
        }

        save()
        return true
    }

    private func ensureGroup(_ group: String) {
        if groupSequence.isEmpty {
            groupSequence = ["我的应用"] + AIService.groups
        }
        guard !groupSequence.contains(group) else { return }
        if let index = groupSequence.firstIndex(of: "我的应用") {
            groupSequence.insert(group, at: index + 1)
        } else {
            groupSequence.append(group)
        }
    }

    func isCustom(_ id: String) -> Bool {
        custom.contains { $0.id == id }
    }

    func contains(bundleID: String) -> Bool {
        services.contains { $0.bundleID == bundleID }
    }

    func contains(url: URL) -> Bool {
        let key = WebAddress.comparisonKey(url)
        return services.contains { service in
            guard let raw = service.url, let existing = WebAddress.parse(raw) else { return false }
            return WebAddress.comparisonKey(existing) == key
        }
    }

    func add(_ service: AIService) {
        guard !custom.contains(where: { $0.id == service.id }) else { return }
        custom.append(service)
        groupOrders[service.group] = services(in: service.group).map(\.id)
        collapsedGroups.remove(service.group)
        ensureGroup(service.group)
        save()
    }

    func remove(id: String) {
        if custom.contains(where: { $0.id == id }) {
            custom.removeAll { $0.id == id }
        } else {
            hiddenBuiltins.insert(id)
        }
        groupOverrides.removeValue(forKey: id)
        for key in groupOrders.keys {
            groupOrders[key]?.removeAll { $0 == id }
        }
        save()
    }

    func restoreHidden() {
        hiddenBuiltins.removeAll()
        save()
    }

    /// 如果添加的是被隐藏的内置应用，直接恢复它而不是新建副本。
    func restoreIfHidden(bundleID: String) -> Bool {
        guard let builtin = AIService.all.first(where: { $0.bundleID == bundleID }),
              hiddenBuiltins.contains(builtin.id) else { return false }
        hiddenBuiltins.remove(builtin.id)
        save()
        return true
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AIService].self, from: data) {
            custom = decoded
        }
        if let hidden = UserDefaults.standard.array(forKey: hiddenKey) as? [String] {
            hiddenBuiltins = Set(hidden)
        }
        if let data = UserDefaults.standard.data(forKey: orderKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            groupOrders = decoded
        }
        if let data = UserDefaults.standard.data(forKey: overrideKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            groupOverrides = decoded
        }
        if let collapsed = UserDefaults.standard.array(forKey: collapsedKey) as? [String] {
            collapsedGroups = Set(collapsed)
        }
        if let sequence = UserDefaults.standard.array(forKey: groupSequenceKey) as? [String] {
            groupSequence = sequence
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(Array(hiddenBuiltins), forKey: hiddenKey)
        if let data = try? JSONEncoder().encode(groupOrders) {
            UserDefaults.standard.set(data, forKey: orderKey)
        }
        if let data = try? JSONEncoder().encode(groupOverrides) {
            UserDefaults.standard.set(data, forKey: overrideKey)
        }
        UserDefaults.standard.set(Array(collapsedGroups), forKey: collapsedKey)
        UserDefaults.standard.set(groupSequence, forKey: groupSequenceKey)
    }
}
