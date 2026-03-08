pub mod auth;
pub mod db;
pub mod routes;
pub mod terraform;
pub mod types;

use std::path::PathBuf;

#[derive(Clone)]
pub struct AppState {
    pub db: db::Db,
    pub terraform_dir: PathBuf,
    pub hcloud_token: String,
}
