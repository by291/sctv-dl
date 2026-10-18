use reqwest::{
    StatusCode,
    header::{HeaderMap, HeaderValue},
};
use sctv_dl_desktop_lib::downloads::{
    file_identity::FileIdentity,
    journal::ResumeCheckpoint,
    resume::{ResumeDecision, decide},
};

fn checkpoint(bytes: u64) -> ResumeCheckpoint {
    ResumeCheckpoint {
        task_id: "task".into(),
        attempt_id: "attempt".into(),
        file_identity: FileIdentity { device: 1, file: 2 },
        committed_bytes: bytes,
        total_bytes: Some(100),
        etag: Some("\"stable\"".into()),
    }
}

fn headers(range: &str, etag: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert("content-range", HeaderValue::from_str(range).unwrap());
    headers.insert("etag", HeaderValue::from_str(etag).unwrap());
    headers
}

#[test]
fn validates_range_validator_length_and_complete_416_without_appending_incompatible_bytes() {
    let checkpoint = checkpoint(40);

    assert_eq!(
        decide(
            &checkpoint,
            StatusCode::PARTIAL_CONTENT,
            &headers("bytes 40-99/100", "\"stable\""),
            40
        ),
        ResumeDecision::Append {
            offset: 40,
            total: 100,
            etag: "\"stable\"".into()
        }
    );

    for (status, range, etag, length) in [
        (StatusCode::OK, "bytes 40-99/100", "\"stable\"", 40),
        (
            StatusCode::PARTIAL_CONTENT,
            "bytes 0-99/100",
            "\"stable\"",
            40,
        ),
        (
            StatusCode::PARTIAL_CONTENT,
            "bytes 40-98/100",
            "\"stable\"",
            40,
        ),
        (
            StatusCode::PARTIAL_CONTENT,
            "bytes 40-99/101",
            "\"stable\"",
            40,
        ),
        (
            StatusCode::PARTIAL_CONTENT,
            "bytes 40-99/100",
            "W/\"stable\"",
            40,
        ),
        (
            StatusCode::PARTIAL_CONTENT,
            "bytes 40-99/100",
            "\"changed\"",
            40,
        ),
        (StatusCode::PARTIAL_CONTENT, "bytes 40-99/100", "", 40),
        (
            StatusCode::PARTIAL_CONTENT,
            "bytes 40-99/100",
            "\"stable\"",
            39,
        ),
        (
            StatusCode::RANGE_NOT_SATISFIABLE,
            "bytes */100",
            "\"stable\"",
            40,
        ),
    ] {
        assert!(matches!(
            decide(&checkpoint, status, &headers(range, etag), length),
            ResumeDecision::RestartRequired { .. }
        ));
    }

    let complete = super_checkpoint();
    assert_eq!(
        decide(
            &complete,
            StatusCode::RANGE_NOT_SATISFIABLE,
            &headers("bytes */100", "\"stable\""),
            100
        ),
        ResumeDecision::AlreadyComplete
    );
    assert!(matches!(
        decide(
            &complete,
            StatusCode::RANGE_NOT_SATISFIABLE,
            &headers("bytes */101", "\"stable\""),
            100
        ),
        ResumeDecision::RestartRequired { .. }
    ));
}

fn super_checkpoint() -> ResumeCheckpoint {
    checkpoint(100)
}
