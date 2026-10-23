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
    @State private var cacheMessage: String?

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
                LabeledContent("新下载保存到", value: destinationDescription)
                if let chooseDirectory { Button("选择其他下载目录", action: chooseDirectory) }
                if let resetDirectory { Button("使用应用下载目录", action: resetDirectory) }
                Button("清理缓存") {
                    Task {
                        do {
                            try await clearCache()
                            ArtworkCache.clear()
                            cacheMessage = "缓存已清理"
                        } catch { cacheMessage = error.localizedDescription }
                    }
                }
                Text("保留收藏、观看历史、设置和已下载的文件。").font(.footnote).foregroundStyle(.secondary)
                if let cacheMessage { Text(cacheMessage).font(.callout) }
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
        .task { await model.load() }
    }
}
