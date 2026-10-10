use std::{env, fs, io::Write, path::PathBuf};

fn state() -> PathBuf { PathBuf::from("/tmp/keytool-rs-state") }

fn write_key(body: &str) {
    let path = state().join("key.json");
    if cfg!(feature = "buggy") {
        // truncate in place, then write: a kill between the two leaves 0 bytes
        let mut f = fs::File::create(&path).unwrap();
        f.write_all(body.as_bytes()).unwrap();
        f.sync_all().unwrap();
    } else {
        let tmp = state().join("key.json.tmp");
        let mut f = fs::File::create(&tmp).unwrap();
        f.write_all(body.as_bytes()).unwrap();
        f.sync_all().unwrap();
        fs::rename(&tmp, &path).unwrap();
    }
}

fn main() {
    match env::args().nth(1).as_deref() {
        Some("init") => { fs::create_dir_all(state()).unwrap(); write_key("{\"key\":\"one\"}\n"); }
        Some("rotate") => write_key("{\"key\":\"two\"}\n"),
        _ => std::process::exit(2),
    }
}
