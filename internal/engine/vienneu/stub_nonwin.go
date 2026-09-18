//go:build !windows && cgo && vieneu

// Trên hệ điều hành khác engine neural cgo chưa hỗ trợ — dùng stub,
// giữ cho `go vet ./...` và build CI Linux luôn xanh.
package vienneu

import (
	"errors"

	"hcstudio/internal/engine"
)

const Linked = false

type Driver struct{}

const stubErrText = "Engine neural chỉ có trên bản Windows (tag build: vieneu)."

func New(modelDir string) *Driver { return &Driver{} }

func (d *Driver) Name() string { return "VieNeu (stub)" }

func (d *Driver) ListVoices() ([]engine.Voice, error) {
	return nil, errors.New(stubErrText)
}

func (d *Driver) Synthesize(text string, opts engine.SynthOptions) (*engine.SynthResult, error) {
	return nil, errors.New(stubErrText)
}

func (d *Driver) Close() error { return nil }
