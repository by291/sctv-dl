use sctv_dl_desktop_lib::media::{MediaConfig, MediaServer, Quality};

#[tokio::test]
async fn local_handles_support_head_ranges_restrictions_and_explicit_session_close() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("clip.mp4");
    std::fs::write(&path, b"0123456789").unwrap();
    let server = MediaServer::bind(MediaConfig::default()).await.unwrap();
    let session = server
        .open_local(
            "task".into(),
            Quality::Standard,
            std::fs::File::open(&path).unwrap(),
        )
        .unwrap();
    let url = &session.sources[0].url;
    let client = reqwest::Client::new();
    let response = client.head(url).send().await.unwrap();
    assert_eq!(response.status(), 200);
    assert_eq!(response.headers()["content-length"], "10");
    assert!(response.bytes().await.unwrap().is_empty());
    for (range, expected) in [
        ("bytes=0-2", "012"),
        ("bytes=-3", "789"),
        ("bytes=3-3", "3"),
        ("bytes=7-", "789"),
    ] {
        let response = client.get(url).header("Range", range).send().await.unwrap();
        assert_eq!(response.status(), 206);
        assert_eq!(response.text().await.unwrap(), expected);
    }
    let response = client
        .get(url)
        .header("Range", "bytes=10-")
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 416);
    assert_eq!(response.headers()["content-range"], "bytes */10");
    assert_eq!(
        client
            .get(url)
            .header("Host", "evil.invalid")
            .send()
            .await
            .unwrap()
            .status(),
        403
    );
    assert_eq!(
        client
            .get(url)
            .header("Origin", "https://evil.invalid")
            .send()
            .await
            .unwrap()
            .status(),
        403
    );
    server.close(&session.id);
    assert_eq!(client.get(url).send().await.unwrap().status(), 404);
    server.shutdown().await;
}

#[tokio::test]
async fn local_session_keeps_its_opened_file_and_shutdown_stops_backpressured_producers() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("clip.mp4");
    let file = std::fs::File::create(&path).unwrap();
    file.set_len(64 * 1024 * 1024).unwrap();
    drop(file);
    let server = MediaServer::bind(MediaConfig::default()).await.unwrap();
    let session = server
        .open_local(
            "task".into(),
            Quality::Standard,
            std::fs::File::open(&path).unwrap(),
        )
        .unwrap();
    std::fs::rename(&path, root.path().join("original.mp4")).unwrap();
    std::fs::write(&path, b"replacement").unwrap();
    let response = reqwest::Client::new()
        .get(&session.sources[0].url)
        .send()
        .await
        .unwrap();
    assert_eq!(response.content_length(), Some(64 * 1024 * 1024));
    tokio::time::timeout(std::time::Duration::from_secs(2), server.shutdown())
        .await
        .unwrap();
    drop(response);
    assert_eq!(std::fs::read(&path).unwrap(), b"replacement");
}
