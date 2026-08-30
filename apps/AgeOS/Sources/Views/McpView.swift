import SwiftUI
import AgeOSCore

/// MCP manager: enable per-client, health, cảnh báo env nhạy cảm.
///
/// Tách Enabled / Available thay vì một list phẳng: thứ đang chạy trên máy và thứ
/// mới chỉ nằm trong library là hai câu hỏi khác nhau, trộn lại thì phải đọc từng
/// dòng mới biết cái nào là cái nào.
struct McpView: View {
    @Environment(AppModel.self) private var model

    var mcpAdapters: [AdapterSpec] {
        model.adapters.filter { $0.isDetected() && $0.mcp != nil }
    }

    private var enabled: [McpServerModel] {
        model.mcpServers.filter { server in
            mcpAdapters.contains { model.mcpIsEnabled(serverId: server.id, adapterId: $0.id) }
        }
    }

    private var available: [McpServerModel] {
        let enabledIds = Set(enabled.map(\.id))
        return model.mcpServers.filter { !enabledIds.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                SectionCard(title: "Enabled", count: enabled.count) {
                    if enabled.isEmpty {
                        Text("No MCP server is enabled on any client yet.")
                            .font(.ageCallout)
                            .foregroundStyle(Color.ageTextSecondary)
                    } else {
                        serverList(enabled)
                    }
                }

                SectionCard(title: "Available", count: available.count) {
                    if available.isEmpty {
                        Text("Every server in the library is enabled somewhere.")
                            .font(.ageCallout)
                            .foregroundStyle(Color.ageTextSecondary)
                    } else {
                        serverList(available)
                    }
                }
            }
            .padding(Space.xxl)
        }
        .background(Color.ageSurface)
        .navigationTitle("MCP Servers")
        .overlay {
            if model.mcpServers.isEmpty {
                EmptyState(icon: "server.rack",
                           title: "No MCP servers yet",
                           message: "Add one from the CLI: ageos mcp add <registry-name|file.mcpb>")
            }
        }
    }

    private func serverList(_ servers: [McpServerModel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                if index > 0 { Divider().overlay(Color.ageBorderSubtle) }
                serverRow(server)
            }
        }
    }

    private func serverRow(_ server: McpServerModel) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: server.name)
                        .font(.ageHeadline)
                        .foregroundStyle(Color.ageTextPrimary)
                    Text(verbatim: server.id)
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                }
                Spacer()
                HealthBadge(report: model.healthByName[server.name])
                Button("Health") {
                    Task { await model.healthCheck(serverQuery: server.id) }
                }
                .controlSize(.small)
                .accessibilityLabel("Health check \(server.name)")
            }

            if !server.description.isEmpty {
                Text(verbatim: server.description)
                    .font(.ageCallout)
                    .foregroundStyle(Color.ageTextSecondary)
                    .lineLimit(2)
            }

            if !server.sensitiveEnvKeys.isEmpty {
                // Nội dung cảnh báo giữ nguyên — nó đúng và người dùng cần biết
                // trước khi enable, chỉ đổi cách trình bày.
                StatusPill("plaintext env: \(server.sensitiveEnvKeys.joined(separator: ", "))",
                           tone: .warning, icon: "key")
                Text("These values sit in plaintext inside the client config. Keychain storage lands in v1.1.")
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
            }

            HStack(spacing: Space.lg) {
                ForEach(mcpAdapters) { adapter in
                    Toggle(adapter.displayName, isOn: Binding(
                        get: { model.mcpIsEnabled(serverId: server.id, adapterId: adapter.id) },
                        set: { on in
                            Task { await model.mcpToggle(serverQuery: server.id,
                                                         adapterId: adapter.id, enabled: on) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(server.name) for \(adapter.displayName)")
                }
            }
        }
        .padding(.vertical, Space.md)
    }
}

struct HealthBadge: View {
    let report: HealthCheck.Report?

    var body: some View {
        if let report {
            if report.ok {
                StatusPill("\(report.toolCount) tools · \(report.latencyMs)ms · ≈\(report.schemaTokens)tk",
                           tone: .success, icon: "checkmark.circle.fill")
            } else {
                StatusPill(verbatim: report.error ?? "failed",
                           tone: .danger, icon: "xmark.circle.fill")
            }
        } else {
            StatusPill("not measured", tone: .neutral, icon: "questionmark.circle")
        }
    }
}
