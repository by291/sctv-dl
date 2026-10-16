use reqwest::Url;
use serde::Serialize;
use serde_json::Value;

use crate::error::{AppError, Result};

#[derive(Debug, Serialize)]
pub struct Programme {
    pub id: String,
    pub name: String,
    pub cover: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ProgrammeDate {
    pub id: String,
    pub date: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgrammeContent {
    pub id: String,
    pub title: String,
    pub cover: Option<String>,
    pub video: Option<String>,
    pub smooth_video: Option<String>,
    pub published_at: Option<String>,
}

pub fn validate_id(id: &str) -> Result<()> {
    if id.is_empty() || !id.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(AppError::new("invalid-input", "节目 ID 无效"));
    }
    Ok(())
}

fn id(value: &Value) -> Result<String> {
    if let Some(id) = value.as_str().filter(|id| validate_id(id).is_ok()) {
        return Ok(id.to_owned());
    }
    if let Some(number) = value.as_f64().filter(|number| {
        *number >= 0.0 && *number <= 9_007_199_254_740_991.0 && number.fract() == 0.0
    }) {
        return Ok((number as u64).to_string());
    }
    Err(AppError::new("upstream", "接口 ID 无效或超出安全整数范围"))
}

fn url(value: &Value, base: &str) -> Option<String> {
    // Match ECMAScript String.trim used by the Node normalizer, including BOM and excluding NEL.
    let text = value.as_str()?.trim_matches(|character: char| {
        matches!(character,
            '\u{0009}'..='\u{000d}' | '\u{0020}' | '\u{00a0}' | '\u{1680}' |
            '\u{2000}'..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}' |
            '\u{205f}' | '\u{3000}' | '\u{feff}'
        )
    });
    if text.is_empty() {
        return None;
    }
    let parsed = Url::parse(base).ok()?.join(text).ok()?;
    matches!(parsed.scheme(), "http" | "https").then(|| parsed.to_string())
}

pub fn programme(value: &Value) -> Result<Programme> {
    Ok(Programme {
        id: id(&value["id"])?,
        name: value["name"].as_str().unwrap_or("未命名栏目").to_owned(),
        cover: url(&value["cover"], "https://kscgc.sctv.com/"),
    })
}

pub fn date(value: &Value) -> Result<ProgrammeDate> {
    let id = id(&value["id"])?;
    let date = value["date"]
        .as_str()
        .filter(|date| valid_date(date))
        .ok_or_else(|| AppError::new("upstream", "接口日期数据格式异常"))?;
    Ok(ProgrammeDate {
        id,
        date: date.to_owned(),
    })
}

fn valid_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || !bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit())
    {
        return false;
    }
    let year: u16 = value[..4].parse().unwrap();
    let month: usize = value[5..7].parse().unwrap();
    let day: u8 = value[8..].parse().unwrap();
    let leap = year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    (1..=12).contains(&month) && day > 0 && day <= days[month - 1]
}

pub fn content(value: &Value) -> Result<ProgrammeContent> {
    Ok(ProgrammeContent {
        id: id(&value["id"])?,
        title: value["title"].as_str().unwrap_or("未命名节目").to_owned(),
        cover: url(&value["cover"], "https://kscgc.sctv.com/"),
        video: url(&value["video"], "https://fscgc.scgchc.com/"),
        smooth_video: url(&value["videoStandard"], "https://fscgc.scgchc.com/"),
        published_at: value["pubTime"].as_str().map(str::to_owned),
    })
}

pub fn rows(value: &Value) -> Result<&Vec<Value>> {
    value
        .as_array()
        .ok_or_else(|| AppError::new("upstream", "接口数据格式异常"))
}
