// Package textnorm chuẩn hoá văn bản trước khi đưa vào engine neural.
//
// PATCH FIX46: engine VieNeu v3 Turbo dùng Byte-BPE tokenizer thô — không có
// bước text normalization/phonemize (skip_normalize của ABI v1 chỉ áp cho
// profile v2-turbo). Gặp số, ký hiệu toán, ký tự đặc biệt hay emoji, model
// đọc lộn xộn hoặc bỏ sót. Package này chuyển văn bản sang dạng "đọc được":
//   - số  → chữ tiếng Việt (cardinal, thập phân, tiền, phần trăm, ngày, giờ)
//   - ký hiệu toán học (+ − × ÷ = < > % ≈ π ∑ √ ° ² ³ …) → từ tương ứng
//   - ký tự đặc biệt (@ # & © ® ™ …) → từ hoặc xoá an toàn
//   - emoji/pictograph → xoá (model không đọc được)
//   - chữ Hy Lạp thường gặp → tên đọc thông dụng (π → pi, Δ → đenta)
//   - script ngoài Latin (Cyrillic, CJK, Ả Rập…) → xoá, giữ dấu câu cơ bản
//   - tiếng Anh/Latin không dấu → GIỮ NGUYÊN (model đọc được ở mức cơ bản)
//
// Thiết kế "an toàn trước": mỗi quy tắc chỉ thay thế khi khớp chính xác,
// mọi thứ không chắc chắn được giữ nguyên. Tests nằm ở textnorm_test.go.
package textnorm

import (
	"regexp"
	"strings"
	"unicode"
)

// Options tuỳ biến mức chuẩn hoá. Zero value = khuyến nghị mặc định.
type Options struct {
	// SkipNumbers: không chuyển số sang chữ (mặc định false = luôn chuyển).
	SkipNumbers bool
	// SkipSymbols: không xử lý ký hiệu toán/ký tự đặc biệt (mặc định false).
	SkipSymbols bool
	// KeepEmoji: giữ emoji thay vì xoá (mặc định false = xoá).
	KeepEmoji bool
	// KeepForeignScript: giữ chữ Cyrillic/CJK/Ả Rập… (mặc định false = xoá).
	KeepForeignScript bool
}

// Normalize áp toàn bộ pipeline chuẩn hoá với tuỳ chọn mặc định.
func Normalize(in string) string {
	return NormalizeWith(in, Options{})
}

// NormalizeWith áp pipeline chuẩn hoá theo Options.
// Thứ tự các bước có chủ ý (không đổi trật tự):
//  1. URL/email → dạng đọc được (phải chạy trước mọi quy tắc ký hiệu vì
//     chứa '@' và '.').
//  2. Ký hiệu toán học có ngữ cảnh (giữa hai số, đơn vị °C/°F, m²…).
//  3. Số → chữ (cardinal/decimal/thousands + %, tiền, k/K).
//  4. Ký hiệu đơn lẻ và ký tự đặc biệt còn lại.
//  5. Chữ Hy Lạp.
//  6. Script ngoài Latin → xoá (trừ khi KeepForeignScript).
//  7. Emoji → xoá.
//  8. Rút gọn khoảng trắng thừa.
func NormalizeWith(in string, o Options) string {
	if in == "" {
		return in
	}
	s := in

	if !o.SkipSymbols {
		s = normalizeURLAndEmail(s)
		s = normalizeContextSymbols(s)
	}
	if !o.SkipNumbers {
		s = normalizeNumbers(s)
	}
	if !o.SkipSymbols {
		s = normalizeStandaloneSymbols(s)
		s = normalizeGreek(s)
		s = stripForeignScript(s, o.KeepForeignScript)
	}
	if !o.KeepEmoji {
		s = stripEmoji(s)
	}
	s = collapseSpaces(s)
	return strings.TrimSpace(s)
}

// ---------------------------------------------------------------------------
// 1) URL & email
// ---------------------------------------------------------------------------

