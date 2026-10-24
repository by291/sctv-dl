import SCTVCore
import SwiftUI

public struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable private var model: SettingsModel
    private let clearCache: () async throws -> Void
    private let appVersion: String
    private let destinationDescription: String
    private let chooseDirectory: (() -> Void)?
    private let resetDirectory: (() -> Void)?
    @State private var showingCacheConfirmation = false
    @State private var cacheResult: String?

    public init(
        model: SettingsModel, clearCache: @escaping () async throws -> Void,
        destinationDescription: String = "应用下载目录", chooseDirectory: (() -> Void)? = nil,
        resetDirectory: (() -> Void)? = nil, appVersion: String = "0.1.0"
    ) {
        self.appVersion = appVersion
        self.model = model
        self.clearCache = clearCache
        self.destinationDescription = destinationDescription
        self.chooseDirectory = chooseDirectory
        self.resetDirectory = resetDirectory
    }

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(PresentationStyle.accent(scheme))
                        .frame(width: 64, height: 64)
                        .background(
                            PresentationStyle.accent(scheme).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCTV").font(.system(.title, design: .serif, weight: .bold))
                        Text("让好节目，随时在身边。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 10)
            }

            Section("外观") {
                Picker(
                    "显示模式",
                    selection: Binding(
                        get: { model.value.appearance },
                        set: { next in model.change { $0.appearance = next } })
                ) {
                    Text("跟随系统").tag(Preferences.Appearance.system)
                    Text("浅色").tag(Preferences.Appearance.light)
                    Text("深色").tag(Preferences.Appearance.dark)
                }
            }
            Section("播放与下载") {
                Picker(
                    "首选画质",
                    selection: Binding(
                        get: { model.value.playbackQuality },
                        set: { next in model.change { $0.playbackQuality = next } })
                ) {
                    Text("标准").tag(VideoQuality.standard)
                    Text("流畅").tag(VideoQuality.smooth)
                }
                Toggle(
                    "允许通过蜂窝网络下载",
                    isOn: Binding(
                        get: { model.value.allowCellularDownloads },
                        set: { next in model.change { $0.allowCellularDownloads = next } }))
                Text("网络设置仅应用于新建的下载任务。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("存储") {
                #if os(macOS)
                    storageLocationRow
                    storageCacheRow
                #else
                    LabeledContent("新下载保存到", value: destinationDescription)
                    if let chooseDirectory { Button("选择其他下载目录", action: chooseDirectory) }
                    if let resetDirectory { Button("使用应用下载目录", action: resetDirectory) }
                    cacheButton
                    Text("保留收藏、观看历史、设置和已下载的文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                #endif
            }
            Section("关于") {
                LabeledContent("SCTV", value: appVersion)
                Text("本机数据独立保存，不与其他客户端同步。").font(.footnote).foregroundStyle(.secondary)
            }
            if let warning = model.warning {
                Section {
                    Text(warning)
                    Button("重试保存") { Task { await model.flush() } }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PresentationStyle.canvas(scheme))
        .tint(PresentationStyle.accent(scheme))
        .navigationTitle("设置")
        .alert(
            "缓存清理",
            isPresented: Binding(
                get: { cacheResult != nil },
                set: { if !$0 { cacheResult = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(cacheResult ?? "")
        }
        .task { await model.load() }
    }

    #if os(macOS)
        private var storageLocationRow: some View {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载位置")
                    Text(destinationDescription)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if let resetDirectory {
                        Button("恢复默认", action: resetDirectory)
                            .help("新下载使用应用下载目录，已有文件保留在原位置")
                    }
                    if let chooseDirectory {
                        Button(action: chooseDirectory) {
                            Text("更改…").frame(minWidth: 44)
                        }
                        .help("选择其他下载目录")
                        .accessibilityIdentifier("settings-change-directory")
                    }
                }
                .fixedSize()
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(PresentationStyle.accent(scheme))
            }
            .padding(.vertical, 4)
        }

        private var storageCacheRow: some View {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("缓存")
                    Text("保留收藏、观看历史、设置和已下载的文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                cacheButton
                    .fixedSize()
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(PresentationStyle.accent(scheme))
                    .foregroundStyle(PresentationStyle.accent(scheme))
            }
            .padding(.vertical, 4)
        }
    #endif

    private var cacheButton: some View {
        Button {
            showingCacheConfirmation = true
        } label: {
            #if os(macOS)
                Text("清理").frame(minWidth: 44)
            #else
                Text("清理缓存")
            #endif
        }
        .accessibilityLabel("清理缓存")
        .accessibilityIdentifier("settings-clear-cache")
        .alert("清理缓存？", isPresented: $showingCacheConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清理缓存", role: .destructive, action: clearStoredCache)
        } message: {
            Text("将清理节目数据和封面缓存。收藏、观看历史、设置和已下载的文件都会保留。")
        }
    }

    private func clearStoredCache() {
        Task {
            do {
                try await clearCache()
                ArtworkCache.clear()
                cacheResult = "缓存已清理"
            } catch { cacheResult = error.localizedDescription }
        }
    }
}
