use chrono::Utc;
use uuid::Uuid;

use platform_api::auth::hash_api_key;
use platform_api::db::Db;
use platform_api::types::Tenant;

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: create-tenant <tenant_name>");
        std::process::exit(1);
    }
    let tenant_name = &args[1];

    let mongodb_uri = std::env::var("PLATFORM_MONGODB_URI")
        .unwrap_or_else(|_| {
            eprintln!("PLATFORM_MONGODB_URI must be set");
            std::process::exit(1);
        });

    let db = Db::new(&mongodb_uri, "platform").await;

    let tenant_id = Uuid::new_v4().to_string();
    let api_key = format!("5gc_{}", Uuid::new_v4().to_string().replace("-", ""));
    let api_key_hash = hash_api_key(&api_key);

    let tenant = Tenant {
        id: tenant_id,
        name: tenant_name.clone(),
        api_key_hash,
        created_at: Utc::now(),
    };

    db.insert_tenant(&tenant)
        .await
        .unwrap_or_else(|e| {
            eprintln!("Failed to insert tenant: {}", e);
            std::process::exit(1);
        });

    println!("Tenant created:");
    println!("  ID:      {}", tenant.id);
    println!("  Name:    {}", tenant.name);
    println!("  API Key: {}", api_key);
    println!();
    println!("Save this API key now. It cannot be retrieved later.");
}
