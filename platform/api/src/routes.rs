use axum::{
    extract::{Path, State},
    http::StatusCode,
    Extension, Json,
};
use chrono::Utc;
use uuid::Uuid;

use crate::types::*;
use crate::AppState;


pub async fn create_core(
    State(state): State<AppState>,
    Extension(tenant): Extension<Tenant>,
    Json(req): Json<CreateCoreRequest>,
) -> Result<(StatusCode, Json<CoreResponse>), (StatusCode, String)> {
    let server_size = req.server_size.unwrap_or(ServerSize::Small);
    let location = req.location.unwrap_or_else(|| "nbg1".to_string());
    let mcc = req.mcc.unwrap_or_else(|| "999".to_string());
    let mnc = req.mnc.unwrap_or_else(|| "70".to_string());

    let core = Core {
        id: Uuid::new_v4().to_string(),
        tenant_id: tenant.id.clone(),
        status: CoreStatus::Provisioning,
        server_type: server_size.to_hcloud_type().to_string(),
        server_size,
        hcloud_server_id: None,
        public_ip: None,
        amf_endpoint: None,
        upf_endpoint: None,
        web_ui_url: None,
        location: location.clone(),
        mcc: mcc.clone(),
        mnc: mnc.clone(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        destroyed_at: None,
    };

    state
        .db
        .insert_core(&core)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let response = CoreResponse::from(core.clone());
    let core_id = core.id.clone();
    let tenant_name = tenant.name.clone();
    let server_type = core.server_type.clone();
    let db = state.db.clone();
    let tf_dir = state.terraform_dir.clone();
    let hcloud_token = state.hcloud_token.clone();

    tokio::task::spawn_blocking(move || {
        let vars = vec![
            ("hcloud_token", hcloud_token.as_str()),
            ("tenant_id", core_id.as_str()),
            ("tenant_name", tenant_name.as_str()),
            ("server_type", server_type.as_str()),
            ("location", location.as_str()),
            ("mcc", mcc.as_str()),
            ("mnc", mnc.as_str()),
        ];

        let rt = tokio::runtime::Handle::current();
        match crate::terraform::apply(&tf_dir, &core_id, &vars) {
            Ok(result) => {
                rt.block_on(async {
                    let _ = db
                        .update_core_status(
                            &core_id,
                            CoreStatus::Running,
                            Some(&result.public_ip),
                            Some(result.server_id),
                        )
                        .await;
                });
                tracing::info!(core_id = %core_id, ip = %result.public_ip, "core provisioned");
            }
            Err(e) => {
                rt.block_on(async {
                    let _ = db.update_core_status(&core_id, CoreStatus::Error, None, None).await;
                });
                tracing::error!(core_id = %core_id, error = %e, "terraform apply failed");
            }
        }
    });

    Ok((StatusCode::CREATED, Json(response)))
}

pub async fn get_core(
    State(state): State<AppState>,
    Extension(tenant): Extension<Tenant>,
    Path(id): Path<String>,
) -> Result<Json<CoreResponse>, (StatusCode, String)> {
    let core = state
        .db
        .get_core(&id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
        .ok_or((StatusCode::NOT_FOUND, "core not found".to_string()))?;

    if core.tenant_id != tenant.id {
        return Err((StatusCode::NOT_FOUND, "core not found".to_string()));
    }

    Ok(Json(CoreResponse::from(core)))
}

pub async fn list_cores(
    State(state): State<AppState>,
    Extension(tenant): Extension<Tenant>,
) -> Result<Json<Vec<CoreResponse>>, (StatusCode, String)> {
    let cores = state
        .db
        .get_cores_by_tenant(&tenant.id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(cores.into_iter().map(CoreResponse::from).collect()))
}

pub async fn delete_core(
    State(state): State<AppState>,
    Extension(tenant): Extension<Tenant>,
    Path(id): Path<String>,
) -> Result<StatusCode, (StatusCode, String)> {
    let core = state
        .db
        .get_core(&id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
        .ok_or((StatusCode::NOT_FOUND, "core not found".to_string()))?;

    if core.tenant_id != tenant.id {
        return Err((StatusCode::NOT_FOUND, "core not found".to_string()));
    }

    if core.status == CoreStatus::Stopped {
        return Err((StatusCode::BAD_REQUEST, "core already stopped".to_string()));
    }

    state
        .db
        .update_core_status(&id, CoreStatus::Stopping, None, None)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let db = state.db.clone();
    let tf_dir = state.terraform_dir.clone();
    let core_id = id.clone();

    tokio::task::spawn_blocking(move || {
        let rt = tokio::runtime::Handle::current();
        match crate::terraform::destroy(&tf_dir, &core_id) {
            Ok(()) => {
                rt.block_on(async {
                    let _ = db.mark_core_destroyed(&core_id).await;
                });
                tracing::info!(core_id = %core_id, "core destroyed");
            }
            Err(e) => {
                rt.block_on(async {
                    let _ = db.update_core_status(&core_id, CoreStatus::Error, None, None).await;
                });
                tracing::error!(core_id = %core_id, error = %e, "terraform destroy failed");
            }
        }
    });

    Ok(StatusCode::ACCEPTED)
}

pub async fn add_subscriber(
    State(state): State<AppState>,
    Extension(tenant): Extension<Tenant>,
    Path(id): Path<String>,
    Json(req): Json<AddSubscriberRequest>,
) -> Result<(StatusCode, Json<Subscriber>), (StatusCode, String)> {
    let core = state
        .db
        .get_core(&id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
        .ok_or((StatusCode::NOT_FOUND, "core not found".to_string()))?;

    if core.tenant_id != tenant.id {
        return Err((StatusCode::NOT_FOUND, "core not found".to_string()));
    }

    if core.status != CoreStatus::Running {
        return Err((StatusCode::BAD_REQUEST, "core is not running".to_string()));
    }

    let sub = Subscriber {
        imsi: req.imsi,
        key: req.key,
        opc: req.opc,
        msisdn: req.msisdn,
        core_id: id,
        created_at: Utc::now(),
    };

    state
        .db
        .insert_subscriber(&sub)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok((StatusCode::CREATED, Json(sub)))
}

pub async fn get_usage(
    State(state): State<AppState>,
    Extension(tenant): Extension<Tenant>,
) -> Result<Json<Vec<UsageRecord>>, (StatusCode, String)> {
    state
        .db
        .get_usage_by_tenant(&tenant.id)
        .await
        .map(Json)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
}
