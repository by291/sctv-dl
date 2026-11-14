import SCTVCore

/// Localized download messages shared by the task list and native file actions.
public enum DownloadIssueMessage {
    /// Returns the user-facing explanation for a known download issue.
    public static func text(for code: DownloadIssueCode) -> String {
        switch code {
        case .unsafePath: "文件路径无效。"
        case .missingFile: "文件已移动或删除。"
        case .accessDenied: "无法访问下载目录，请重新授权。"
        case .identityChanged: "文件已被替换，操作已取消。"
        case .emptyFile: "下载文件为空，请重新下载。"
        case .invalidMedia: "下载内容不是可播放的视频，请重新下载。"
        case .missingCallbackFile: "系统未保留下载文件，请重新下载。"
        case .stagedPathOccupied: "临时下载文件已占用，请重试。"
        case .unknownSession: "无法恢复原下载任务，请重试。"
        case .invalidResume: "无法继续原下载，请重新下载。"
        case .invalidSource: "节目下载地址不可用，请重试。"
        }
    }
}