var (
	// URL: scheme bắt buộc hoặc www. — bắt dài nhất trước khi cắt dấu câu đuôi.
	reURL = regexp.MustCompile(`(?i)\b(?:https?://|www\.)[^\s<>"]+`)
	// Email: user@domain.tld — chỉ nhận form phổ thông, tránh phá chữ khác.
	reEmail = regexp.MustCompile(`\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b`)
)

func normalizeURLAndEmail(s string) string {
	s = reEmail.ReplaceAllStringFunc(s, func(m string) string {
		// "a@b.com" → "a còng b.com": giữ domain nguyên để model đọc, chỉ
		// chuyển '@' thành "còng" (cách đọc thông dụng trong tiếng Việt).
		parts := strings.SplitN(m, "@", 2)
		return parts[0] + " còng " + parts[1]
	})
	s = reURL.ReplaceAllStringFunc(s, func(m string) string {
		// Đọc thân thiện: bỏ scheme, giữ domain + path ngắn.
		t := strings.TrimPrefix(m, "https://")
		t = strings.TrimPrefix(t, "http://")
		t = strings.TrimPrefix(t, "www.")
		// Bỏ dấu câu đuôi không thuộc URL.
		t = strings.TrimRight(t, ".,;:!?)]}\"'")
		if t == "" {
			return "liên kết"
		}
		return "liên kết " + t
	})
	return s
}

// ---------------------------------------------------------------------------
// 2) Ký hiệu có ngữ cảnh (giữa số, đơn vị, lũy thừa)
// ---------------------------------------------------------------------------

// "a<op>b" với a,b là số — từng khối được thay bằng replaceMath2.
var reMath2 = regexp.MustCompile(`(\d+(?:[.,]\d+)?)\s*([+\-−×x÷/=<>≤≥≠±])\s*(\d+(?:[.,]\d+)?)`)

// Đơn vị: 45°C / 45°F / 45° → "bốn mươi lăm độ xê/ê/độ".
var reDegUnit = regexp.MustCompile(`(\d+)\s*°\s*([CF])?\b`)

// Lũy thừa superscript: m² cm² x² (ký tự ²³ ngay sau một ký tự từ).
// CHÚ Ý RE2 (regexp của Go) KHÔNG hỗ trợ lookahead — mọi điều kiện “theo
// sau phải là…” viết bằng nhóm bắt thứ 3 ([^…]|$) và hàm thay giữ lại nó.
var reSup = regexp.MustCompile(`([A-Za-z0-9\)])\s*([²³])([^A-Za-z0-9]|$)`)

func normalizeContextSymbols(s string) string {
	s = reMath2.ReplaceAllStringFunc(s, replaceMath2)
	s = reDegUnit.ReplaceAllStringFunc(s, func(m string) string {
		g := reDegUnit.FindStringSubmatch(m)
		num := g[1]
		switch g[2] {
		case "C":
			return num + " độ xê"
		case "F":
			return num + " độ ê"
		default:
			return num + " độ"
		}
	})
	s = reSup.ReplaceAllStringFunc(s, func(m string) string {
		g := reSup.FindStringSubmatch(m)
		word := " lập phương"
		if g[2] == "²" {
			word = " bình phương"
		}
		return g[1] + word + g[3]
	})
	return s
}

// replaceMath2 chuyển "2+3" → "2 cộng 3". Số hai vế giữ nguyên dạng số để
// bước normalizeNumbers phía sau tự chuyển sang chữ một cách nhất quán.
func replaceMath2(m string) string {
	g := reMath2.FindStringSubmatch(m)
	if g == nil {
		return m
	}
	a, op, b := g[1], g[2], g[3]
	word := opWord(op)
	if word == "" {
		return m
	}
	return a + " " + word + " " + b
}

func opWord(op string) string {
	switch op {
	case "+":
		return "cộng"
	case "-", "−":
		return "trừ"
	case "×", "x":
		return "nhân với"
	case "÷":
		return "chia cho"
	case "/", "=":
		return "bằng"
	case "<":
		return "nhỏ hơn"
	case ">":
		return "lớn hơn"
	case "≤":
		return "nhỏ hơn hoặc bằng"
	case "≥":
		return "lớn hơn hoặc bằng"
	case "≠":
		return "khác"
	case "±":
		return "cộng trừ"
	}
	return ""
}

