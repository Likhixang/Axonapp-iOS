import SwiftUI

/// Condition (`when`) editor for a model association, with the same fields, operators and
/// value choices as the web console's filter builder.
struct ConditionEditorSections: View {
    @Binding var condition: AssociationWhen

    var body: some View {
        Section {
            Toggle("按条件生效", isOn: $condition.enabled.animation())
        } header: {
            Text("生效条件")
        } footer: {
            if condition.enabled {
                Text("仅当请求满足所有条件组时，才应用这条关联。" + (condition.usesDailyTime ? "每日时间段条件使用服务器本地时区。" : ""))
            } else {
                Text("关闭时这条关联对所有请求生效。")
            }
        }

        if condition.enabled {
            ForEach($condition.groups) { $group in
                Section {
                    Picker("逻辑", selection: $group.logic) {
                        Text("同时满足").tag("and")
                        Text("满足其一").tag("or")
                    }
                    .pickerStyle(.segmented)
                    ForEach($group.conditions) { $item in
                        NavigationLink {
                            ConditionRowEditor(condition: $item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.summary).font(.callout)
                                if let error = item.validationError {
                                    Text(error).font(.caption).foregroundStyle(Theme.danger)
                                }
                            }
                        }
                    }
                    .onDelete { group.conditions.remove(atOffsets: $0) }
                    Button {
                        group.conditions.append(.makeDefault())
                    } label: {
                        Label("添加条件", systemImage: "plus")
                    }
                    Button("删除这个条件组", role: .destructive) {
                        let id = group.id
                        condition.groups.removeAll { $0.id == id }
                    }
                } header: {
                    Text("条件组 \((condition.groups.firstIndex { $0.id == group.id } ?? 0) + 1)")
                }
            }
            Section {
                Button {
                    condition.groups.append(AssociationConditionGroup(conditions: [.makeDefault()]))
                } label: {
                    Label("添加条件组", systemImage: "plus.circle")
                }
            } footer: {
                if let error = condition.validationError {
                    Text(error).foregroundStyle(Theme.danger)
                }
            }
        }
    }
}

struct ConditionRowEditor: View {
    @Binding var condition: AssociationCondition

    var body: some View {
        Form {
            Section {
                Picker("字段", selection: Binding(get: { condition.baseField }, set: { condition.setBaseField($0) })) {
                    ForEach(ConditionCatalog.fields) { Text($0.label).tag($0.value) }
                }
                if condition.baseField == "request_header" {
                    OptionPickerRow(title: "头部名称", value: condition.headerName, placeholder: "如 X-Model",
                                    monospaced: true, options: ConditionCatalog.headerSuggestions) { condition.headerName = $0 }
                }
                if let def = condition.definition {
                    Picker("运算符", selection: $condition.op) {
                        ForEach(def.operators, id: \.self) { Text(ConditionCatalog.operatorLabels[$0] ?? $0).tag($0) }
                    }
                }
            }
            Section {
                valueEditor
            } header: {
                Text("值")
            } footer: {
                if let error = condition.validationError {
                    Text(error).foregroundStyle(Theme.danger)
                } else if condition.field == "daily_time" {
                    Text("使用服务器本地时区，可以跨过午夜，如 22:00-06:00。")
                }
            }
        }
        .navigationTitle("条件")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var valueEditor: some View {
        let def = condition.definition
        switch def?.type {
        case .boolean?:
            Picker("值", selection: Binding(get: { condition.value.boolValue ?? true }, set: { condition.value = .bool($0) })) {
                Text("是").tag(true)
                Text("否").tag(false)
            }
            .pickerStyle(.segmented)
        case .number?:
            TextField(def?.placeholder ?? "", text: Binding(get: { condition.textValue }, set: { condition.setText($0) }))
                .keyboardType(.numberPad)
        default:
            if let def, !def.options.isEmpty {
                OptionPickerRow(title: def.label, value: condition.textValue, placeholder: def.placeholder,
                                monospaced: true, options: def.options, allowsCustom: false) { condition.setText($0) }
            } else if condition.field == "reasoning_effort" {
                OptionPickerRow(title: "推理强度", value: condition.textValue, placeholder: def?.placeholder ?? "",
                                monospaced: true, options: ProvidersCatalog.reasoningEfforts) { condition.setText($0) }
            } else {
                TextField(def?.placeholder ?? "", text: Binding(get: { condition.textValue }, set: { condition.setText($0) }))
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}
