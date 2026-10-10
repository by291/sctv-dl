package dev.sctvdl.ui.downloads

import dev.sctvdl.domain.download.BatchDownloadResult
import kotlinx.coroutines.flow.first

fun batchResultMessage(result: BatchDownloadResult): String = buildString {
    append("已加入 ${result.queued} 个下载")
    if (result.fallbacks > 0) append("，${result.fallbacks} 个使用可用清晰度")
    if (result.failures.isNotEmpty()) {
        append(
            "；${result.failures.size} 个未加入：${result.failures.first().error.message}"
        )
    }
}
