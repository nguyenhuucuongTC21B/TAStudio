//go:build !windows

package engine

// Stub SAPI cho môi trường không phải Windows để compile/vet không lỗi.
// Bản phát hành thật chỉ chạy Windows nên driver này không bao giờ được gọi.

type SapiDriver struct{}

func NewSapiDriver() *SapiDriver { return &SapiDriver{} }

func (s *SapiDriver) Name() string { return "SAPI5 (chỉ Windows)" }

func (s *SapiDriver) ListVoices() ([]Voice, error) { return nil, nil }

func (s *SapiDriver) Synthesize(text string, opts SynthOptions) (*SynthResult, error) {
	return nil, ErrNeuralNotLinked // không dùng; trả lỗi nhẹ nhàng đủ ý
}

func (s *SapiDriver) Close() error { return nil }
