use axum::{middleware, routing::{delete, get, post}, Router};
use std::path::PathBuf;
use tower_http::cors::CorsLayer;

use platform_api::{auth, db, routes, AppState};

fn env_or_panic(key: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| panic!("{} must be set", key))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let mongodb_uri = env_or_panic("PLATFORM_MONGODB_URI");
    let db = db::Db::new(&mongodb_uri, "platform").await;

    let state = AppState {
        db,
        terraform_dir: PathBuf::from(
            std::env::var("TERRAFORM_DIR").unwrap_or_else(|_| "../terraform".to_string()),
        ),
        hcloud_token: env_or_panic("HCLOUD_TOKEN"),
    };

    let app = Router::new()
        .route("/v1/cores", post(routes::create_core))
        .route("/v1/cores", get(routes::list_cores))
        .route("/v1/cores/{id}", get(routes::get_core))
        .route("/v1/cores/{id}", delete(routes::delete_core))
        .route("/v1/cores/{id}/subscribers", post(routes::add_subscriber))
        .route("/v1/usage", get(routes::get_usage))
        .layer(middleware::from_fn_with_state(state.clone(), auth::auth_middleware))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8090".to_string());
    tracing::info!("platform api listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
