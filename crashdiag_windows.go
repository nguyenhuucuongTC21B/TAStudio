//go:build windows

// crashdiag_windows.go — PATCH FIX41: bắt crash native để còn chứng cứ khi
// exe GUI (windowsgui) tắt ngóm mà không in nổi một dòng nào.
//
// Vấn đề: khi app "tự thoát" lúc synth neural, crash diễn ra bên trong code
// C/C++ (ggml / llama.cpp / ONNX Runtime / vieneu core) gọi qua cgo. Build
// GUI không có console, stderr vô hình; hcstudio.log dừng ở dòng cuối cùng
// trước khi rơi vào native — không biết chết ở đâu.
//
// Giải pháp lớp 1 (file này): gắn SetUnhandledExceptionFilter ngay đầu
// main(), filter ghi:
//
//  1. một dòng "[CRASH] unhandled exception · code=0x..." vào hcstudio.log
//     (ghi thẳng file, KHÔNG qua diagf để tránh khoá mutex khi đang crash);
//  2. một minidump đầy đủ ngăn xếp + danh sách module vào
//     %LOCALAPPDATA%\HCStudio\logs\crash-YYYYMMDD-HHMMSS.dmp — mở bằng
//     WinDbg/Visual Studio để xem module+offset của lỗi.
//
// Sau đó trả EXCEPTION_CONTINUE_SEARCH để Windows Error Reporting vẫn ghi
// sự kiện Application/1000 (faulting module + exception code) như thường.
//
// Lưu ý phạm vi: filter này ch unhandled exception "thoát ra ngoài" từ code
// C/C++. Với lỗi mà Go runtime tự xử lý rồi exit(2) (fatal error trong cgo),
// Go in stack vào stderr — dùng HCStudio-debug.exe (build.ps1 -Full giờ tạo
// kèm, subsystem console) để thấy stderr trực tiếp. Hai lớp bổ sung nhau.

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	modKernel32 = syscall.NewLazyDLL("kernel32.dll")
	modDbgHelp  = syscall.NewLazyDLL("dbghelp.dll")

	procSetUnhandledExceptionFilter = modKernel32.NewProc("SetUnhandledExceptionFilter")
	procMiniDumpWriteDump           = modDbgHelp.NewProc("MiniDumpWriteDump")
)

// exceptionRecord — chỉ cần ExceptionCode nằm ở offset 0 theo layout x64.
type exceptionRecord struct {
	ExceptionCode      uint32
	ExceptionFlags     uint32
	ExceptionRecordPtr uintptr
	ExceptionAddress   uintptr
	NumberParameters   uint32
}

// exceptionPointers khớp EXCEPTION_POINTERS (x64): hai con trỏ liên tiếp.
// Đọc bộ nhớ ngoài qua con trỏ kiểu hóa — chuẩn practice cho Windows
// callback, go vet sạch.
type exceptionPointers struct {
	ExceptionRecord *exceptionRecord
	ContextRecord   uintptr
}

// minidumpExceptionInformation khớp MINIDUMP_EXCEPTION_INFORMATION (x64).
type minidumpExceptionInformation struct {
	ThreadId          uint32
	ExceptionPointers uintptr
	ClientPointers    int32
}

// uefHandler chạy trong ngữ cảnh exception trên thread gây lỗi.
// Trả EXCEPTION_CONTINUE_SEARCH (0) để WER ghi sự kiện như bình thường.
func uefHandler(ep *exceptionPointers) uintptr {
	// Lấy ExceptionCode từ EXCEPTION_POINTERS -> EXCEPTION_RECORD (offset 0).
	code := uint32(0)
	if ep != nil && ep.ExceptionRecord != nil {
		code = ep.ExceptionRecord.ExceptionCode
	}

	line := time.Now().Format("2006-01-02 15:04:05.000") +
		fmt.Sprintf(" [CRASH] unhandled exception · code=0x%08X · đang ghi minidump…\r\n", code)
	for _, f := range diagFiles {
		_, _ = f.WriteString(line) // ghi thẳng, KHÔNG khoá diagMu
	}

	dir := diagDirPath
	if dir == "" {
		dir = os.TempDir()
	}
	dumpPath := filepath.Join(dir,
		"crash-"+time.Now().Format("20060102-150405")+".dmp")

	dumped := false
	if f, err := os.Create(dumpPath); err == nil {
		ei := minidumpExceptionInformation{
			ThreadId:          windows.GetCurrentThreadId(),
			ExceptionPointers: uintptr(unsafe.Pointer(ep)),
			ClientPointers:    0,
		}
		// MiniDumpWriteDump(hProcess, ProcessId, hFile, DumpType,
		//                   ExceptionParam, UserStreamParam, CallbackParam)
		// DumpType = MiniDumpNormal (0): đầy đủ stack + danh sách module.
		const minidumpNormal = 0x00000000
		r1, _, _ := procMiniDumpWriteDump.Call(
			uintptr(windows.CurrentProcess()),
			uintptr(windows.GetCurrentProcessId()),
			f.Fd(),
			uintptr(minidumpNormal),
			uintptr(unsafe.Pointer(&ei)),
			0, 0,
		)
		_ = f.Close()
		dumped = r1 != 0
	}

	ok := "THẤT BẠI"
	if dumped {
		ok = "xong"
	}
	line2 := time.Now().Format("2006-01-02 15:04:05.000") +
		" [CRASH] minidump " + ok + " · " + dumpPath + "\r\n"
	for _, f := range diagFiles {
		_, _ = f.WriteString(line2)
	}

	return 0 // EXCEPTION_CONTINUE_SEARCH -> WER/Event Viewer vẫn chạy
}

// crashInit gắn filter + bật traceback chi tiết. Gọi đúng 1 lần từ main().
func crashInit() {
	// Traceback "all" giúp stack trace của Go (khi runtime tự in) đầy đủ hơn.
	debug.SetTraceback("all")
	cb := syscall.NewCallback(uefHandler)
	procSetUnhandledExceptionFilter.Call(cb)
	diagf("crashdiag: unhandled exception filter đã gắn · minidump -> %s",
		DiagLogDir())
}
