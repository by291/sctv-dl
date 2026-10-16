mod client;
mod models;

pub use client::{Deadlines, ProgrammeService};
pub(crate) use models::validate_id;
pub use models::{Programme, ProgrammeContent, ProgrammeDate};
