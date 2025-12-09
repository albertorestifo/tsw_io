use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_shell::ShellExt;
use std::time::Duration;

const BACKEND_PORT: u16 = 4000;
const MAX_RETRIES: u32 = 60;
const RETRY_DELAY_MS: u64 = 1000;

/// Check if the backend is ready by making an HTTP request
fn check_backend_ready() -> bool {
    let url = format!("http://localhost:{}", BACKEND_PORT);
    reqwest::blocking::get(&url).is_ok()
}

/// Wait for the backend to become ready
fn wait_for_backend() -> bool {
    for attempt in 1..=MAX_RETRIES {
        if check_backend_ready() {
            println!("Backend ready after {} attempts", attempt);
            return true;
        }
        println!("Waiting for backend... attempt {}/{}", attempt, MAX_RETRIES);
        std::thread::sleep(Duration::from_millis(RETRY_DELAY_MS));
    }
    false
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let handle = app.handle().clone();

            // Spawn the Elixir backend as a sidecar process
            let sidecar = handle
                .shell()
                .sidecar("tsw_io_backend")
                .expect("Failed to create sidecar command");

            let (mut _rx, _child) = sidecar
                .env("PORT", BACKEND_PORT.to_string())
                .env("MIX_ENV", "prod")
                .env("BURRITO", "1")
                .spawn()
                .expect("Failed to spawn backend sidecar");

            // Wait for backend to be ready in a separate thread
            std::thread::spawn(move || {
                if wait_for_backend() {
                    // Create the main window once backend is ready
                    let url = format!("http://localhost:{}", BACKEND_PORT);

                    WebviewWindowBuilder::new(
                        &handle,
                        "main",
                        WebviewUrl::External(url.parse().unwrap()),
                    )
                    .title("TWS IO")
                    .inner_size(1200.0, 800.0)
                    .min_inner_size(800.0, 600.0)
                    .build()
                    .expect("Failed to create window");
                } else {
                    eprintln!("Backend failed to start after {} attempts", MAX_RETRIES);
                    std::process::exit(1);
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Error while running TWS IO");
}
