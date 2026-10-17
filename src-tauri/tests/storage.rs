use sctv_dl_desktop_lib::storage::{read_json, write_json_atomic};
use serde::Serialize;
use serde_json::{Value, json};

#[test]
fn atomic_replacement_round_trips_and_bounds_reads() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("state.json");
    assert_eq!(read_json::<Value>(&path, 1024).unwrap(), None);
    write_json_atomic(&path, &json!({"revision": 1})).unwrap();
    write_json_atomic(&path, &json!({"revision": 2})).unwrap();
    assert_eq!(
        read_json::<Value>(&path, 1024).unwrap(),
        Some(json!({"revision": 2}))
    );
    assert!(read_json::<Value>(&path, 2).is_err());
    std::fs::write(&path, b"{broken").unwrap();
    assert!(read_json::<Value>(&path, 1024).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), b"{broken");
}

struct Unserializable;
impl Serialize for Unserializable {
    fn serialize<S: serde::Serializer>(&self, _: S) -> Result<S::Ok, S::Error> {
        Err(serde::ser::Error::custom("injected serialization failure"))
    }
}

#[test]
fn failed_write_preserves_previous_bytes_and_removes_temporary_files() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("state.json");
    std::fs::write(&path, b"{\"previous\":true}").unwrap();
    assert!(write_json_atomic(&path, &Unserializable).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), b"{\"previous\":true}");
    assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    let directory = root.path().join("directory.json");
    std::fs::create_dir(&directory).unwrap();
    std::fs::write(directory.join("owned"), b"preserve").unwrap();
    assert!(write_json_atomic(&directory, &json!({})).is_err());
    assert_eq!(std::fs::read(directory.join("owned")).unwrap(), b"preserve");
    assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 2);
}
