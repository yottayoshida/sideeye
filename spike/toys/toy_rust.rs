//! The same rotation written the way a Rust program would write it.
//!
//! This one is not a boundary case — it is the stand-in for a real target. Sideeye's
//! users do not write C, and Rust's standard library reaches libc through its own
//! paths: `File::create` may end up in `open64` or `openat`, metadata queries may use
//! `statx`, and none of that is knowable from documentation with enough confidence to
//! design around. Running this under the shim and comparing against the oracle is how
//! the supported operation set gets decided — by measurement, not by expectation.

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;

fn state_dir() -> PathBuf {
    PathBuf::from(env::var("TOY_STATE").unwrap_or_else(|_| "./state".to_string()))
}

fn write_file(path: &PathBuf, content: &str) -> std::io::Result<()> {
    let mut f = fs::File::create(path)?;
    f.write_all(content.as_bytes())?;
    f.sync_all()?;
    Ok(())
}

fn cmd_init() -> std::io::Result<()> {
    fs::create_dir_all(state_dir())?;
    write_file(&state_dir().join("key.json"), "key=1\n")
}

fn cmd_rotate() -> std::io::Result<()> {
    let dir = state_dir();
    let key = dir.join("key.json");
    let tmp = dir.join("key.json.tmp");

    write_file(&tmp, "key=2\n")?;
    // The same delete-before-rename window as the C toy.
    if key.exists() {
        fs::remove_file(&key)?;
    }
    fs::rename(&tmp, &key)?;
    Ok(())
}

fn cmd_doctor() -> ExitCode {
    if state_dir().is_dir() {
        println!("healthy");
    } else {
        println!("unhealthy");
    }
    ExitCode::from(0)
}

fn cmd_load_key() -> ExitCode {
    let key = state_dir().join("key.json");
    let mut buf = String::new();
    match fs::File::open(&key).and_then(|mut f| f.read_to_string(&mut buf)) {
        Ok(_) if buf.starts_with("key=") => {
            print!("{}", buf);
            ExitCode::from(0)
        }
        _ => ExitCode::from(1),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: {} init|rotate|doctor|load-key", args[0]);
        return ExitCode::from(2);
    }
    match args[1].as_str() {
        "init" => match cmd_init() {
            Ok(()) => ExitCode::from(0),
            Err(e) => {
                eprintln!("init failed: {e}");
                ExitCode::from(1)
            }
        },
        "rotate" => match cmd_rotate() {
            Ok(()) => ExitCode::from(0),
            Err(e) => {
                eprintln!("rotate failed: {e}");
                ExitCode::from(1)
            }
        },
        "doctor" => cmd_doctor(),
        "load-key" => cmd_load_key(),
        other => {
            eprintln!("unknown command: {other}");
            ExitCode::from(2)
        }
    }
}
