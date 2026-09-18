//go:build windows

package main

import ole "github.com/go-ole/go-ole"

// initWindowsCOM khởi tạo COM apartment cho goroutine chính.
// SAPI SpVoice sinh sau đó sẽ dùng chung apartment này (MTA đủ an toàn
// vì mọi lời gọi synth đều tuần tự qua mutex của pipeline).
func initWindowsCOM() {
	_ = ole.CoInitializeEx(0, ole.COINIT_MULTITHREADED)
}

func uninitWindowsCOM() {
	ole.CoUninitialize()
}
