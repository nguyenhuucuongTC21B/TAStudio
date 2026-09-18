package textnorm

import "testing"

func TestNormalize(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		// --- Số ---
		{"so nguyen", "Đây là số 2026.", "Đây là số hai nghìn không trăm hai mươi sáu."},
		{"so don", "7 ngày", "bảy ngày"},
		{"thap phan dau phay", "pi la 3,14", "pi la ba phẩy một bốn"},
		{"thap phan dau cham", "dien tich 1.5 m2", "dien tich một phẩy năm m2"},
		{"thousands cham", "so tien 50.000 đồng?", "so tien năm mươi nghìn đồng?"},
		{"thousands cham x2", "1.234.567", "một triệu hai trăm ba mươi tư nghìn năm trăm sáu mươi bảy"},
		{"thousands comma", "co 50,000 nguoi", "co năm mươi nghìn nguoi"},
		{"mot tram le mot", "số 101", "số một trăm lẻ một"},
		{"muoi lam", "15 tuổi", "mười lăm tuổi"},
		{"hai muoi mot", "21", "hai mươi mốt"},
		{"hai muoi tu", "24", "hai mươi tư"},
		{"khong", "số 0", "số không"},
		{"so lon doc tung chu so", "Số 1234567890123456", "Số một hai ba bốn năm sáu bảy tám chín không một hai ba bốn năm sáu"},

		// --- Phần trăm & tiền ---
		{"phan tram", "giảm 50% giá", "giảm năm mươi phần trăm giá"},
		{"phan nghin", "0,5‰", "không phẩy năm phần nghìn"},
		{"k tien", "giá 500k", "giá năm trăm nghìn"},
		{"vnd don vi", "phí 50.000đ", "phí năm mươi nghìn đồng"},
		{"vnd code", "100.000 VND", "một trăm nghìn đồng"},
		{"dola truoc", "tốn $5", "tốn năm đô la"},
		{"euro truoc", "mua €20", "mua hai mươi euro"},

		// --- Toán ---
		{"cong", "2+3=5", "hai cộng ba bằng năm"},
		{"tru", "10-4", "mười trừ bốn"},
		{"nhan", "6×7=42", "sáu nhân với bảy bằng bốn mươi hai"},
		{"chia", "10÷2", "mười chia cho hai"},
		{"so sanh", "3<5 va 5>3", "ba nhỏ hơn năm va năm lớn hơn ba"},
		{"xap xi", "pi ≈ 3,14", "pi xấp xỉ ba phẩy một bốn"},
		{"do C", "nhiệt độ 45°C", "nhiệt độ bốn mươi lăm độ xê"},
		{"do don", "góc 90°", "góc chín mươi độ"},
		{"binh phuong", "m²", "m bình phương"},
		{"lhap phuong", "3³", "ba lập phương"},
		{"can", "√9 = 3", "căn chín bằng ba"},

		// --- Ký tự đặc biệt ---
		{"email", "gửi tới hai@example.com nhé", "gửi tới hai còng example.com nhé"},
		{"url", "xem tại https://example.com/bai-viet?", "xem tại liên kết example.com/bai-viet"},
		{"a cong", "liên hệ @admin", "liên hệ a còng admin"},
		{"thang", "tag #hot", "tag thăng hot"},
		{"van", "A&B", "A và B"},
		{"ban quyen", "© 2026", "bản quyền hai nghìn không trăm hai mươi sáu"},
		{"thuong hieu", "TM™", "TM thương hiệu"},

		// --- Hy Lạp ---
		{"pi", "hằng số π", "hằng số pi"},
		{"delta", "ΔABC", "đenta ABC"},
		{"omega", "Ω là 1Ω", "ô-mê là một ô-mê"},

		// --- Script ngoài + emoji ---
		{"cjk strip", "汉字 tên Nhật Bản", "tên Nhật Bản"},
		{"cyrillic strip", "Привет thế giới", "thế giới"},
		{"emoji strip", "Xin chào 😀!", "Xin chào!"},
		{"flag strip", "Việt Nam 🇻🇳 đẹp", "Việt Nam đẹp"},

		// --- Ngoại ngữ Latin giữ nguyên ---
		{"tieng anh giu", "Hello world, xin chào!", "Hello world, xin chào!"},
		{"viet giu nguyen", "Tiếng Việt có dấu!", "Tiếng Việt có dấu!"},

		// --- Text rỗng / ký tự trắng ---
		{"rong", "", ""},
		{"khoang trang", "  a   b  ", "a b"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Normalize(c.in)
			if got != c.want {
				t.Errorf("Normalize(%q)\n  got  = %q\n  want = %q", c.in, got, c.want)
			}
		})
	}
}

func TestCardinalVN(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"0", "không"},
		{"1", "một"},
		{"11", "mười một"},
		{"15", "mười lăm"},
		{"20", "hai mươi"},
		{"21", "hai mươi mốt"},
		{"24", "hai mươi tư"},
		{"25", "hai mươi lăm"},
		{"100", "một trăm"},
		{"101", "một trăm lẻ một"},
		{"110", "một trăm mười"},
		{"205", "hai trăm lẻ năm"},
		{"999", "chín trăm chín mươi chín"},
		{"1000", "một nghìn"},
		{"1001", "một nghìn không trăm lẻ một"},
		{"1025", "một nghìn không trăm hai mươi lăm"},
		{"10000", "mười nghìn"},
		{"100000", "một trăm nghìn"},
		{"1000000", "một triệu"},
		{"1000001", "một triệu không trăm lẻ một"},
		{"1200000", "một triệu hai trăm nghìn"},
		{"1234567", "một triệu hai trăm ba mươi tư nghìn năm trăm sáu mươi bảy"},
		{"1000000000", "một tỷ"},
		{"1000000001", "một tỷ không trăm lẻ một"},
	}
	for _, c := range cases {
		if got := cardinalVN(c.in); got != c.want {
			t.Errorf("cardinalVN(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// TestNormalizeSafeOnPlainText đảm bảo văn bản thuần tiếng Việt/SAPI không bị
// biến dạng ngoài ý muốn (kiểm soát hồi quy).
func TestNormalizeSafeOnPlainText(t *testing.T) {
	samples := []string{
		"Xin chào, đây là bài kiểm tra tổng hợp giọng đọc.",
		"Truyện kiều của Nguyễn Du là một kiệt tác văn học Việt Nam.",
		"Hôm nay trời đẹp quá!",
	}
	for _, s := range samples {
		if got := Normalize(s); got != s {
			t.Errorf("Normalize(%q) = %q, want giữ nguyên", s, got)
		}
	}
}