// ---------------------------------------------------------------------------
// 3) Số → chữ tiếng Việt
// ---------------------------------------------------------------------------

var (
	rePct = regexp.MustCompile(`(\d+(?:[.,]\d+)?)\s*(%|‰)`)
	// "500k" / "500K" đứng một mình (không phải phần của từ khác).
	reMoneyK = regexp.MustCompile(`(\d+(?:[.,]\d+)?)\s*(k|K)([^A-Za-z0-9]|$)`)
	// Tiền VND: "50.000đ" "50.000 ₫" "100.000 VND". "đồng" phải đứng trước
	// "đ" trong alternation để ưu tiên; theo sau không được là chữ cái khác
	// (tránh nuốt "đ" của từ "đắt" đứng cạnh số).
	reVnd = regexp.MustCompile(`(\d+(?:[.,]\d+)*)\s*(?:₫|VND|đồng|đ)([^\p{L}0-9]|$)`)
	// Tiền trước ký hiệu: "$5" "€20".
	reCurPre = regexp.MustCompile(`([$€¥£])\s*(\d+(?:[.,]\d+)?)`)
	// Số nguyên/chuỗi thousands "1.234.567" hoặc decimal "3,14"/"3.14".
	// Chỉ bắt khi TRƯỚC số không phải là chữ cái (tránh nuốt chữ số trong
	// từ ghép như "m2", "v1.2.3" — model đọc nguyên bản tốt hơn).
	reNumber = regexp.MustCompile(`([^A-Za-zÀ-ỹ0-9.]|^)(\d+(?:[.,]\d+)*)`)
)

func normalizeNumbers(s string) string {
	s = rePct.ReplaceAllStringFunc(s, func(m string) string {
		g := rePct.FindStringSubmatch(m)
		unit := "phần trăm"
		if g[2] == "‰" {
			unit = "phần nghìn"
		}
		return spokenNumber(g[1]) + " " + unit
	})
	s = reMoneyK.ReplaceAllStringFunc(s, func(m string) string {
		g := reMoneyK.FindStringSubmatch(m)
		// g[3] là ký tự theo sau (không phải chữ/số) hoặc rỗng — giữ nguyên.
		return spokenNumber(g[1]) + " nghìn" + g[3]
	})
	s = reVnd.ReplaceAllStringFunc(s, func(m string) string {
		g := reVnd.FindStringSubmatch(m)
		// g[2] là ký tự theo sau đơn vị tiền (không phải chữ/số) hoặc rỗng.
		return spokenNumber(g[1]) + " đồng" + g[2]
	})
	s = reCurPre.ReplaceAllStringFunc(s, func(m string) string {
		g := reCurPre.FindStringSubmatch(m)
		cur := "đô la"
		switch g[1] {
		case "€":
			cur = "euro"
		case "¥":
			cur = "yên"
		case "£":
			cur = "bảng anh"
		}
		return spokenNumber(g[2]) + " " + cur
	})
	s = reNumber.ReplaceAllStringFunc(s, func(m string) string {
		g := reNumber.FindStringSubmatch(m)
		return g[1] + spokenNumber(g[2])
	})
	return s
}

