use std::path::Path;
use std::process::Command;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct TfOutputValue {
    value: serde_json::Value,
}

pub struct TerraformResult {
    pub server_id: i64,
    pub public_ip: String,
}

pub fn apply(
    tf_dir: &Path,
    workspace: &str,
    vars: &[(&str, &str)],
) -> Result<TerraformResult, String> {
    let workspace_dir = tf_dir.join("workspaces").join(workspace);
    std::fs::create_dir_all(&workspace_dir).map_err(|e| e.to_string())?;

    for entry in std::fs::read_dir(tf_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.is_file() {
            let filename = path.file_name().unwrap();
            std::fs::copy(&path, workspace_dir.join(filename)).map_err(|e| e.to_string())?;
        }
    }

    let init = Command::new("terraform")
        .arg("init")
        .arg("-input=false")
        .current_dir(&workspace_dir)
        .output()
        .map_err(|e| format!("terraform init failed: {}", e))?;

    if !init.status.success() {
        return Err(format!(
            "terraform init failed: {}",
            String::from_utf8_lossy(&init.stderr)
        ));
    }

    let mut apply_cmd = Command::new("terraform");
    apply_cmd
        .arg("apply")
        .arg("-auto-approve")
        .arg("-input=false")
        .current_dir(&workspace_dir);

    for (key, val) in vars {
        apply_cmd.arg(format!("-var={}={}", key, val));
    }

    let apply = apply_cmd
        .output()
        .map_err(|e| format!("terraform apply failed: {}", e))?;

    if !apply.status.success() {
        return Err(format!(
            "terraform apply failed: {}",
            String::from_utf8_lossy(&apply.stderr)
        ));
    }

    let output = Command::new("terraform")
        .arg("output")
        .arg("-json")
        .current_dir(&workspace_dir)
        .output()
        .map_err(|e| format!("terraform output failed: {}", e))?;

    let outputs: std::collections::HashMap<String, TfOutputValue> =
        serde_json::from_slice(&output.stdout)
            .map_err(|e| format!("failed to parse terraform output: {}", e))?;

    let server_id = outputs
        .get("server_id")
        .and_then(|v| v.value.as_i64())
        .ok_or("missing server_id output")?;

    let public_ip = outputs
        .get("public_ip")
        .and_then(|v| v.value.as_str().map(|s| s.to_string()))
        .ok_or("missing public_ip output")?;

    Ok(TerraformResult {
        server_id,
        public_ip,
    })
}

pub fn destroy(tf_dir: &Path, workspace: &str) -> Result<(), String> {
    let workspace_dir = tf_dir.join("workspaces").join(workspace);

    if !workspace_dir.exists() {
        return Err(format!("workspace {} does not exist", workspace));
    }

    let destroy = Command::new("terraform")
        .arg("destroy")
        .arg("-auto-approve")
        .arg("-input=false")
        .current_dir(&workspace_dir)
        .output()
        .map_err(|e| format!("terraform destroy failed: {}", e))?;

    if !destroy.status.success() {
        return Err(format!(
            "terraform destroy failed: {}",
            String::from_utf8_lossy(&destroy.stderr)
        ));
    }

    std::fs::remove_dir_all(&workspace_dir).ok();

    Ok(())
}
