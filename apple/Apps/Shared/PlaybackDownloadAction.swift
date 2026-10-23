import SCTVCore
import SCTVMedia

extension AppDependencies {
    func downloadCurrentProgramme() async -> String {
        guard let details = player.details, !details.isLocal else { return "本地视频已保存在设备上。" }
        let content = ProgrammeContent(
            id: details.content.contentID, title: details.title, cover: details.cover,
            video: details.sources.first { $0.quality == .standard }?.url,
            smoothVideo: details.sources.first { $0.quality == .smooth }?.url, publishedAt: nil)
        let prepared = DownloadPreparation.prepare(
            contents: [content],
            programme: Programme(
                id: details.content.programmeID, name: details.programmeName, cover: details.cover),
            broadcast: BroadcastDate(id: details.content.dateID, date: details.broadcastDate),
            requestedQuality: settings.value.playbackQuality, productVersion: "0.1.0")
        await downloads.start()
        if let warning = downloads.warning { return warning }
        let result = await downloads.service.start(
            prepared.prepared.map {
                $0.request(
                    destination: downloads.destination,
                    allowsCellular: settings.value.allowCellularDownloads)
            })
        if result.accepted.isEmpty { return "未能添加下载，请检查下载列表或稍后重试。" }
        return "已添加下载，可在下载页面查看进度。"
    }
}
