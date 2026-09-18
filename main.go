package main

// main.go — Entry point của HCStudio v5.0.
//
// Ràng buộc kiến trúc được thực thi ngay tại đây:
//   - Wails Bind/Bridge: frontend giao tiếp trực tiếp qua bộ nhớ, không port.
//   - Frameless window: tự vẽ traffic-lights macOS trên Windows.
//   - go:embed toàn bộ frontend/dist → không cần Node.js lúc build/release.
//
// PATCH run #29: bật nhật ký chẩn đoán (diaglog.go) TRƯỚC mọi thứ khác —
// mỗi lần chạy app ghi một session vào %LOCALAPPDATA%\HCStudio\logs\hcstudio.log
// (và hcstudio.log cạnh exe nếu thư mục đó cho phép ghi), hết cảnh "mù log".
import (
	"embed"
	"fmt"
	"os"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/windows"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	app := NewApp()

	// PATCH run #29: logger chẩn đoán lên trước — mọi thất bại sau đó
	// đều còn dấu vết trong hcstudio.log kể cả khi app thoát đột ngột.
	diagInit()
	// PATCH FIX41: gắn unhandled exception filter + minidump NGAY SAU
	// logger — crash native lúc synth neural giờ để lại .dmp + dòng
	// [CRASH] trong hcstudio.log thay vì tắt ngóm không một dấu vết.
	crashInit()
	diagf("boot: HCStudio v%s · bắt đầu wails.Run", appVersion)

	err := wails.Run(&options.App{
		Title:     "HCStudio v5.0",
		Width:     1280,
		Height:    820,
		MinWidth:  1040,
		MinHeight: 680,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		OnStartup:  app.startup,
		OnShutdown: app.shutdown,
		Bind:       []interface{}{app},
		Frameless:  true,
		Windows: &windows.Options{
			WebviewIsTransparent: false,
			WindowIsTranslucent:  false,
			DisableWindowIcon:    false,
		},
	})
	if err != nil {
		// Không console nào được phép hiện lên — ghi log tĩnh rồi thoát lặng lẽ.
		// PATCH run #29: cùng lỗi này cũng nằm trong hcstudio.log.
		diagf("[error] wails.Run thất bại: %v", err)
		_ = os.WriteFile("hcstudio-boot-error.log", []byte(fmt.Sprint(err)), 0o644)
		os.Exit(1)
	}
	diagf("boot: wails.Run kết thúc bình thường (cửa sổ đã đóng)")
}