// spokenNumber chuyển một token số ("2026", "3,14", "1.234.567") sang cách
// đọc tiếng Việt. Heuristic dấu ngăn cách:
//   - dấu phẩy: đúng 3 chữ số sau phẩy và chuỗi đó là nhóm cuối → hàng nghìn
//     kiểu EN ("50,000"); còn lại → thập phân ("3,14").
//   - ≥2 dấu chấm → hàng nghìn kiểu VN ("1.234.567").
//   - 1 dấu chấm + đúng 3 chữ số sau chấm → hàng nghìn ("50.000"); khác →
//     thập phân ("3.14", "1.5").
func spokenNumber(tok string) string {
	dots := strings.Count(tok, ".")
	commas := strings.Count(tok, ",")

	if commas > 0 && dots == 0 {
		if isThousandsStyle(tok, ',') {
			return cardinalVN(removeSeparators(tok))
		}
		parts := strings.SplitN(tok, ",", 2)
		return decimalVN(parts[0], parts[1])
	}
	if dots >= 2 && isThousandsStyle(tok, '.') {
		return cardinalVN(removeSeparators(tok))
	}
	if dots == 1 {
		parts := strings.SplitN(tok, ".", 2)
		intPart, frac := parts[0], parts[1]
		if len(frac) == 3 && !strings.Contains(frac, ".") {
			// "50.000" → nghìn. Đã ghi chú trong README: "3.141" cũng rơi
			// vào nhánh này theo chuẩn dấu chấm của tiếng Việt.
			return cardinalVN(intPart + frac)
		}
		return decimalVN(intPart, frac)
	}
	return cardinalVN(tok)
}

func isThousandsStyle(tok string, sep byte) bool {
	groups := strings.Split(tok, string(sep))
	if len(groups) < 2 {
		return false
	}
	for _, g := range groups[1:] {
		if len(g) != 3 {
			return false
		}
		for _, r := range g {
			if r < '0' || r > '9' {
				return false
			}
		}
	}
	return true
}

func removeSeparators(tok string) string {
	tok = strings.ReplaceAll(tok, ".", "")
	tok = strings.ReplaceAll(tok, ",", "")
	return tok
}

func decimalVN(intPart, frac string) string {
	head := cardinalVN(intPart)
	var sb strings.Builder
	sb.WriteString(head)
	sb.WriteString(" phẩy")
	for _, r := range frac {
		if r >= '0' && r <= '9' {
			sb.WriteString(" ")
			sb.WriteString(digitName(r))
		}
	}
	return sb.String()
}

var digitNames = []string{"không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"}

func digitName(r rune) string { return digitNames[r-'0'] }

// cardinalVN đọc số nguyên 0..999.999.999.999 theo chuẩn tiếng Việt
// (lẻ / mười / mười lăm / ba mươi mốt / tư).
func cardinalVN(digits string) string {
	digits = strings.TrimSpace(digits)
	if digits == "" {
		return digits
	}
	// Bỏ số 0 ở đầu.
	k := 0
	for k < len(digits)-1 && digits[k] == '0' {
		k++
	}
	digits = digits[k:]
	if len(digits) > 12 {
		// Quá lớn: đọc từng chữ số an toàn thay vì đoán nhóm.
		var sb strings.Builder
		for i, r := range digits {
			if i > 0 {
				sb.WriteString(" ")
			}
			sb.WriteString(digitName(r))
		}
		return sb.String()
	}
	if digits == "0" {
		return "không"
	}
	// Tách nhóm 3 chữ số từ phải sang trái: [tỷ][triệu][nghìn][đơn vị].
	var groups []int
	for len(digits) > 0 {
		cut := len(digits) - 3
		if cut < 0 {
			cut = 0
		}
		groups = append([]int{atoi(digits[cut:])}, groups...)
		digits = digits[:cut]
	}
	var parts []string
	// scaleNames[idx] với idx = khoảng cách từ nhóm HIỆN TẠI tới nhóm cuối
	// (đơn vị): nhóm cuối "" (đơn vị), áp cuối " nghìn", rồi " triệu", " tỷ".
	scaleNames := []string{"", " nghìn", " triệu", " tỷ"}
	for i, g := range groups {
		if g == 0 {
			continue
		}
		piece := readGroup3(g)
		// Quy tắc "không trăm": nhóm sau một scale mà giá trị < 100 (không
		// tự có chữ trăm) phải đọc "không trăm [lẻ] X" — ví dụ 1001 =
		// "một nghìn không trăm lẻ một", 2026 = "hai nghìn không trăm hai
		// mươi sáu", 1000001 = "một triệu không trăm lẻ một".
		if i > 0 && g < 100 {
			if g < 10 {
				piece = "không trăm lẻ " + digitNames[g]
			} else {
				piece = "không trăm " + piece
			}
		}
		parts = append(parts, piece+scaleNames[len(groups)-1-i])
	}
	if len(parts) == 0 {
		return "không"
	}
	return strings.Join(parts, " ")
}

