import SwiftUI
import AgeOSCore

/// MCP manager: enable per-client, health badge, cảnh báo env nhạy cảm.
struct McpView: View {
    @Environment(AppModel.self) private var model

    var mcpAdapters: [AdapterSpec] {
        model.adapters.filter { $0.isDetected() && $0.mcp != nil }
    }

    var body: some View {
        List {
            ForEach(model.mcpServers, id: \.id) { server in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(server.name).font(.headline)
                                Text(server.id).font(.caption).foregroundStyle(.secondary)
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
                            Text(server.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if !server.sensitiveEnvKeys.isEmpty {
                            Label("Env nhạy cảm plaintext trong config client: \(server.sensitiveEnvKeys.joined(separator: ", ")) (Keychain là v1.1)",
                                  systemImage: "key")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        HStack(spacing: 14) {
                            ForEach(mcpAdapters) { adapter in
                                Toggle(adapter.displayName, isOn: Binding(
                                    get: { model.mcpIsEnabled(serverId: server.id, adapterId: adapter.id) },
                                    set: { on in
                                        Task { await model.mcpToggle(serverQuery: server.id,
                                                                     adapterId: adapter.id, enabled: on) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("\(server.name) cho \(adapter.displayName)")
                            }
                        }
                    }
                    .padding(4)
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("MCP Servers")
        .overlay {
            if model.mcpServers.isEmpty {
                ContentUnavailableView("Chưa có MCP server",
                                       systemImage: "server.rack",
                                       description: Text("Add bằng CLI: ageos mcp add <registry-name|file.mcpb>"))
            }
        }
    }
}

struct HealthBadge: View {
    let report: HealthCheck.Report?

    var body: some View {
        if let report {
            if report.ok {
                Label("\(report.toolCount) tools · \(report.latencyMs)ms · ≈\(report.schemaTokens)tk",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label(report.error ?? "fail", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        } else {
            Label("chưa đo", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
