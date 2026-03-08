use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum CoreStatus {
    Provisioning,
    Running,
    Stopping,
    Stopped,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ServerSize {
    Small,
    Medium,
    Large,
}

impl ServerSize {
    pub fn to_hcloud_type(&self) -> &'static str {
        match self {
            ServerSize::Small => "cx22",
            ServerSize::Medium => "cx32",
            ServerSize::Large => "cx52",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tenant {
    pub id: String,
    pub name: String,
    pub api_key_hash: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Core {
    pub id: String,
    pub tenant_id: String,
    pub status: CoreStatus,
    pub server_size: ServerSize,
    pub server_type: String,
    pub hcloud_server_id: Option<i64>,
    pub public_ip: Option<String>,
    pub amf_endpoint: Option<String>,
    pub upf_endpoint: Option<String>,
    pub web_ui_url: Option<String>,
    pub location: String,
    pub mcc: String,
    pub mnc: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub destroyed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
pub struct CoreResponse {
    pub id: String,
    pub status: CoreStatus,
    pub server_size: ServerSize,
    pub public_ip: Option<String>,
    pub amf_endpoint: Option<String>,
    pub upf_endpoint: Option<String>,
    pub web_ui_url: Option<String>,
    pub location: String,
    pub mcc: String,
    pub mnc: String,
    pub created_at: DateTime<Utc>,
}

impl From<Core> for CoreResponse {
    fn from(c: Core) -> Self {
        Self {
            id: c.id,
            status: c.status,
            server_size: c.server_size,
            public_ip: c.public_ip,
            amf_endpoint: c.amf_endpoint,
            upf_endpoint: c.upf_endpoint,
            web_ui_url: c.web_ui_url,
            location: c.location,
            mcc: c.mcc,
            mnc: c.mnc,
            created_at: c.created_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateCoreRequest {
    pub server_size: Option<ServerSize>,
    pub location: Option<String>,
    pub mcc: Option<String>,
    pub mnc: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Subscriber {
    pub imsi: String,
    pub key: String,
    pub opc: String,
    pub msisdn: Option<String>,
    pub core_id: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct AddSubscriberRequest {
    pub imsi: String,
    pub key: String,
    pub opc: String,
    pub msisdn: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageRecord {
    pub tenant_id: String,
    pub core_id: String,
    pub server_type: String,
    pub hours: f64,
    pub cost_cents: i64,
    pub period_start: DateTime<Utc>,
    pub period_end: DateTime<Utc>,
}
