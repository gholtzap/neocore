use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use crate::AppState;

pub fn hash_api_key(key: &str) -> String {
    let mut hasher = DefaultHasher::new();
    key.hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

pub async fn auth_middleware(
    State(state): State<AppState>,
    mut req: Request,
    next: Next,
) -> Result<Response, (StatusCode, String)> {
    let auth_header = req
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or((StatusCode::UNAUTHORIZED, "missing authorization header".to_string()))?;

    let api_key = auth_header
        .strip_prefix("Bearer ")
        .ok_or((StatusCode::UNAUTHORIZED, "invalid authorization format".to_string()))?;

    let key_hash = hash_api_key(api_key);

    let tenant = state
        .db
        .get_tenant_by_key_hash(&key_hash)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
        .ok_or((StatusCode::UNAUTHORIZED, "invalid api key".to_string()))?;

    req.extensions_mut().insert(tenant);

    Ok(next.run(req).await)
}

