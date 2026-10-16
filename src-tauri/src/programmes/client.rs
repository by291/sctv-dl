use reqwest::{
    Client, Url,
    header::{HeaderMap, HeaderValue},
};
use serde_json::Value;
use std::{collections::BTreeMap, time::Duration};

use super::models::{self, Programme, ProgrammeContent, ProgrammeDate};
use crate::error::{AppError, Result};

#[derive(Clone, Copy)]
pub struct Deadlines {
    pub headers: Duration,
    pub idle: Duration,
}
impl Default for Deadlines {
    fn default() -> Self {
        Self {
            headers: Duration::from_secs(20),
            idle: Duration::from_secs(30),
        }
    }
}

pub struct ProgrammeService {
    client: Client,
    origin: Url,
    headers: HeaderMap,
    deadlines: Deadlines,
}

impl ProgrammeService {
    pub fn production(device_id: String) -> Result<Self> {
        Self::new("https://gw.scgchc.com", device_id, Deadlines::default())
    }

    pub fn new(origin: &str, device_id: String, deadlines: Deadlines) -> Result<Self> {
        let origin =
            Url::parse(origin).map_err(|_| AppError::new("invalid-input", "节目服务地址无效"))?;
        let mut headers = HeaderMap::new();
        for (name, value) in [
            ("accept", "application/json"),
            ("accept-encoding", "gzip"),
            ("user-agent", "okhttp/4.12.0"),
            ("userid", ""),
            ("authorization", ""),
            ("devicebrand", "google"),
            ("devicemodel", "Pixel 8"),
            ("systemversion", "14"),
            ("devicetype", "android"),
            ("appversion", "9.6.1.5"),
            ("captchaid", ""),
        ] {
            headers.insert(name, HeaderValue::from_static(value));
        }
        headers.insert(
            "deviceid",
            HeaderValue::from_str(&device_id)
                .map_err(|_| AppError::new("invalid-input", "设备标识无效"))?,
        );
        let client = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .read_timeout(deadlines.idle)
            .gzip(true)
            .build()
            .map_err(transport_error)?;
        Ok(Self {
            client,
            origin,
            headers,
            deadlines,
        })
    }

    async fn request(&self, path: &str) -> Result<Value> {
        let url = self
            .origin
            .join(path)
            .map_err(|_| AppError::new("invalid-input", "节目服务地址无效"))?;
        let response = tokio::time::timeout(
            self.deadlines.headers,
            self.client.get(url).headers(self.headers.clone()).send(),
        )
        .await
        .map_err(|_| AppError::new("timeout", "节目服务响应超时，请稍后重试"))?
        .map_err(transport_error)?;
        if !response.status().is_success() {
            return Err(AppError::new(
                "upstream",
                format!(
                    "请求失败（HTTP {}），请稍后重试",
                    response.status().as_u16()
                ),
            ));
        }
        let envelope: Value = response.json().await.map_err(transport_error)?;
        let status = envelope
            .get("rs")
            .and_then(Value::as_f64)
            .ok_or_else(|| AppError::new("upstream", "接口数据格式异常"))?;
        if status != 200.0 {
            return Err(AppError::new(
                "upstream",
                envelope["error"].as_str().unwrap_or("节目服务暂时不可用"),
            ));
        }
        Ok(envelope["data"].clone())
    }

    pub async fn programmes(&self) -> Result<Vec<Programme>> {
        let data = self.request("/app/v1/programs?page=0&size=100").await?;
        models::rows(&data["records"])?
            .iter()
            .map(models::programme)
            .collect()
    }

    pub async fn dates(&self, programme_id: &str) -> Result<Vec<ProgrammeDate>> {
        models::validate_id(programme_id)?;
        let data = self
            .request(&format!("/app/v1/programs/{programme_id}/dates/list"))
            .await?;
        let mut dates = BTreeMap::new();
        // The last upstream record for a broadcast date wins, matching the Web service.
        for row in models::rows(&data)? {
            let row = models::date(row)?;
            dates.insert(row.date.clone(), row);
        }
        Ok(dates.into_values().rev().collect())
    }

    pub async fn contents(
        &self,
        programme_id: &str,
        date_id: &str,
    ) -> Result<Vec<ProgrammeContent>> {
        models::validate_id(programme_id)?;
        models::validate_id(date_id)?;
        let data = self
            .request(&format!(
                "/app/v1/programs/{programme_id}/dates/{date_id}/contents/list"
            ))
            .await?;
        models::rows(&data)?.iter().map(models::content).collect()
    }
}

fn transport_error(error: reqwest::Error) -> AppError {
    if error.is_timeout() {
        AppError::new("timeout", "节目服务响应超时，请稍后重试")
    } else if error.is_decode() {
        AppError::new("upstream", "接口数据不是有效 JSON，请检查节目服务")
    } else {
        AppError::new("upstream", "无法连接节目服务，请稍后重试")
    }
}
