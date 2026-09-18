//go:build !windows

package appstate

// IsWindowsDark trên hệ điều hành khác luôn trả về false (chế độ sáng)
// — chỉ phục vụ dev/build thử nghiệm, bản phát hành thật chạy trên Windows.
func IsWindowsDark() bool { return false }
