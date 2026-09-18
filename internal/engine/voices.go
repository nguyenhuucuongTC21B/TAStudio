package engine

// Catalog giọng preset của VieNeu-TTS v3 Turbo.
//
// PATCH FIX46: nâng cấp 20 → 25 giọng, pin đúng voices_v3_turbo.json revision
// fa2b1afa (bản "curated" mới trên GitHub pnnbao97/VieNeu-TTS — SDK 3.7.1).
// Kiểm chứng tương thích C++ core @cc037cf (vieneu_v3_onnx_voice.cpp
// load_voices): engine duyệt MỌI entry trong "presets" (không hard-count),
// đọc "codes" (đúng shape n_vq=16 cho cả 25 giọng đã đối chiếu) và
// "reserved_id" (null hợp lệ). default_voice "Minh Quân Pro" tồn tại trong
// file mới. 20 giọng cũ GIỮ NGUYÊN vị trí → settings voiceId đã lưu không vỡ.
// Nguồn mô tả: trường description/gender/region/style của chính file json.

var neuralCatalog = []Voice{
	{ID: "Adam", Name: "Adam", Gender: "male", Region: "Nam",
		Style: "tu_nhien", Description: "Nam · Nam · Giọng đọc tự nhiên"},
	{ID: "Phạm Tuyên", Name: "Phạm Tuyên", Gender: "male", Region: "Bắc",
		Style: "tu_nhien", Description: "Nam · Bắc · Phong cách tự nhiên"},
	{ID: "Minh Đức", Name: "Minh Đức", Gender: "male", Region: "Bắc",
		Style: "tin_tuc", Description: "Nam · Bắc · Phong cách tin tức"},
	{ID: "Thanh Bình", Name: "Thanh Bình", Gender: "male", Region: "Bắc",
		Style: "doc_truyen", Description: "Nam · Bắc · Phong cách kể chuyện"},
	{ID: "Ngọc Huyền", Name: "Ngọc Huyền", Gender: "female", Region: "Bắc",
		Style: "tu_nhien", Description: "Nữ · Bắc · Giọng đọc tự nhiên"},
	{ID: "Trúc Ly", Name: "Trúc Ly", Gender: "female", Region: "Bắc",
		Style: "tu_nhien", Description: "Nữ · Bắc · Phong cách tự nhiên"},
	{ID: "Đoan Trang", Name: "Đoan Trang", Gender: "female", Region: "Bắc",
		Style: "tu_nhien", Description: "Nữ · Bắc · Phong cách tự nhiên"},
	{ID: "Ngọc Linh", Name: "Ngọc Linh", Gender: "female", Region: "Bắc",
		Style: "doc_truyen", Description: "Nữ · Bắc · Phong cách kể chuyện"},
	{ID: "Mai Anh", Name: "Mai Anh", Gender: "female", Region: "Bắc",
		Style: "tin_tuc", Description: "Nữ · Bắc · Phong cách tin tức"},
	{ID: "Quỳnh Anh", Name: "Quỳnh Anh", Gender: "female", Region: "Bắc",
		Style: "doc_truyen", Description: "Nữ · Bắc · Phong cách đọc truyện"},
	{ID: "Quang Sơn", Name: "Quang Sơn", Gender: "male", Region: "Trung",
		Style: "tu_nhien", Description: "Nam · Trung · Phong cách tự nhiên"},
	{ID: "Ngọc Trân", Name: "Ngọc Trân", Gender: "female", Region: "Trung",
		Style: "tu_nhien", Description: "Nữ · Trung · Phong cách tự nhiên"},
	{ID: "Xuân Vĩnh", Name: "Xuân Vĩnh", Gender: "male", Region: "Nam",
		Style: "tu_nhien", Description: "Nam · Nam · Phong cách tự nhiên"},
	{ID: "Thái Sơn", Name: "Thái Sơn", Gender: "male", Region: "Nam",
		Style: "doc_truyen", Description: "Nam · Nam · Phong cách kể chuyện"},
	{ID: "Minh Triết", Name: "Minh Triết", Gender: "male", Region: "Nam",
		Style: "tin_tuc", Description: "Nam · Nam · Phong cách tin tức"},
	{ID: "Đức Trí", Name: "Đức Trí", Gender: "male", Region: "Nam",
		Style: "doc_truyen", Description: "Nam · Nam · Phong cách đọc truyện"},
	{ID: "Thục Đoan", Name: "Thục Đoan", Gender: "female", Region: "Nam",
		Style: "doc_truyen", Description: "Nữ · Nam · Phong cách kể chuyện"},
	{ID: "Thùy Dung", Name: "Thùy Dung", Gender: "female", Region: "Nam",
		Style: "tin_tuc", Description: "Nữ · Nam · Phong cách tin tức"},
	{ID: "Mỹ Duyên", Name: "Mỹ Duyên", Gender: "female", Region: "Nam",
		Style: "doc_truyen", Description: "Nữ · Nam · Phong cách đọc truyện"},
	{ID: "Kim Thanh", Name: "Kim Thanh", Gender: "female", Region: "Nam",
		Style: "doc_truyen", Description: "Nữ · Nam · Phong cách đọc truyện"},
	// --- 5 giọng mới (FIX46) — trích nguyên metadata từ voices json @fa2b1afa ---
	{ID: "Adam bựa", Name: "Adam bựa", Gender: "male", Region: "Bắc",
		Style: "tu_nhien", Description: "Nam · Bắc · Phong cách tự nhiên (mới)"},
	{ID: "Anh Khôi", Name: "Anh Khôi", Gender: "male", Region: "Bắc",
		Style: "doc_truyen", Description: "Nam · Bắc · Phong cách kể chuyện (mới)"},
	{ID: "Minh Quân Pro", Name: "Minh Quân Pro", Gender: "male", Region: "Bắc",
		Style: "tu_nhien", Description: "Nam · Bắc · Phong cách tự nhiên (mới · đọc \"Minh Quân\" được map sang)"},
	{ID: "Thiền Tâm Đức", Name: "Thiền Tâm Đức", Gender: "male", Region: "Bắc",
		Style: "doc_truyen", Description: "Nam · Bắc · Phong cách kể chuyện (mới)"},
	{ID: "Mạnh Dũng", Name: "Mạnh Dũng", Gender: "male", Region: "Bắc",
		Style: "tu_nhien", Description: "Nam · Bắc · Phong cách tự nhiên (mới)"},
}

