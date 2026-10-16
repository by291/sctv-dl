use std::{error::Error, io};

use sctv_dl_desktop_lib::error::{AppError, ErrorCode};

#[test]
fn internal_causes_survive_cloning_without_entering_the_ipc_response() {
    let error = AppError::with_source(
        ErrorCode::Storage,
        "Unable to save preferences",
        io::Error::new(io::ErrorKind::PermissionDenied, "private diagnostic detail"),
    );
    let cloned = error.clone();

    assert_eq!(
        cloned.source().unwrap().to_string(),
        "private diagnostic detail"
    );
    assert_eq!(
        serde_json::to_value(&cloned).unwrap(),
        serde_json::json!({
            "code": "storage",
            "message": "Unable to save preferences",
        })
    );
    assert_eq!(cloned.to_string(), "Unable to save preferences");
}

#[test]
fn typed_errors_keep_the_existing_wire_codes() {
    for (code, wire) in [
        (ErrorCode::InvalidInput, "invalid-input"),
        (ErrorCode::NotFound, "not-found"),
        (ErrorCode::Upstream, "upstream"),
        (ErrorCode::Timeout, "timeout"),
        (ErrorCode::Cancelled, "cancelled"),
        (ErrorCode::Storage, "storage"),
    ] {
        let error = AppError::new(code, "Request failed");

        assert!(error.source().is_none());
        assert_eq!(serde_json::to_value(error).unwrap()["code"], wire);
    }
}
