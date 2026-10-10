package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestNoCrashWindow(t *testing.T) {
	sideeye, err := exec.LookPath("sideeye")
	if err != nil {
		t.Fatal("sideeye is not on PATH")
	}
	if out, err := exec.Command("go", "build", "-o", "bin/keytool", ".").CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	dir := t.TempDir()
	report := filepath.Join(dir, "report.json")
	out, err := exec.Command(sideeye, "explore", "--config", "sideeye.toml",
		"--observe", "supervised", "--oracle", "/usr/bin/strace",
		"--work", filepath.Join(dir, "work"), "--json", report).CombinedOutput()
	if err != nil {
		t.Fatalf("sideeye: %v\n%s", err, out)
	}
	b, err := os.ReadFile(report)
	if err != nil {
		t.Fatal(err)
	}
	var r struct {
		Verdict        string `json:"verdict"`
		OracleVerified bool   `json:"oracle_verified"`
	}
	if err := json.Unmarshal(b, &r); err != nil {
		t.Fatal(err)
	}
	if r.Verdict != "PASS" || !r.OracleVerified {
		t.Fatalf("wanted a verified PASS:\n%s", b)
	}
}
