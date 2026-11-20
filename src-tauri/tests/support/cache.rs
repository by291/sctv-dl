use std::path::Path;

use sctv_dl_desktop_lib::programme_cache::BrowseState;
use serde_json::{Map, json};
use uuid::Uuid;

const SNAPSHOT_CAPACITY: u32 = 200;
const BROWSE_CAPACITY: u32 = 100;

/// Builds a deterministic browse record for the cache capacity boundary.
pub fn browse_state(programme_id: u32) -> BrowseState {
    BrowseState {
        programme_id: programme_id.to_string(),
        date_id: None,
        date: None,
        sort: "asc".into(),
        scroll_y: f64::from(programme_id),
        visited_at: format!(
            "2026-10-17T00:{:02}:{:02}.000Z",
            programme_id / 60,
            programme_id % 60
        ),
    }
}

/// Seeds existing disk records without repeating atomic durability work during test preparation.
pub fn seed_capacity(root: &Path) -> String {
    let epoch = Uuid::new_v4().to_string();
    let directory = root.join(&epoch);
    std::fs::create_dir_all(&directory).unwrap();
    let mut entries = Map::new();

    for programme_id in 0..SNAPSHOT_CAPACITY {
        let snapshot = json!({
            "kind": "dates",
            "programmeId": programme_id.to_string(),
            "items": [],
            "version": 1,
            "revision": format!("fixture-{programme_id}"),
            "fetchedAt": "2026-10-17T00:00:00.000Z"
        });
        let bytes = serde_json::to_vec(&snapshot).unwrap();
        let filename = format!("{}.json", Uuid::new_v4());
        std::fs::write(directory.join(&filename), &bytes).unwrap();
        entries.insert(
            format!("dates:{programme_id}"),
            json!({
                "file": filename,
                "bytes": bytes.len(),
                "accessed": programme_id
            }),
        );
    }

    let mut browse = Map::new();
    for programme_id in 0..BROWSE_CAPACITY {
        let value = serde_json::to_value(browse_state(programme_id)).unwrap();
        browse.insert(programme_id.to_string(), value);
    }

    let manifest = json!({
        "version": 1,
        "epoch": epoch,
        "clock": SNAPSHOT_CAPACITY,
        "entries": entries,
        "browse": browse
    });
    let bytes = serde_json::to_vec(&manifest).unwrap();
    std::fs::write(root.join("manifest.json"), bytes).unwrap();

    epoch
}
