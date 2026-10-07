package dev.sctvdl.domain

enum class ErrorKind {
    Network,
    Http,
    Business,
    InvalidData,
    UnsafeUrl,
    NoVideo,
    Storage,
    Download,
    Unknown
}
data class AppError(val kind: ErrorKind, val message: String, val code: Int? = null)
class AppException(val error: AppError, cause: Throwable? = null) : Exception(error.message, cause)