// StyleLabel ánh xạ style code → nhãn UI tiếng Việt.
func StyleLabel(style string) string {
	switch style {
	case "tu_nhien":
		return "Tự nhiên"
	case "tin_tuc":
		return "Tin tức"
	case "doc_truyen":
		return "Đọc truyện"
	case "storytelling":
		return "Kể chuyện"
	case "news":
		return "Tin tức"
	case "audiobook":
		return "Sách nói"
	default:
		return "Đọc bài"
	}
}

// NeuralCatalog trả về bản copy catalog để caller không phá trạng thái chung.
func NeuralCatalog() []Voice {
	out := make([]Voice, len(neuralCatalog))
	copy(out, neuralCatalog)
	return out
}

// IsNeuralVoice kiểm tra một ID có thuộc catalog neural không (25 giọng).
func IsNeuralVoice(id string) bool {
	for _, v := range neuralCatalog {
		if v.ID == id {
			return true
		}
	}
	return false
}

// IsNeuralAlias gộp các bí danh của voices json (SDK 3.7.1) về ID chuẩn.
// Ví dụ "Minh Quân" là alias của "Minh Quân Pro". Lớp hybrid dùng hàm này
// để settings cũ / text cũ vẫn đọc được giọng đúng.
func IsNeuralAlias(id string) (string, bool) {
	if id == "" {
		return "", false
	}
	if IsNeuralVoice(id) {
		return id, true
	}
	switch id {
	case "Minh Quân":
		return "Minh Quân Pro", true
	}
	return "", false
}
