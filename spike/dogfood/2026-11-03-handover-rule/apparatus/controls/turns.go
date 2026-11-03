// The control the rule must judge: two goroutines take turns through channels, each writing one file
// and handing the turn over, ten times; nothing writes until the turn is its own.
package main

import "os"

func main() {
	ping, pong, done := make(chan int), make(chan int), make(chan struct{})
	write := func(n string, i int) {
		p := os.Args[1] + "/" + n
		if err := os.WriteFile(p+".tmp", []byte{byte('0' + i)}, 0o644); err != nil {
			os.Exit(2)
		}
		if err := os.Rename(p+".tmp", p); err != nil {
			os.Exit(2)
		}
	}
	go func() {
		for i := range pong {
			write("b", i)
			if i == 9 {
				close(done)
				return
			}
			ping <- i + 1
		}
	}()
	go func() { ping <- 0 }()
	for i := range ping {
		write("a", i)
		pong <- i
		if i == 9 {
			break
		}
	}
	<-done
}
