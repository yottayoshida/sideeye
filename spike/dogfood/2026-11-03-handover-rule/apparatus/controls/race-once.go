// The control a rule that only looks where the earlier writer is would pass: two goroutines released
// together each write one file once, and the main goroutine waits for both. A write that waited
// behind the other's for the engine has its writer asleep in the runtime by the time it is read.
package main

import (
	"os"
	"sync"
)

func main() {
	var wg sync.WaitGroup
	start := make(chan struct{})
	for _, name := range []string{"x", "y"} {
		wg.Add(1)
		go func(n string) {
			defer wg.Done()
			<-start
			if err := os.WriteFile(os.Args[1]+"/"+n, []byte(n+"\n"), 0o644); err != nil {
				os.Exit(2)
			}
		}(name)
	}
	close(start)
	wg.Wait()
}
