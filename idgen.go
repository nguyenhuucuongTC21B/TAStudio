package main

import (
	"crypto/rand"
	"fmt"
	"time"
)

// genID sinh định danh duy nhất dạng job-<unix>-<random>.
func genID(prefix string) string {
	var b [3]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
	}
	return fmt.Sprintf("%s-%x-%x", prefix, time.Now().Unix(), b)
}
