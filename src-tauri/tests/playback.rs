use axum::{Json, Router, http::Uri};
use sctv_dl_desktop_lib::{
    media::{MediaConfig, PlaybackRequest, PlaybackService, Quality},
    programmes::{Deadlines, ProgrammeService},
};
use serde_json::json;

#[tokio::test]
async fn resolves_domain_references_and_releases_opaque_sessions() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        axum::serve(listener,Router::new().fallback(|uri:Uri|async move {
            Json(json!({"rs":200,"data":if uri.path().contains("contents") {json!([
                {"id":3,"video":"https://fscgc.scgchc.com/a.mp4","videoStandard":"https://fscgc.scgchc.com/b.mp4"},
                {"id":4,"video":"https://fscgc.scgchc.com/a.mp4"},
                {"id":5,"video":"https://external.invalid/a.mp4"}
            ])}else{json!([{"id":2,"date":"2026-10-16"}])}}))
        })).await.unwrap();
    });
    let programme = ProgrammeService::new(&origin, "guest".into(), Deadlines::default()).unwrap();
    let playback = PlaybackService::new(MediaConfig::default()).await.unwrap();
    let request = |id: &str| PlaybackRequest {
        programme_id: "1".into(),
        date_id: "2".into(),
        content_id: id.into(),
        quality: Quality::Smooth,
    };
    let session = playback.open(&programme, request("3")).await.unwrap();
    assert_eq!(session.selected_quality, Quality::Smooth);
    assert_eq!(session.sources.len(), 2);
    assert!(
        session
            .sources
            .iter()
            .all(|source| source.url.starts_with("http://127.0.0.1:"))
    );
    playback.close(&session.id);
    assert_eq!(
        reqwest::get(&session.sources[0].url)
            .await
            .unwrap()
            .status(),
        404
    );
    let fallback = playback.open(&programme, request("4")).await.unwrap();
    assert_eq!(fallback.selected_quality, Quality::Standard);
    assert_eq!(
        playback
            .open(&programme, request("99"))
            .await
            .err()
            .unwrap()
            .code,
        "not-found"
    );
    assert!(playback.open(&programme, request("5")).await.is_err());
    let mut stale = request("3");
    stale.date_id = "99".into();
    assert_eq!(
        playback.open(&programme, stale).await.err().unwrap().code,
        "not-found"
    );
    let mut invalid = request("3");
    invalid.content_id = "../3".into();
    assert_eq!(
        playback.open(&programme, invalid).await.err().unwrap().code,
        "invalid-input"
    );
    assert!(serde_json::from_value::<PlaybackRequest>(json!({"programmeId":"1","dateId":"2","contentId":"3","quality":"standard","url":"https://external.invalid/a.mp4"})).is_err());
    playback.shutdown().await;
    assert!(playback.open(&programme, request("3")).await.is_err());
    server.abort();
}
