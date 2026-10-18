use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{MAX_BYTES, models::BrowseState};

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct Entry {
    pub(super) file: String,
    pub(super) bytes: usize,
    pub(super) accessed: u64,
}

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct Manifest {
    pub(super) version: u32,
    pub(super) epoch: String,
    pub(super) clock: u64,
    pub(super) entries: BTreeMap<String, Entry>,
    pub(super) browse: BTreeMap<String, BrowseState>,
}

impl Default for Manifest {
    fn default() -> Self {
        Self {
            version: 1,
            epoch: Uuid::new_v4().to_string(),
            clock: 0,
            entries: BTreeMap::new(),
            browse: BTreeMap::new(),
        }
    }
}

impl Manifest {
    pub(super) fn valid(&self) -> bool {
        self.version == 1
            && Uuid::parse_str(&self.epoch).is_ok()
            && self.entries.len() <= 200
            && self
                .entries
                .values()
                .map(|entry| entry.bytes as u128)
                .sum::<u128>()
                <= MAX_BYTES as u128
            && self.browse.len() <= 100
            && self
                .browse
                .iter()
                .all(|(key, value)| key == &value.programme_id && value.validate().is_ok())
            && self.entries.values().all(|entry| {
                entry
                    .file
                    .strip_suffix(".json")
                    .is_some_and(|stem| Uuid::parse_str(stem).is_ok())
            })
    }

    pub(super) fn touch(&mut self, key: &str) {
        self.clock = self.clock.saturating_add(1);

        if let Some(entry) = self.entries.get_mut(key) {
            entry.accessed = self.clock;
        }
    }

    pub(super) fn insert_snapshot(&mut self, key: String, file: String, bytes: usize) {
        self.clock = self.clock.saturating_add(1);
        self.entries.insert(
            key,
            Entry {
                file,
                bytes,
                accessed: self.clock,
            },
        );

        trim(self);
    }

    pub(super) fn insert_browse(&mut self, value: BrowseState) {
        self.browse.insert(value.programme_id.clone(), value);

        while self.browse.len() > 100 {
            let oldest = self
                .browse
                .iter()
                .min_by(|a, b| a.1.visited_at.cmp(&b.1.visited_at))
                .map(|(key, _)| key.clone())
                .unwrap();

            self.browse.remove(&oldest);
        }
    }
}

fn trim(manifest: &mut Manifest) {
    while manifest.entries.len() > 200
        || manifest
            .entries
            .values()
            .map(|entry| entry.bytes)
            .sum::<usize>()
            > MAX_BYTES
    {
        let oldest = manifest
            .entries
            .iter()
            .min_by_key(|(_, value)| value.accessed)
            .map(|(key, _)| key.clone())
            .unwrap();

        manifest.entries.remove(&oldest);
    }
}