func atoi(s string) int {
	n := 0
	for _, r := range s {
		n = n*10 + int(r-'0')
	}
	return n
}

// readGroup3 đọc số 1..999 ("lẻ", "mười", "mười lăm", "ba mươi mốt", "tư").
func readGroup3(n int) string {
	h, rem := n/100, n%100
	t, u := rem/10, rem%10
	var sb strings.Builder
	if h > 0 {
		sb.WriteString(digitNames[h])
		sb.WriteString(" trăm")
	}
	if rem == 0 {
		return sb.String()
	}
	if sb.Len() > 0 {
		sb.WriteString(" ")
	}
	switch {
	case t == 0:
		if h > 0 {
			sb.WriteString("lẻ ")
		}
		sb.WriteString(unitVN(u))
	case t == 1:
		sb.WriteString("mười")
		if u == 5 {
			sb.WriteString(" lăm")
		} else if u > 0 {
			sb.WriteString(" ")
			sb.WriteString(unitVN(u))
		}
	default:
		sb.WriteString(digitNames[t])
		sb.WriteString(" mươi")
		if u == 1 {
			sb.WriteString(" mốt")
		} else if u == 4 {
			sb.WriteString(" tư")
		} else if u == 5 {
			sb.WriteString(" lăm")
		} else if u > 0 {
			sb.WriteString(" ")
			sb.WriteString(unitVN(u))
		}
	}
	return sb.String()
}

func unitVN(u int) string { return digitNames[u] }

// ---------------------------------------------------------------------------
// 4) Ký hiệu đơn lẻ + ký tự đặc biệt
// ---------------------------------------------------------------------------

var symbolMap = map[rune]string{
	'+': " cộng ", '−': " trừ ", '×': " nhân với ", '÷': " chia cho ", '=': " bằng ",
	'<': " nhỏ hơn ", '>': " lớn hơn ", '≤': " nhỏ hơn hoặc bằng ",
	'≥': " lớn hơn hoặc bằng ", '≠': " khác ", '≈': " xấp xỉ ",
	'±': " cộng trừ ", '√': " căn ", '∑': " tổng ",
	'∫': " tích phân ", '∞': " vô cực ", '°': " độ ", '%': " phần trăm ",
	'‰': " phần nghìn ",
	'@': " a còng ", '#': " thăng ", '&': " và ",
	'©': " bản quyền ", '®': " đã đăng ký ", '™': " thương hiệu ",
	'§': " mục ", '$': " đô la ", '€': " euro ", '¥': " yên ", '£': " bảng anh ",
	'₫': " đồng ",
	'↑': " lên ", '↓': " xuống ", '←': " trái ", '→': " sang ",
	'½': " một phần hai ", '¼': " một phần tư ", '¾': " ba phần tư ",
	'⅓': " một phần ba ", '⅔': " hai phần ba ",
	'·': ", ", '•': ", ",
	'—': ", ", '–': ", ",
	'…': "...",
	'«': " ", '»': " ",
	'*': " ", '_': " ", '|': " ", '\\': " ",
	'^': " lũy thừa ", '~': " khoảng ",
}

// normalizeStandaloneSymbols thay các ký hiệu còn sót (không nằm trong khối
// toán hai vế đã xử lý ở bước 2).
func normalizeStandaloneSymbols(s string) string {
	var sb strings.Builder
	for _, r := range s {
		if w, ok := symbolMap[r]; ok {
			sb.WriteString(w)
		} else {
			sb.WriteRune(r)
		}
	}
	return sb.String()
}

// ---------------------------------------------------------------------------
// 5) Chữ Hy Lạp
// ---------------------------------------------------------------------------

