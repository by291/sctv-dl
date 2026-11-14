use std::time::Duration;

use reqwest::{
    Client, Response, Url,
    header::{HeaderMap, HeaderValue},
};
use serde_json::Value;

use super::models::{self, Programme, ProgrammeContent, ProgrammeDate};
use crate::error::{AppError, ErrorCode, Result};

const MAX_METADATA_BYTES: usize = 2 * 1024 * 1024;

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
    /// Connects to the production metadata host with the desktop installation identity.
    pub fn production(device_id: String) -> Result<Self> {
        Self::new("https://gw.scgchc.com", device_id, Deadlines::default())
    }

    /// Configures the HTTP client and its separate header and idle deadlines.
    pub fn new(origin: &str, device_id: String, deadlines: Deadlines) -> Result<Self> {
        let origin = Url::parse(origin).map_err(|error| {
            AppError::with_source(ErrorCode::InvalidInput, "节目服务地址无效", error)
        })?;
        let headers = guest_headers(&device_id)?;

        let client = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .read_timeout(deadlines.idle)
            .gzip(true)
            .build()
            .map_err(|error| transport_error(error).reported("initialize programme HTTP client"))?;

        Ok(Self {
            client,
            origin,
            headers,
            deadlines,
        })
    }

    async fn request(&self, path: &str) -> Result<Value> {
        let url = self.origin.join(path).map_err(|error| {
            AppError::with_source(ErrorCode::InvalidInput, "节目服务地址无效", error)
        })?;

        let request = self.client.get(url).headers(self.headers.clone());
        let response = tokio::time::timeout(self.deadlines.headers, request.send())
            .await
            .map_err(|error| {
                AppError::with_source(ErrorCode::Timeout, "节目服务响应超时，请稍后重试", error)
                    .reported("request programme response headers")
            })?
            .map_err(|error| {
                transport_error(error).reported("request programme response headers")
            })?;

        if !response.status().is_success() {
            return Err(AppError::new(
                ErrorCode::Upstream,
                format!(
                    "请求失败（HTTP {}），请稍后重试",
                    response.status().as_u16()
                ),
            ));
        }

        let mut envelope = read_metadata(response).await?;
        let status = envelope
            .get("rs")
            .and_then(Value::as_f64)
            .ok_or_else(|| AppError::new(ErrorCode::Upstream, "接口数据格式异常"))?;
        if status != 200.0 {
            return Err(AppError::new(
                ErrorCode::Upstream,
                envelope["error"].as_str().unwrap_or("节目服务暂时不可用"),
            ));
        }

        Ok(envelope["data"].take())
    }

    /// Lists programmes with normalized names, IDs, and artwork URLs.
    pub async fn programmes(&self) -> Result<Vec<Programme>> {
        let catalogue = self.request("/app/v1/programs?page=0&size=100").await?;

        models::rows(&catalogue["records"])?
            .iter()
            .map(models::programme)
            .collect()
    }

    /// Lists the available broadcast dates for a programme.
    pub async fn dates(&self, programme_id: &str) -> Result<Vec<ProgrammeDate>> {
        models::validate_id(programme_id)?;

        let dates = self
            .request(&format!("/app/v1/programs/{programme_id}/dates/list"))
            .await?;

        models::dates(&dates)
    }

    /// Lists normalized content for a specific programme broadcast.
    pub async fn contents(
        &self,
        programme_id: &str,
        date_id: &str,
    ) -> Result<Vec<ProgrammeContent>> {
        models::validate_id(programme_id)?;
        models::validate_id(date_id)?;

        let path = format!("/app/v1/programs/{programme_id}/dates/{date_id}/contents/list");
        let contents = self.request(&path).await?;

        models::rows(&contents)?
            .iter()
            .map(models::content)
            .collect()
    }
}

async fn read_metadata(mut response: Response) -> Result<Value> {
    let mut body = Vec::new();

    // Count decoded chunks because gzip and chunked responses need not declare a usable length.
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| transport_error(error).reported("read programme response body"))?
    {
        if chunk.len() > MAX_METADATA_BYTES - body.len() {
            return Err(AppError::new(ErrorCode::Upstream, "节目服务响应数据过大")
                .reported("read programme response body"));
        }

        body.extend_from_slice(&chunk);
    }

    serde_json::from_slice(&body).map_err(|error| {
        AppError::with_source(
            ErrorCode::Upstream,
            "接口数据不是有效 JSON，请检查节目服务",
            error,
        )
        .reported("decode programme response body")
    })
}

fn guest_headers(device_id: &str) -> Result<HeaderMap> {
    let mut headers = HeaderMap::new();
    for (name, value) in [
        ("accept", "application/json"),
        ("accept-encoding", "gzip"),
        ("user-agent", crate::upstream::USER_AGENT),
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
        HeaderValue::from_str(device_id).map_err(|error| {
            AppError::with_source(ErrorCode::InvalidInput, "设备标识无效", error)
        })?,
    );

    Ok(headers)
}

fn transport_error(error: reqwest::Error) -> AppError {
    let (code, message) = if error.is_timeout() {
        (ErrorCode::Timeout, "节目服务响应超时，请稍后重试")
    } else if error.is_decode() {
        (ErrorCode::Upstream, "接口数据不是有效 JSON，请检查节目服务")
    } else {
        (ErrorCode::Upstream, "无法连接节目服务，请稍后重试")
    };

    AppError::with_source(code, message, error.without_url())
}
