use std::process::Command;

#[test]
fn no_crash_window() {
    let dir = std::env::temp_dir().join(format!("sideeye-{}-no_crash_window", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let report = dir.join("report.json");
    let out = Command::new("sideeye")
        .args(["explore", "--config", concat!(env!("CARGO_MANIFEST_DIR"), "/sideeye.toml")])
        .args(["--oracle", "/usr/bin/strace"])
        .arg("--work").arg(dir.join("work"))
        .arg("--json").arg(&report)
        .output()
        .expect("sideeye is not on PATH");
    let text = String::from_utf8_lossy(&out.stdout);
    assert_eq!(out.status.code(), Some(0), "{text}{}", String::from_utf8_lossy(&out.stderr));
    let json = std::fs::read_to_string(&report).unwrap();
    let flat: String = json.chars().filter(|c| !c.is_whitespace()).collect();
    assert!(flat.contains("\"verdict\":\"PASS\"") && flat.contains("\"oracle_verified\":true"), "{json}");
}
