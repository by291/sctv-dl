use std::{error::Error, fmt};

use crate::error::{AppError, ErrorCode, Result};

pub(super) fn storage(error: std::io::Error) -> AppError {
    AppError::with_source(ErrorCode::Storage, "无法保存或清理下载文件", error)
}

pub(super) fn network(error: reqwest::Error) -> AppError {
    AppError::with_source(
        if error.is_timeout() {
            ErrorCode::Timeout
        } else {
            ErrorCode::Upstream
        },
        if error.is_timeout() {
            "视频传输超时，请重试"
        } else {
            "视频传输中断，请重试"
        },
        error.without_url(),
    )
}

/// Keeps both failures private while retaining the primary IPC error contract.
pub(super) fn with_rollback(primary: AppError, rollback: Result<()>) -> AppError {
    with_secondary(primary, rollback, "rollback")
}

pub(super) fn with_secondary(
    primary: AppError,
    secondary: Result<()>,
    phase: &'static str,
) -> AppError {
    match secondary {
        Ok(()) => primary,
        Err(secondary) => AppError::with_source(
            primary.code,
            primary.message.clone(),
            SecondaryFailure {
                primary,
                secondary,
                phase,
            },
        ),
    }
}

#[derive(Debug)]
struct SecondaryFailure {
    primary: AppError,
    secondary: AppError,
    phase: &'static str,
}

impl fmt::Display for SecondaryFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "primary: {}", self.primary)?;
        if let Some(cause) = self.primary.source() {
            write!(formatter, ": {cause}")?;
        }
        write!(formatter, "; {}: {}", self.phase, self.secondary)?;
        if let Some(cause) = self.secondary.source() {
            write!(formatter, ": {cause}")?;
        }
        Ok(())
    }
}

impl Error for SecondaryFailure {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(&self.primary)
    }
}
