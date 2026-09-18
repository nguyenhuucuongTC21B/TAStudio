//go:build windows

// Driver SAPI5 — tầng Ultra-Lite dùng giọng Windows có sẵn (zero model).
//
// Chiến lược kỹ thuật: COM automation qua go-ole IDispatch (ProgID SAPI.SpVoice
// + SAPI.SpFileStream ghi WAV tạm) — API ổn định hai mươi năm trên mọi Windows,
// không cần header/vtable offset nào nên khó vỡ nhất trong toàn app.
package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	ole "github.com/go-ole/go-ole"
	"github.com/go-ole/go-ole/oleutil"

	"hcstudio/internal/dsp"
)

const sapiVoicePrefix = "sapi:"

// SapiDriver wrap một IDispatch của SpVoice.
type SapiDriver struct{}

// NewSapiDriver — caller chịu trách nhiệm CoInitialize (app.go startup làm 1 lần).
func NewSapiDriver() *SapiDriver { return &SapiDriver{} }

func (s *SapiDriver) Name() string { return "Windows SAPI5 (Ultra-Lite)" }

// ListVoices liệt kê toàn bộ giọng SAPI máy đang cài.
func (s *SapiDriver) listTokenNames() ([]string, error) {
	vp, err := oleutil.CreateObject("SAPI.SpVoice")
	if err != nil {
		return nil, fmt.Errorf("không khởi tạo được SAPI.SpVoice: %w", err)
	}
	defer vp.Release()

	disp, err := vp.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		return nil, err
	}
	defer disp.Release()

	collVT, err := oleutil.CallMethod(disp, "GetVoices")
	if err != nil {
		return nil, err
	}
	coll := collVT.ToIDispatch()
	defer coll.Release()

	countVT, err := oleutil.GetProperty(coll, "Count")
	if err != nil {
		return nil, err
	}
	count := int(countVT.Val)

	names := make([]string, 0, count)
	for i := 0; i < count; i++ {
		itemVT, err := oleutil.CallMethod(coll, "Item", i)
		if err != nil {
			continue
		}
		item := itemVT.ToIDispatch()
		name := ""
		if attrVT, err := oleutil.CallMethod(item, "GetAttribute", "Name"); err == nil {
			name = attrVT.ToString()
		} else if descVT, err2 := oleutil.CallMethod(item, "GetDescription", 0); err2 == nil {
			name = descVT.ToString()
		}
		item.Release()
		if name == "" {
			name = fmt.Sprintf("SAPI Voice #%d", i+1)
		}
		names = append(names, name)
	}
	return names, nil
}

// ListVoices trả catalog Voice cho UI.
func (s *SapiDriver) ListVoices() ([]Voice, error) {
	names, err := s.listTokenNames()
	if err != nil {
		return nil, err
	}
	out := make([]Voice, 0, len(names))
	for _, n := range names {
		gender := "unknown"
		low := strings.ToLower(n)
		switch {
		case strings.Contains(low, "female"):
			gender = "female"
		case strings.Contains(low, "male"):
			gender = "male"
		}
		out = append(out, Voice{
			ID:          sapiVoicePrefix + n,
			Name:        n,
			Gender:      gender,
			Region:      "Hệ thống",
			Style:       "sapi",
			Engine:      EngineSAPI,
			Description: "Giọng hệ thống Windows · " + n,
			Available:   true,
		})
	}
	return out, nil
}

// PATCH run #31 — chống kẹt file WAV tạm ("being used by another process"):
//  1. sapiSynthMu: SAPI không hỗ trợ 2 luồng Speak ghi file đồng thời an toàn;
//     job cũ bị huỷ vẫn còn chạy trong goroutine (Speak không biết context) —
//     không chốt là 2 goroutine cùng ghi MỘT file wav tạm.
//  2. Tên wav tạm DUY NHẤT theo bộ đếm mỗi lần gọi — không còn giành chung
//     hcstudio_sapi_<pid>.wav giữa các lần synth.
//  3. Detach AudioOutputStream TRƯỚC khi Close stream (đúng thứ tự SAPI
//     khuyến nghị — voice buông tham chiếu stream trước khi stream đóng).
//  4. Đọc wav có RETRY ngắn (SAPI đôi khi giữ handle thêm vài chục ms sau
//     khi Close trả về) + xoá file tạm kiên trì, xoá không được cũng bỏ qua
//     (file nằm ở %TEMP% nên không gây rác nhìn thấy).
var (
	sapiSynthMu sync.Mutex
	sapiTmpSeq  atomic.Int64
)

