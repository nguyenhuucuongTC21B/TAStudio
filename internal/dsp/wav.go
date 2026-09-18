package dsp

import (
	"encoding/binary"
	"fmt"
	"math"
	"os"
)

// WriteWav ghi PCM mono/multi-channel float32 xuống file WAV RIFF chuẩn 16-bit.
func WriteWav(path string, samples []float32, sampleRate, channels int) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("không tạo được file wav: %w", err)
	}
	defer f.Close()

	dataBytes := len(samples) * 2
	if channels <= 0 {
		channels = 1
	}
	byteRate := sampleRate * channels * 2

	header := make([]byte, 44)
	copy(header[0:4], "RIFF")
	binary.LittleEndian.PutUint32(header[4:8], uint32(36+dataBytes))
	copy(header[8:12], "WAVE")

	copy(header[12:16], "fmt ")
	binary.LittleEndian.PutUint32(header[16:20], 16)
	binary.LittleEndian.PutUint16(header[20:22], 1) // PCM
	binary.LittleEndian.PutUint16(header[22:24], uint16(channels))
	binary.LittleEndian.PutUint32(header[24:28], uint32(sampleRate))
	binary.LittleEndian.PutUint32(header[28:32], uint32(byteRate))
	binary.LittleEndian.PutUint16(header[32:34], uint16(channels*2)) // block align
	binary.LittleEndian.PutUint16(header[34:36], 16)                 // bits/sample

	copy(header[36:40], "data")
	binary.LittleEndian.PutUint32(header[40:44], uint32(dataBytes))

	if _, err := f.Write(header); err != nil {
		return err
	}

	buf := make([]byte, 2)
	for _, s := range samples {
		if s > 1 {
			s = 1
		} else if s < -1 {
			s = -1
		}
		binary.LittleEndian.PutUint16(buf, uint16(int16(s*32767)))
		if _, err := f.Write(buf); err != nil {
			return err
		}
	}
	return nil
}

// ReadWav đọc WAV PCM 8/16/24/32-bit và float32 trả về []float32, sr, channels.
// Đủ bộ parser chunk đầy đủ: bỏ qua metadata lạ, không giả định header liền mạch.
func ReadWav(path string) ([]float32, int, int, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, 0, err
	}
	if len(raw) < 44 || string(raw[0:4]) != "RIFF" || string(raw[8:12]) != "WAVE" {
		return nil, 0, 0, fmt.Errorf("file không phải WAV hợp lệ")
	}

	var sr, ch, bits int
	formatOK := false
	pos := 12
	var dataChunk []byte

	for pos+8 <= len(raw) {
		id := string(raw[pos : pos+4])
		size := int(binary.LittleEndian.Uint32(raw[pos+4 : pos+8]))
		bodyStart := pos + 8
		bodyEnd := bodyStart + size
		if bodyEnd > len(raw) {
			bodyEnd = len(raw)
		}
		switch id {
		case "fmt ":
			if size >= 16 {
				audioFormat := binary.LittleEndian.Uint16(raw[bodyStart : bodyStart+2])
				ch = int(binary.LittleEndian.Uint16(raw[bodyStart+2 : bodyStart+4]))
				sr = int(binary.LittleEndian.Uint32(raw[bodyStart+4 : bodyStart+8]))
				bits = int(binary.LittleEndian.Uint16(raw[bodyStart+14 : bodyStart+16]))
				formatOK = audioFormat == 1 || audioFormat == 3 || audioFormat == 0xFFFE
			}
		case "data":
			dataChunk = raw[bodyStart:bodyEnd]
		}
		// Các chunk pad chẵn 2 byte theo spec RIFF.
		if size%2 == 1 {
			size++
		}
		pos += 8 + size
	}

	if !formatOK || sr == 0 || ch == 0 || bits == 0 {
		return nil, 0, 0, fmt.Errorf("WAV thiếu fmt hợp lệ")
	}
	if dataChunk == nil {
		return nil, 0, 0, fmt.Errorf("WAV thiếu chunk data")
	}

	bytesPerSample := bits / 8
	stride := bytesPerSample * ch
	n := len(dataChunk) / stride
	out := make([]float32, 0, n)

	frame := make([]byte, stride)
	offset := 0
	for i := 0; i < n; i++ {
		copy(frame, dataChunk[offset:offset+stride])
		offset += stride

		var monoSum float64
		switch bits {
		case 8:
			for c := 0; c < ch; c++ {
				monoSum += float64(frame[c])/127.5 - 1
			}
		case 16:
			for c := 0; c < ch; c++ {
				v := int16(binary.LittleEndian.Uint16(frame[c*2:]))
				monoSum += float64(v) / 32768
			}
		case 24:
			for c := 0; c < ch; c++ {
				v := int32(frame[c*3]) | int32(frame[c*3+1])<<8 | int32(frame[c*3+2])<<16
				if v&0x800000 != 0 {
					v |= -0x1000000
				}
				monoSum += float64(v) / 8388608
			}
		case 32:
			for c := 0; c < ch; c++ {
				u := binary.LittleEndian.Uint32(frame[c*4:])
				monoSum += float64(math.Float32frombits(u)) // float32 format
			}
		}
		out = append(out, float32(monoSum/float64(ch)))
	}
	return out, sr, ch, nil
}

// FloatToPCM16Interleaved chuyển đổi cuối cùng trước khi encode MP3/winmm.
func FloatToPCM16Interleaved(samples []float32) []int16 {
	out := make([]int16, len(samples))
	for i, s := range samples {
		if s > 1 {
			s = 1
		} else if s < -1 {
			s = -1
		}
		out[i] = int16(s * 32767)
	}
	return out
}
