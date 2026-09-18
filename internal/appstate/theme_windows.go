//go:build windows

package appstate

import (
	"golang.org/x/sys/windows/registry"
)

// IsWindowsDark đọc registry HKCU\...\Themes\Personalize\AppsUseLightTheme
// để biết Windows đang bật chế độ tối hay sáng. Thiếu key coi như Light.
func IsWindowsDark() bool {
	key, err := registry.OpenKey(registry.CURRENT_USER,
		`Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`,
		registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer key.Close()
	val, _, err := key.GetIntegerValue("AppsUseLightTheme")
	if err != nil {
		return false
	}
	return val == 0
}