// Synthesize render text → WAV tạm → PCM float32.
// Áp dụng native rate từ Speed và báo lại phần đã áp để pipeline chạy WSOLA phần dư.
func (s *SapiDriver) Synthesize(text string, opts SynthOptions) (*SynthResult, error) {
	sapiSynthMu.Lock()
	defer sapiSynthMu.Unlock()

	vp, err := oleutil.CreateObject("SAPI.SpVoice")
	if err != nil {
		return nil, fmt.Errorf("SAPI.SpVoice không khả dụng: %w", err)
	}
	defer vp.Release()
	disp, err := vp.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		return nil, err
	}
	defer disp.Release()

	// Chọn giọng theo tên nếu người dùng chỉ định.
	if opts.VoiceID != "" && strings.HasPrefix(opts.VoiceID, sapiVoicePrefix) {
		wantName := strings.TrimPrefix(opts.VoiceID, sapiVoicePrefix)
		s.selectVoiceByName(disp, wantName)
	}

	// Map speed slider → rate SAPI (thang ±10). Xấp xỉ tuyến tính chấp nhận được.
	rate := int((opts.Speed - 1.0) * 12.5)
	if rate > 10 {
		rate = 10
	} else if rate < -10 {
		rate = -10
	}
	_, _ = oleutil.PutProperty(disp, "Rate", int32(rate))
	nativeFactor := 1.0 + float64(rate)*0.08

	tmpFile := filepath.Join(os.TempDir(),
		fmt.Sprintf("hcstudio_sapi_%d_%d.wav", os.Getpid(), sapiTmpSeq.Add(1)))
	fsObj, ferr := oleutil.CreateObject("SAPI.SpFileStream")
	if ferr != nil {
		return nil, fmt.Errorf("SpFileStream lỗi: %w", ferr)
	}
	defer fsObj.Release()
	fsDisp, ferr := fsObj.QueryInterface(ole.IID_IDispatch)
	if ferr != nil {
		return nil, ferr
	}
	defer fsDisp.Release()

	openMode := int32(3) // SSFCreateForWrite
	if _, err := oleutil.CallMethod(fsDisp, "Open", tmpFile, openMode); err != nil {
		return nil, fmt.Errorf("mở stream ghi WAV thất bại: %w", err)
	}

	streamed := true
	if _, perr := oleutil.PutProperty(disp, "AudioOutputStream", fsDisp); perr != nil {
		streamed = false // fallback hiếm gặp: không gắn được stream ghi file
	}

	flags := int32(8) // SPF_IS_XML — cho phép thẻ pitch sau này
	if _, err := oleutil.CallMethod(disp, "Speak", xmlEscape(text), flags); err != nil {
		if streamed {
			PutNullProperty(disp, "AudioOutputStream")
		}
		CallMethodQuiet(fsDisp, "Close")
		_ = os.Remove(tmpFile)
		return nil, fmt.Errorf("SAPI Speak lỗi: %w", err)
	}

	// Thứ tự giải phóng đúng: voice buông stream TRƯỚC, stream Close SAU.
	if streamed {
		PutNullProperty(disp, "AudioOutputStream")
		CallMethodQuiet(fsDisp, "Close")
	}

	// Đọc wav với retry — chống treo ngắn của handle SAPI sau Close.
	var pcm []float32
	var sr int
	var rerr error
	for attempt := 0; attempt < 15; attempt++ {
		var chn int
		pcm, sr, chn, rerr = dsp.ReadWav(tmpFile)
		if rerr == nil && len(pcm) > 0 {
			_ = chn // mono đã gộp sẵn trong ReadWav
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	// Xoá file tạm kiên trì; thất bại cũng không sao (nằm ở %TEMP%).
	for rm := 0; rm < 5; rm++ {
		if os.Remove(tmpFile) == nil {
			break
		}
		time.Sleep(60 * time.Millisecond)
	}
	if rerr != nil || len(pcm) == 0 {
		return nil, fmt.Errorf("đọc WAV do SAPI tạo thất bại: %v", rerr)
	}

	if !streamed {
		// Không capture được thì cũng chẳng có dữ liệu; trường hợp cực hiếm.
		return nil, fmt.Errorf("SAPI SpFileStream không gắn được vào luồng đầu ra")
	}

	res := &SynthResult{
		Samples:      pcm,
		SampleRate:   sr,
		NativeSpeed:  false,
		SpeedApplied: nativeFactor,
	}
	return res, nil
}

func (s *SapiDriver) selectVoiceByName(disp *ole.IDispatch, want string) bool {
	collVT, err := oleutil.CallMethod(disp, "GetVoices")
	if err != nil {
		return false
	}
	coll := collVT.ToIDispatch()
	defer coll.Release()
	countVT, err := oleutil.GetProperty(coll, "Count")
	if err != nil {
		return false
	}
	count := int(countVT.Val)
	var found *ole.VARIANT
	for i := 0; i < count && found == nil; i++ {
		itemVT, err := oleutil.CallMethod(coll, "Item", i)
		if err != nil {
			continue
		}
		item := itemVT.ToIDispatch()
		name := ""
		if attrVT, e1 := oleutil.CallMethod(item, "GetAttribute", "Name"); e1 == nil {
			name = attrVT.ToString()
		} else if dVT, e2 := oleutil.CallMethod(item, "GetDescription", 0); e2 == nil {
			name = dVT.ToString()
		}
		if name == want {
			found = itemVT
			// giữ item release lần sau vì variant còn dùng
		} else {
			item.Release()
		}
	}
	if found == nil {
		return false
	}
	_, perr := oleutil.PutProperty(disp, "Voice", found.ToIDispatch())
	found.ToIDispatch().Release()
	return perr == nil
}

func xmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;")
	return r.Replace(s)
}

// CallMethodQuiet gọi COM bỏ qua lỗi (utility).
func CallMethodQuiet(disp *ole.IDispatch, method string, args ...interface{}) {
	if disp == nil {
		return
	}
	vt, err := oleutil.CallMethod(disp, method, args...)
	if err == nil && vt != nil {
		vt.Clear()
	}
}

// PutNullProperty đặt property COM về NULL (giải phóng stream đang gắn).
func PutNullProperty(disp *ole.IDispatch, prop string) {
	if disp == nil {
		return
	}
	_, _ = oleutil.PutProperty(disp, prop, nil)
}

// Close giải phóng driver (no-op vì SpVoice tạo/thả mỗi lần synth).
func (s *SapiDriver) Close() error { return nil }