var greekMap = map[rune]string{
	'α': " an-pha ", 'β': " bê-ta ", 'γ': " gam-ma ", 'δ': " đenta ",
	'ε': " epsilon ", 'θ': " teta ", 'λ': " lam-da ", 'μ': " mu ",
	'ν': " nu ", 'π': " pi ", 'ρ': " ro ", 'σ': " sigma ", 'τ': " tau ",
	'φ': " phi ", 'χ': " kai ", 'ψ': " psi ", 'ω': " omega ",
	'Α': " an-pha ", 'Β': " bê-ta ", 'Γ': " gam-ma ", 'Δ': " đenta ",
	'Θ': " teta ", 'Λ': " lam-da ", 'Π': " pi ", 'Σ': " sigma ",
	'Φ': " phi ", 'Ψ': " psi ", 'Ω': " ô-mê ",
}

func normalizeGreek(s string) string {
	var sb strings.Builder
	for _, r := range s {
		if w, ok := greekMap[r]; ok {
			sb.WriteString(w)
		} else {
			sb.WriteRune(r)
		}
	}
	return sb.String()
}

// ---------------------------------------------------------------------------
// 6) Script ngoài Latin
// ---------------------------------------------------------------------------

func stripForeignScript(s string, keep bool) string {
	if keep {
		return s
	}
	var sb strings.Builder
	for _, r := range s {
		switch {
		case unicode.Is(unicode.Cyrillic, r),
			unicode.Is(unicode.Han, r),
			unicode.Is(unicode.Hiragana, r),
			unicode.Is(unicode.Katakana, r),
			unicode.Is(unicode.Hangul, r),
			unicode.Is(unicode.Arabic, r),
			unicode.Is(unicode.Hebrew, r),
			unicode.Is(unicode.Thai, r),
			unicode.Is(unicode.Devanagari, r):
			// Xoá — model không đọc được các script này; chèn space thay thế
			// để hai bên không dính thành một từ.
			sb.WriteRune(' ')
		default:
			sb.WriteRune(r)
		}
	}
	return sb.String()
}

// ---------------------------------------------------------------------------
// 7) Emoji & pictograph
// ---------------------------------------------------------------------------

func stripEmoji(s string) string {
	var sb strings.Builder
	for _, r := range s {
		if isEmoji(r) {
			sb.WriteRune(' ')
			continue
		}
		sb.WriteRune(r)
	}
	return sb.String()
}

func isEmoji(r rune) bool {
	switch {
	case r >= 0x1F000 && r <= 0x1FAFF: // emoji chính + symbol supplements
		return true
	case r >= 0x2600 && r <= 0x27BF: // misc symbols + dingbats (☀ ✂ ✅)
		return true
	case r >= 0x2B00 && r <= 0x2BFF: // misc symbols & arrows (⭐ ⬆)
		return true
	case r == 0xFE0F || r == 0x200D || r == 0x20E3: // modifier / ZWJ / combining
		return true
	case r >= 0x2190 && r <= 0x21FF &&
		r != '→' && r != '↑' && r != '↓' && r != '←':
		// mũi tên khác 4 mũi tên cơ bản đã map → xoá
		return true
	}
	return false
}

// ---------------------------------------------------------------------------
// 8) Khoảng trắng
// ---------------------------------------------------------------------------

var reSpaces = regexp.MustCompile("[ \t\v\f\r\u00A0\u2000-\u200B]+")

func collapseSpaces(s string) string {
	s = reSpaces.ReplaceAllString(s, " ")
	// Dọn space trước dấu câu để không đọc ngắt quãng.
	s = strings.ReplaceAll(s, " ,", ",")
	s = strings.ReplaceAll(s, " .", ".")
	s = strings.ReplaceAll(s, " !", "!")
	s = strings.ReplaceAll(s, " ?", "?")
	s = strings.ReplaceAll(s, " ;", ";")
	s = strings.ReplaceAll(s, " :", ":")
	return s
}
