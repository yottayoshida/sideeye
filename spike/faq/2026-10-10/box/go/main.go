package main

import (
	"os"
	"path/filepath"
)

func state() string { return "/tmp/keytool-go-state" }

func writeKey(body string) {
	path := filepath.Join(state(), "key.json")
	if buggy {
		f, err := os.Create(path) // truncates in place
		must(err)
		_, err = f.WriteString(body)
		must(err)
		must(f.Sync())
		must(f.Close())
		return
	}
	tmp := path + ".tmp"
	f, err := os.Create(tmp)
	must(err)
	_, err = f.WriteString(body)
	must(err)
	must(f.Sync())
	must(f.Close())
	must(os.Rename(tmp, path))
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	if len(os.Args) < 2 {
		os.Exit(2)
	}
	switch os.Args[1] {
	case "init":
		must(os.MkdirAll(state(), 0o755))
		writeKey("{\"key\":\"one\"}\n")
	case "rotate":
		writeKey("{\"key\":\"two\"}\n")
	default:
		os.Exit(2)
	}
}
