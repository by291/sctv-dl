use std::{
    error::Error,
    fmt,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use serde::Serialize;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ErrorCode {
    InvalidInput,
    NotFound,
    Upstream,
    Timeout,
    Cancelled,
    Storage,
}

#[derive(Debug, Default)]
struct Diagnostic {
    source: Option<Box<dyn Error + Send + Sync>>,
    reported: AtomicBool,
}

#[derive(Clone, Debug, Serialize)]
pub struct AppError {
    pub code: ErrorCode,
    pub message: String,
    #[serde(skip)]
    diagnostic: Arc<Diagnostic>,
}

impl AppError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            diagnostic: Arc::default(),
        }
    }

    /// Retains a private cause. Callers must remove URLs and credentials first.
    pub fn with_source(
        code: ErrorCode,
        message: impl Into<String>,
        source: impl Error + Send + Sync + 'static,
    ) -> Self {
        Self {
            code,
            message: message.into(),
            diagnostic: Arc::new(Diagnostic {
                source: Some(Box::new(source)),
                reported: AtomicBool::new(false),
            }),
        }
    }

    /// Reports an operational failure once, including across cloned results.
    pub fn reported(self, operation: &str) -> Self {
        if matches!(
            self.code,
            ErrorCode::InvalidInput | ErrorCode::NotFound | ErrorCode::Cancelled
        ) || self.diagnostic.reported.swap(true, Ordering::Relaxed)
        {
            return self;
        }

        if let Some(source) = self.source() {
            eprintln!("[desktop] {operation}: {:?}: {self}: {source}", self.code);
        } else {
            eprintln!("[desktop] {operation}: {:?}: {self}", self.code);
        }

        self
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for AppError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        self.diagnostic
            .source
            .as_deref()
            .map(|source| source as &(dyn Error + 'static))
    }
}

pub type Result<T> = std::result::Result<T, AppError>;
