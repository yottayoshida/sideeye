// The control the rule must refuse: two goroutines write their own eight bytes to the same offset of
// one file fifty times each, yielding between writes, with nothing ordering them.
package main

import (
	"os"
	"runtime"
	"sync"
)

func main() {
	f, err := os.OpenFile(os.Args[1]+"/r", os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		os.Exit(2)
	}
	var wg sync.WaitGroup
	start := make(chan struct{})
	for _, text := range []string{"aaaaaaa\n", "bbbbbbb\n"} {
		wg.Add(1)
		go func(b []byte) {
			defer wg.Done()
			<-start
			for i := 0; i < 50; i++ {
				if _, err := f.WriteAt(b, 0); err != nil {
					os.Exit(2)
				}
				runtime.Gosched()
			}
		}([]byte(text))
	}
	close(start)
	wg.Wait()
}
