//go:build !windows

// crashdiag_other.go — PATCH FIX41: stub cho nền không phải Windows.
// Trên Windows crashdiag_windows.go gắn SetUnhandledExceptionFilter +
// MiniDumpWriteDump; nơi khác không có cơ chế tương đương cần thiết cho
// quá trình chẩn đoán này nên để trống.

package main

// crashInit no-op trên nền không phải Windows.
func crashInit() {}
