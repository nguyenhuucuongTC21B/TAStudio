// Package appstate quản lý thiết lập người dùng của HCStudio v5.0.
// File được lưu tại %APPDATA%\HCStudio\settings.json (atomic write).
package appstate

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// ThemeMode cách giao diện khởi động.
type ThemeMode string

const (
	ThemeAuto  ThemeMode = "auto" // theo Windows registry AppsUseLightTheme
	ThemeLight ThemeMode = "light"
	ThemeDark  ThemeMode = "dark"
)

// Settings là toàn bộ trạng thái bền vững của ứng dụng.
// JSON tags dùng camelCase khớp 1-1 với frontend JS.
type Settings struct {
	ThemeMode  ThemeMode `json:"themeMode"`
	VoiceID    string    `json:"voiceId"`
	EnginePref string    `json:"enginePref"` // auto | neural | sapi
	Speed      float64   `json:"speed"`      // 0.5 .. 2.0
	Pitch      float64   `json:"pitch"`      // -12 .. +12 semitone
	Volume     float64   `json:"volume"`     // 0 .. 1
	OutDir     string    `json:"outDir"`
	LightRam   bool      `json:"lightRam"` // PATCH FIX51: nạp weights int8 (nhẹ RAM ~4 lần) khi khởi động
	UpdatedAt  string    `json:"updatedAt"`
}

// DefaultSettings trả về bộ mặc định khi lần đầu chạy hoặc file hỏng.
func DefaultSettings() Settings {
	return Settings{
		ThemeMode:  ThemeAuto,
		VoiceID:    "Adam", // giọng mặc định chính thức của VieNeu v3 Turbo
		EnginePref: "auto",
		LightRam:   false,
		Speed:      1.0,
		Pitch:      0.0,
		Volume:     0.9,
		OutDir:     "",
	}
}

// ConfigDir trả về %APPDATA%\HCStudio, tự tạo nếu chưa có.
func ConfigDir() string {
	base, err := os.UserConfigDir()
	if err != nil || base == "" {
		base = "."
	}
	dir := filepath.Join(base, "HCStudio")
	_ = os.MkdirAll(dir, 0o755)
	return dir
}

// ModelsDir là nơi chứa trọng số VieNeu v3 Turbo.
func ModelsDir() string {
	dir := filepath.Join(ConfigDir(), "models", "vieneu-v3-turbo")
	_ = os.MkdirAll(dir, 0o755)
	return dir
}

// ExportsDir là thư mục xuất audio mặc định.
func ExportsDir() string {
	dir := filepath.Join(ConfigDir(), "exports")
	_ = os.MkdirAll(dir, 0o755)
	return dir
}

// Load đọc settings; nếu không tồn tại/hỏng thì trả DefaultSettings.
func Load() Settings {
	s := DefaultSettings()
	raw, err := os.ReadFile(filepath.Join(ConfigDir(), "settings.json"))
	if err != nil {
		return s
	}
	var loaded Settings
	if json.Unmarshal(raw, &loaded) == nil {
		mergeValid(&s, loaded)
	}
	return s
}

// mergeValid chỉ nhận các trường hợp lệ từ file cũ (bảo vệ giá trị rác).
func mergeValid(dst *Settings, src Settings) {
	switch src.ThemeMode {
	case ThemeAuto, ThemeLight, ThemeDark:
		dst.ThemeMode = src.ThemeMode
	}
	switch src.EnginePref {
	case "auto", "neural", "sapi":
		dst.EnginePref = src.EnginePref
	}
	if len(src.VoiceID) > 0 && len(src.VoiceID) <= 128 {
		dst.VoiceID = src.VoiceID
	}
	dst.Speed = clamp(0.5, 2.0, src.Speed)
	dst.Pitch = clamp(-12, 12, src.Pitch)
	dst.Volume = clamp(0.0, 1.0, src.Volume)
	dst.OutDir = sanitizePath(src.OutDir)
}

func clamp(min, max, v float64) float64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func sanitizePath(p string) string {
	for _, r := range p {
		if r < 0x20 {
			return ""
		}
	}
	const limit = 512
	if len(p) > limit {
		return ""
	}
	return p
}

// Save ghi settings xuống đĩa một cách atomic (tmp + rename).
func (s Settings) Save() error {
	path := filepath.Join(ConfigDir(), "settings.json")
	tmp := path + ".tmp"
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
