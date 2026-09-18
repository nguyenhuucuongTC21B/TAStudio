package engine

import (
	"errors"
	"sync/atomic"
)

// Hook DI: app.go gán giá trị này lúc startup = vienneu.New để tránh vòng
// import module (vienneu cần engine cho các type dùng chung).
// Khi build Lite (không tag vieneu) biến giữ nguyên nil → Resolve trả lỗi rõ ràng.
var (
	NeuralFactory  func(modelDir string) Driver
	NeuralLinked   atomic.Bool
	NeuralModelDir atomic.Pointer[string] // app.go gán trước khi có request nào
)

// IsNeuralLinked trạng thái liên kết engine tại runtime.
func IsNeuralLinked() bool { return NeuralLinked.Load() && NeuralFactory != nil }

// NewNeuralDriver tạo driver neural qua factory; trả stub lỗi nếu chưa link.
func NewNeuralDriver() Driver {
	if NeuralFactory == nil {
		return errorDriver{}
	}
	p := NeuralModelDir.Load()
	dir := ""
	if p != nil {
		dir = *p
	}
	return NeuralFactory(dir)
}

// errorDriver mọi thao tác đều thất bại với thông điệp hướng dẫn build -Full.
type errorDriver struct{}

var errNotLinked = errors.New(
	"Engine neural VieNeu chưa được biên dịch vào binary.\n" +
		"Hãy chạy lại lệnh build: .\\scripts\\build.ps1 -Full")

func (errorDriver) Name() string { return "not-linked" }
func (errorDriver) ListVoices() ([]Voice, error) {
	return nil, errNotLinked
}
func (errorDriver) Synthesize(text string, opts SynthOptions) (*SynthResult, error) {
	return nil, errNotLinked
}
func (errorDriver) Close() error { return nil }
