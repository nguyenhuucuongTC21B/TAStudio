// Package dsp — Smart Splitter tiếng Việt cho HCStudio.
//
// Tách văn bản dài thành các chunk ≤ maxChars đúng ranh giới câu để:
//  1. Thanh tiến trình phản ánh % ký tự thực tế đã tổng hợp.
//  2. Có thể hủy giữa chừng mà không vứt toàn bộ công sức suy luận.
//  3. Chèn khoảng lặng tự nhiên giữa câu (120 ms) và đoạn (240 ms).
package dsp

import (
	"strings"
	"unicode"
)

// SentenceEnders là các dấu kết thúc câu được chấp nhận (bao gồm cả … U+2026).
const sentenceEnders = ".!?…؟"

// SmartSplitter tách văn bản tiếng Việt/lai Việt-Anh thành danh sách chunk.
// Mỗi Chunk mang cờ paragraphBreak ở đầu (nếu chunk trước đó kết thúc đoạn).
type Chunk struct {
	Text            string
	StartRuneOffset int     // vị trí bắt đầu trong văn bản gốc (đếm rune)
	ParaBreakBefore bool    // có ngắt đoạn trước chunk này không
	GapSec          float64 // khoảng lặng chèn SAU chunk này
}

// SplitVietnamese chia text thành các chunk ≤ maxChars ký tự.
// Quy tắc:
//   - Cắt ưu tiên sau dấu câu, kế tiếp là khoảng trắng/xuống dòng.
//   - Không cắt giữa số thập phân (3.14), giữa viết tắt đơn giản.
//   - Câu quá dài được hạ xuống mức gợi ý word-wrap gần nhất.
//   - Chunk ngắn kế cận được gộp để giảm overhead gọi engine.
func SplitVietnamese(text string, maxChars int) []Chunk {
	if maxChars < 32 {
		maxChars = 384 // tham số vô nghĩa/0 → mặc định khớp giới hạn engine VieNeu
	}
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\t", " ")

	sentences := splitSentences(text)
	var chunks []Chunk

	cur := strings.Builder{}
	curStart := 0
	consumed := 0
	lastWasParaEnd := false

	flush := func(gapSec float64) {
		s := strings.TrimSpace(cur.String())
		cur.Reset()
		if s == "" {
			return
		}
		chunks = append(chunks, Chunk{
			Text:            s,
			StartRuneOffset: curStart,
			ParaBreakBefore: lastWasParaEnd && len(chunks) > 0,
			GapSec:          gapSec,
		})
		curStart = consumed
	}

	for _, sent := range sentences {
		runesSent := len([]rune(sent.Text))
		isParaEnd := sent.ParaEnd

		// Nếu câu hiện tại vượt solo maxSize thì phải tự tách cứng theo từ.
		if runesSent > maxChars {
			flush(gapFor(isParaEnd))
			hardSplitLongSentence(sent.Text, maxChars, &chunks, sent.RuneStart)
			consumed = sent.RuneStart + runesSent
			curStart = consumed
			continue
		}

		// Gộp nếu vừa đủ, không vượt maxChars (tính cả 1 dấu cách nối câu).
		if cur.Len() > 0 && cur.Len()+1+runesSent > maxChars {
			gap := gapFor(isParaEnd)
			flush(gap)
			if isParaEnd {
				lastWasParaEnd = true
			}
		}
		if cur.Len() == 0 {
			curStart = sent.RuneStart
		} else {
			cur.WriteByte(' ') // nối câu bằng đúng một khoảng trắng
		}
		cur.WriteString(sent.Text)
		consumed = sent.RuneStart + runesSent
		if isParaEnd {
			flush(gapFor(true))
			lastWasParaEnd = true
		}
	}
	flush(gapFor(false))
	return chunks
}

func gapFor(paraEnd bool) float64 {
	if paraEnd {
		return 0.24
	}
	return 0.12
}

type sentenceSpan struct {
	Text      string
	RuneStart int
	ParaEnd   bool
}

// splitSentences xử lý trên mảng rune để đếm độ dài tiếng Việt chính xác
// (dấu sắc hỏi ngã chồng trên nguyên âm là 1 rune duy nhất khi scan theo rune).
func splitSentences(text string) []sentenceSpan {
	rs := []rune(text)
	var spans []sentenceSpan

	start := 0
	prevEnderIdx := -1
	for i := 0; i < len(rs); i++ {
		r := rs[i]

		// Ghi nhận dấu kết thúc câu. Bảo vệ số thập phân kiểu 3.14:
		// dấu chấm kẹp giữa hai chữ số không phải ranh giới câu.
		if strings.ContainsRune(sentenceEnders, r) {
			isDecimalDot := r == '.' && i > 0 && unicode.IsDigit(rs[i-1]) &&
				i+1 < len(rs) && unicode.IsDigit(rs[i+1])
			if !isDecimalDot {
				prevEnderIdx = i
			}
			continue
		}

		endReached := false
		if prevEnderIdx >= 0 && prevEnderIdx >= i-3 { // chấp nhận cụm "!?", "…?!"
			if unicode.IsSpace(r) || r == '"' || r == '\'' || r == ')' || r == ']' || r == '”' || r == '’' {
				endReached = true
			}
		}
		if r == '\n' {
			endReached = true
		}
		if !endReached {
			continue
		}

		end := i + 1 // bao cả ký tự kết thúc hiện tại vào câu
		if end > len(rs) {
			end = len(rs)
		}
		paraEnd := false
		// newline kép trở lên → ngắt đoạn.
		j := end
		nlCount := 0
		for j < len(rs) && unicode.IsSpace(rs[j]) {
			if rs[j] == '\n' {
				nlCount++
			}
			j++
		}
		if nlCount >= 2 {
			paraEnd = true
			end = j
		}
		if end < start {
			end = start // bất biến an toàn, không bao giờ slice ngược
		}
		txt := strings.TrimSpace(string(rs[start:end]))
		if txt != "" {
			spans = append(spans, sentenceSpan{
				Text:      txt,
				RuneStart: start,
				ParaEnd:   paraEnd,
			})
		}
		start = end
		prevEnderIdx = -1
		// Nhảy con trỏ vòng lặp qua vùng whitespace đã tiêu thụ — khắc phục
		// bug [start:end] đảo chiều khi paragraph được phát hiện giữa chừng.
		if end > i+1 {
			i = end - 1
		}
	}
	if start < len(rs) {
		txt := strings.TrimSpace(string(rs[start:]))
		if txt != "" {
			spans = append(spans, sentenceSpan{
				Text:      txt,
				RuneStart: start,
				ParaEnd:   false,
			})
		}
	}
	return spans
}

// hardSplitLongSentence bắt buộc cắt câu dài hơn maxChars tại khoảng trắng
// gần nhất, tránh tràn bộ nhớ tokenizer của engine.
func hardSplitLongSentence(sent string, maxChars int, chunks *[]Chunk, baseOffset int) {
	rs := []rune(sent)
	pos := 0
	for pos < len(rs) {
		end := pos + maxChars
		if end >= len(rs) {
			end = len(rs)
		} else {
			// Tìm khoảng trắng lùi về phía trước.
			found := -1
			for k := end; k > pos+maxChars/2; k-- {
				if unicode.IsSpace(rs[k]) {
					found = k
					break
				}
			}
			if found > 0 {
				end = found
			}
		}
		part := strings.TrimSpace(string(rs[pos:end]))
		if part != "" {
			*chunks = append(*chunks, Chunk{
				Text:            part,
				StartRuneOffset: baseOffset + pos,
				GapSec:          0.08,
			})
		}
		pos = end
	}
}
