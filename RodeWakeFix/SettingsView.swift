import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            statusCard
            wakeStatus
            deviceGrid
            actions
            activity
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var wakeStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
            Text("Last wake: \(state.lastWakeSummary)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 48, height: 48)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("RØDE Wake Fix")
                    .font(.title2.weight(.semibold))
                Text("Sleep/wake recovery for your NT-USB Mini")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.autoStartInstalled ? "Runs at login" : "Manual only")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    state.autoStartInstalled ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.headline)
                    .font(.headline)
                Text(state.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var deviceGrid: some View {
        HStack(spacing: 10) {
            metric("USB", value: state.usbPresent ? "Connected" : "Not found", ok: state.usbPresent)
            metric("CoreAudio", value: state.coreAudioPresent ? "Available" : "Not found", ok: state.coreAudioPresent)
            metric("System input", value: state.targetIsDefault ? "RØDE" : state.defaultInputName, ok: state.targetIsDefault)
        }
    }

    private func metric(_ title: String, value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(ok ? .green : .secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                state.refreshStatus()
            } label: {
                Label("Check now", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                state.setTargetAsDefault()
            } label: {
                Label("Use RØDE", systemImage: "mic.fill")
            }
            .disabled(!state.coreAudioPresent || state.targetIsDefault)

            Spacer()

            if state.autoStartInstalled {
                Button("Disable background start", role: .destructive) {
                    state.removeBackgroundHelper()
                }
            } else {
                Button {
                    state.installBackgroundHelper()
                } label: {
                    Label("Enable background start", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Recent activity")
                    .font(.headline)
                Spacer()
                Button("Open log") {
                    state.openLog()
                }
                .buttonStyle(.link)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if state.recentEvents.isEmpty {
                        Text("No events yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(state.recentEvents.enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var statusColor: Color {
        if state.targetIsDefault { return .green }
        if state.usbPresent && !state.coreAudioPresent { return .orange }
        return .secondary
    }
}
