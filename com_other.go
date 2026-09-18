//go:build !windows

package main

// Trên môi trường khác COM là no-op — chỉ để compile/vet vượt qua.
func initWindowsCOM() {}

func uninitWindowsCOM() {}
