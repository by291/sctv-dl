mod support;

use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    error::ErrorCode,
    media::{MediaConfig, PlaybackRequest, PlaybackService, Quality},
    programmes::{Deadlines, ProgrammeService},
};
use serde_json::{Value, json};

struct ProgrammeStub {
    service: ProgrammeService,
    _server: support::Stub,
}

async fn programme_stub(contents: Value) -> ProgrammeStub {
    let router = Router::new().fallback(move |uri: Uri| {
        let contents = contents.clone();
        async move {
            let data = if uri.path().contains("contents") {
                contents
            } else {
                json!([{ "id": 2, "date": "2026-10-16" }])
            };
            Json(json!({ "rs": 200, "data": data }))
        }
    });
    let server = support::serve(router).await;
    let service =
        ProgrammeService::new(&server.origin, "guest".into(), Deadlines::default()).unwrap();

    ProgrammeStub {
        service,
        _server: server,
    }
}

fn request(content_id: &str, quality: Quality) -> PlaybackRequest {
    PlaybackRequest {
        programme_id: "1".into(),
        date_id: "2".into(),
        content_id: content_id.into(),
        quality,
    }
}

#[tokio::test]
async fn resolves_domain_references_and_releases_opaque_sessions() {
    let stub = programme_stub(json!([{
        "id": 3,
        "video": "https://fscgc.scgchc.com/a.mp4",
        "videoStandard": "https://fscgc.scgchc.com/b.mp4"
    }]))
    .await;
    let playback = PlaybackService::new(MediaConfig::default()).await.unwrap();

    let session = playback
        .open(&stub.service, request("3", Quality::Smooth))
        .await
        .unwrap();

    assert_eq!(session.selected_quality, Quality::Smooth);
    assert_eq!(session.sources.len(), 2);
    assert!(
        session
            .sources
            .iter()
            .all(|source| source.url.starts_with("http://127.0.0.1:"))
    );

    playback.close(&session.id);
    playback.close(&session.id);
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .status(),
        404
    );
    playback.shutdown().await;
}

#[tokio::test]
async fn selects_distinct_playback_sources_and_falls_back_to_the_available_quality() {
    let stub = programme_stub(json!([
        { "id": 3, "video": "https://fscgc.scgchc.com/a.mp4" },
        { "id": 4, "videoStandard": "https://fscgc.scgchc.com/b.mp4" },
        {
            "id": 5,
            "video": "https://fscgc.scgchc.com/same.mp4",
            "videoStandard": "https://fscgc.scgchc.com/same.mp4"
        }
    ]))
    .await;
    let playback = PlaybackService::new(MediaConfig::default()).await.unwrap();

    for (id, requested, selected) in [
        ("3", Quality::Smooth, Quality::Standard),
        ("4", Quality::Standard, Quality::Smooth),
        ("5", Quality::Smooth, Quality::Standard),
    ] {
        let session = playback
            .open(&stub.service, request(id, requested))
            .await
            .unwrap();
        assert_eq!(session.selected_quality, selected);
        assert_eq!(session.sources.len(), 1);
        assert_eq!(session.sources[0].quality, selected);
        playback.close(&session.id);
    }

    playback.shutdown().await;
}

#[tokio::test]
async fn rejects_missing_broadcasts_contents_and_disallowed_sources() {
    let stub = programme_stub(json!([
        { "id": 3, "video": "https://external.invalid/a.mp4" },
        { "id": 4 }
    ]))
    .await;
    let playback = PlaybackService::new(MediaConfig::default()).await.unwrap();

    for (id, code) in [
        ("3", ErrorCode::InvalidInput),
        ("4", ErrorCode::NotFound),
        ("99", ErrorCode::NotFound),
    ] {
        let error = playback
            .open(&stub.service, request(id, Quality::Standard))
            .await
            .err()
            .unwrap();
        assert_eq!(error.code, code);
    }

    let mut stale = request("3", Quality::Standard);
    stale.date_id = "99".into();
    assert_eq!(
        playback
            .open(&stub.service, stale)
            .await
            .err()
            .unwrap()
            .code,
        ErrorCode::NotFound
    );

    let invalid = request("../3", Quality::Standard);
    assert_eq!(
        playback
            .open(&stub.service, invalid)
            .await
            .err()
            .unwrap()
            .code,
        ErrorCode::InvalidInput
    );

    playback.shutdown().await;
    assert!(
        playback
            .open(&stub.service, request("3", Quality::Standard))
            .await
            .is_err()
    );
}

#[test]
fn rejects_caller_supplied_media_urls() {
    assert!(
        serde_json::from_value::<PlaybackRequest>(json!({
            "programmeId": "1",
            "dateId": "2",
            "contentId": "3",
            "quality": "standard",
            "url": "https://external.invalid/a.mp4"
        }))
        .is_err()
    );
}
