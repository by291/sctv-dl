use super::{ProgrammeContent, ProgrammeDate, ProgrammeService, validate_id};
use crate::error::{AppError, ErrorCode, Result};

pub(crate) struct Broadcast {
    pub date: ProgrammeDate,
    pub contents: Vec<ProgrammeContent>,
}

impl ProgrammeService {
    pub(crate) async fn broadcast(&self, programme_id: &str, date_id: &str) -> Result<Broadcast> {
        validate_id(programme_id)?;
        validate_id(date_id)?;

        let date = self
            .dates(programme_id)
            .await?
            .into_iter()
            .find(|date| date.id == date_id)
            .ok_or_else(|| AppError::new(ErrorCode::NotFound, "播出日期已不可用，请刷新后重试"))?;
        let contents = self.contents(programme_id, date_id).await?;

        Ok(Broadcast { date, contents })
    }
}
