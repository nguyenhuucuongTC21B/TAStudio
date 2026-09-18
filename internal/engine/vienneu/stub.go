//go:build !(windows && cgo && vieneu)

// Stub biên dịch khi KHÔNG bật tag `vieneu` (build Lite hoặc dev cross-check).
// Ứng dụng vẫn chạy đầy đủ với tầng SAPI5.
package vienneu

import (
	"errors"

	"hcstudio/internal/engine"
)

// Linked báo hiệu binary CHƯA nhúng engine neural.
const Linked = false

// Driver stub trả lỗi rõ ràng cho mọi thao tác.
type Driver struct{}

const stubErrText = "Engine neural VieNeu chưa được biên dịch vào binary này.\n" +
	"Hãy chạy lại build với lệnh: .\\scripts\\build.ps1 -Full"

func New(modelDir string) *Driver { return &Driver{} }

func (d *Driver) Name() string { return "VieNeu (chưa link)" }

func (d *Driver) ListVoices() ([]engine.Voice, error) {
	return nil, errors.New(stubErrText)
}

func (d *Driver) Synthesize(text string, opts engine.SynthOptions) (*engine.SynthResult, error) {
	return nil, errors.New(stubErrText)
}

func (d *Driver) Close() error { return nil }
