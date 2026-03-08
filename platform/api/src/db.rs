use mongodb::{Client, Collection, Database};
use mongodb::bson::doc;
use crate::types::{Core, Subscriber, Tenant, UsageRecord, CoreStatus};
use chrono::Utc;

#[derive(Clone)]
pub struct Db {
    db: Database,
}

impl Db {
    pub async fn new(uri: &str, db_name: &str) -> Self {
        let client = Client::with_uri_str(uri).await.expect("failed to connect to mongodb");
        let db = client.database(db_name);
        Self { db }
    }

    fn tenants(&self) -> Collection<Tenant> {
        self.db.collection("tenants")
    }

    fn cores(&self) -> Collection<Core> {
        self.db.collection("cores")
    }

    fn subscribers(&self) -> Collection<Subscriber> {
        self.db.collection("subscribers")
    }

    fn usage(&self) -> Collection<UsageRecord> {
        self.db.collection("usage")
    }

    pub async fn insert_tenant(&self, tenant: &Tenant) -> mongodb::error::Result<()> {
        self.tenants().insert_one(tenant).await?;
        Ok(())
    }

    pub async fn get_tenant_by_key_hash(&self, key_hash: &str) -> mongodb::error::Result<Option<Tenant>> {
        self.tenants().find_one(doc! { "api_key_hash": key_hash }).await
    }

    pub async fn insert_core(&self, core: &Core) -> mongodb::error::Result<()> {
        self.cores().insert_one(core).await?;
        Ok(())
    }

    pub async fn get_core(&self, id: &str) -> mongodb::error::Result<Option<Core>> {
        self.cores().find_one(doc! { "id": id }).await
    }

    pub async fn get_cores_by_tenant(&self, tenant_id: &str) -> mongodb::error::Result<Vec<Core>> {
        use futures_util::TryStreamExt;
        let cursor = self.cores().find(doc! { "tenant_id": tenant_id }).await?;
        cursor.try_collect().await
    }

    pub async fn update_core_status(
        &self,
        id: &str,
        status: CoreStatus,
        public_ip: Option<&str>,
        hcloud_server_id: Option<i64>,
    ) -> mongodb::error::Result<()> {
        let mut update = doc! {
            "status": mongodb::bson::to_bson(&status).unwrap(),
            "updated_at": mongodb::bson::to_bson(&Utc::now()).unwrap(),
        };
        if let Some(ip) = public_ip {
            update.insert("public_ip", ip);
            update.insert("amf_endpoint", format!("{}:38412", ip));
            update.insert("upf_endpoint", format!("{}:2152", ip));
            update.insert("web_ui_url", format!("http://{}:3001", ip));
        }
        if let Some(sid) = hcloud_server_id {
            update.insert("hcloud_server_id", sid);
        }
        self.cores()
            .update_one(doc! { "id": id }, doc! { "$set": update })
            .await?;
        Ok(())
    }

    pub async fn mark_core_destroyed(&self, id: &str) -> mongodb::error::Result<()> {
        self.cores()
            .update_one(
                doc! { "id": id },
                doc! { "$set": {
                    "status": mongodb::bson::to_bson(&CoreStatus::Stopped).unwrap(),
                    "destroyed_at": mongodb::bson::to_bson(&Utc::now()).unwrap(),
                    "updated_at": mongodb::bson::to_bson(&Utc::now()).unwrap(),
                }},
            )
            .await?;
        Ok(())
    }

    pub async fn insert_subscriber(&self, sub: &Subscriber) -> mongodb::error::Result<()> {
        self.subscribers().insert_one(sub).await?;
        Ok(())
    }

    pub async fn get_subscribers_by_core(&self, core_id: &str) -> mongodb::error::Result<Vec<Subscriber>> {
        use futures_util::TryStreamExt;
        let cursor = self.subscribers().find(doc! { "core_id": core_id }).await?;
        cursor.try_collect().await
    }

    pub async fn get_usage_by_tenant(&self, tenant_id: &str) -> mongodb::error::Result<Vec<UsageRecord>> {
        use futures_util::TryStreamExt;
        let cursor = self.usage().find(doc! { "tenant_id": tenant_id }).await?;
        cursor.try_collect().await
    }
}
