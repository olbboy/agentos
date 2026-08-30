import SwiftUI
import AgeOSCore

/// MCP manager: per-client enable, health, and the sensitive-env warning.
///
/// Enabled and Available are split rather than one flat list: what is running on the
/// machine and what merely sits in the library are different questions, and mixing
/// them means reading every row to tell which is which.
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
                // The warning text is unchanged — it is correct and the user needs it
                // before enabling. Only its presentation changed.
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
