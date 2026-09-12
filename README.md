# TVDL — Termux Video Downloader

Công cụ tải video **YouTube** và **Facebook** chạy trực tiếp trên **Termux (Android)**, không cần root, không cần server riêng, không dùng API trả phí.

Engine tải: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) + `ffmpeg` (để ghép audio/video).

---

## 1. Cấu trúc dự án

```
termux-video-downloader/
├── tvdl.sh              # Script chính (chạy trực tiếp)
├── config/
│   └── config.conf      # File cấu hình mẫu (tham khảo)
└── README.md            # Tài liệu này
```

Khi chạy lần đầu, script tự tạo:

- `~/.config/termux-video-downloader/config.conf` — cấu hình thực tế đang dùng
- `/storage/emulated/0/Download/TermuxVideo/` — thư mục tải mặc định
- `/storage/emulated/0/Download/TermuxVideo/tvdl_history.log` — lịch sử tải. File này luôn nằm trong **thư mục tải mặc định** của TVDL, kể cả khi bạn đổi thư mục tải hiện tại ở mục 7.
- `/storage/emulated/0/Download/TermuxVideo/tvdl_error.log` — log lỗi chi tiết (mọi lỗi hiển thị trên màn hình đều được ghi lại vào đây kèm thời gian). Cũng luôn nằm trong thư mục tải mặc định, xem trong menu **6 → 4. Xem log lỗi**.

---

## 2. Cài đặt trên Termux

```bash
pkg update
pkg install python ffmpeg git curl wget
python -m pip install -U yt-dlp
```

Tải/copy `tvdl.sh` vào Termux, sau đó:

```bash
chmod +x tvdl.sh
./tvdl.sh
```

### Cấp quyền bộ nhớ (bắt buộc để lưu video vào Download)

Nếu chưa cấp quyền, chạy:

```bash
termux-setup-storage
```

Script cũng tự động gợi ý lệnh này khi cần.

### (Tuỳ chọn) Tạo lệnh gõ tắt `tvdl`

```bash
mkdir -p ~/../usr/bin 2>/dev/null || true
cp tvdl.sh $PREFIX/bin/tvdl
chmod +x $PREFIX/bin/tvdl
```

Sau đó chỉ cần gõ:

```bash
tvdl
```

từ bất kỳ đâu trong Termux.

### Chạy không màu (terminal không hỗ trợ ANSI)

```bash
./tvdl.sh --no-color
```

---

## 3. Sử dụng

Khi chạy `./tvdl.sh`, script sẽ:

1. Tự kiểm tra Python / FFmpeg / yt-dlp, hỏi cài đặt nếu thiếu.
2. Hiển thị menu chính:

```
╔══════════════════════════════════════╗
║        TERMUX VIDEO DOWNLOADER       ║
║          Facebook + YouTube          ║
╠══════════════════════════════════════╣
  1. Tải video
  2. Tải playlist
  3. Chọn chất lượng mặc định
  4. Chỉ tải audio
  5. Xem thông tin video
  6. Lịch sử tải
  7. Thư mục tải
  8. Cập nhật yt-dlp
  9. Kiểm tra hệ thống
  0. Thoát
```

- **Tải video (1):** dán URL YouTube/Facebook → xem thông tin video → chọn chất lượng (1–8) → xác nhận trước khi tải → file MP4 (hoặc audio nếu chọn "Chỉ audio").
- **Tải playlist (2):** hỗ trợ tải toàn bộ, một khoảng (1–10), hoặc các chỉ số tuỳ chọn (`1,3,5`). Tên file theo mẫu `001 - Tên video.mp4`.
- **Chỉ tải audio (4):** xuất MP3 / M4A / OPUS, không giả bitrate.
- **Xem thông tin video (5):** hiển thị tiêu đề, uploader, thời lượng, độ phân giải mà không tải.
- **Lịch sử tải (6):** xem / xóa / tìm kiếm lịch sử, và xem log lỗi chi tiết (`tvdl_history.log` và `tvdl_error.log`, cả hai đều lưu trong thư mục tải **mặc định** của TVDL, không đổi theo thư mục tải hiện tại).
- **Thư mục tải (7):** mở (cần Termux:API), đổi, hoặc xem thư mục hiện tại.
- **Cập nhật yt-dlp (8):** chạy `pip install -U yt-dlp`, hiển thị phiên bản cũ/mới. Không tự cập nhật ngầm khi khởi động.
- **Kiểm tra hệ thống (9):** trạng thái Termux, Python, yt-dlp, FFmpeg, storage, thư mục tải, kết nối mạng.

Trước khi tải, script **luôn hiển thị lại** tiêu đề / nền tảng / thời lượng / chất lượng / định dạng / thư mục và chờ xác nhận `[Y/n]` — không tự động tải khi chưa đồng ý.

---

## 4. Cập nhật yt-dlp

Có 2 cách:

- Trong menu: chọn **8. Cập nhật yt-dlp**
- Thủ công:

```bash
python -m pip install -U yt-dlp
```

YouTube/Facebook thường xuyên thay đổi cơ chế, nên nếu tải lỗi, hãy thử cập nhật yt-dlp trước tiên.

---

## 5. Xử lý lỗi thường gặp

| Tình huống | Cách xử lý |
|---|---|
| `FFmpeg chưa cài` | `pkg install ffmpeg` hoặc chọn Y khi script hỏi tự cài |
| Video riêng tư / yêu cầu đăng nhập | Script sẽ báo rõ, không có cách vượt qua (không hỗ trợ bypass) |
| Facebook giới hạn khu vực / thay đổi cơ chế | Kiểm tra lại URL, thử video khác, hoặc cập nhật yt-dlp |
| Không tìm thấy chất lượng đã chọn | Script hỏi có muốn chọn chất lượng gần nhất không |
| Mất mạng / tải bị gián đoạn | Chạy lại — script hỗ trợ tiếp tục tải dở (`-c`) |
| Không đủ dung lượng / không có quyền storage | Chạy `termux-setup-storage`, kiểm tra dung lượng máy |
| yt-dlp báo lỗi khác | Xem "Chi tiết" hiển thị trong hộp thoại lỗi, hoặc cập nhật yt-dlp |

Script không bao giờ hiển thị traceback Python/Bash thô cho người dùng — mọi lỗi được bọc lại thành thông báo tiếng Việt dễ hiểu kèm gợi ý khắc phục, đồng thời **ghi lại đầy đủ chi tiết vào `tvdl_error.log`** (trong thư mục tải mặc định) để xem lại sau qua menu 6 → 4.

---

## 6. Bảo mật & quyền riêng tư

- Không bao giờ yêu cầu mật khẩu Facebook / YouTube / Google.
- Không upload video hoặc URL lên server trung gian nào — mọi thứ chạy hoàn toàn cục bộ trên máy bạn.
- Không thu thập dữ liệu người dùng.
- Có thể dùng cookie tự cung cấp (`~/.termux-video-downloader/cookies.txt`, định dạng Netscape) để tải nội dung mà tài khoản của bạn có quyền truy cập — script **không** tự tạo hay yêu cầu cookie, đây là tuỳ chọn nâng cao và cookie có thể chứa thông tin phiên đăng nhập, hãy tự bảo quản cẩn thận.
- Không triển khai bypass DRM, CAPTCHA hoặc cơ chế kiểm soát truy cập. Chỉ tải nội dung bạn có quyền tải xuống.

---

## 7. Cấu hình

File cấu hình thực tế: `~/.config/termux-video-downloader/config.conf`

```conf
DOWNLOAD_DIR=/storage/emulated/0/Download/TermuxVideo
DEFAULT_FORMAT=mp4
DEFAULT_QUALITY=best
AUDIO_FORMAT=mp3
COLOR=1
```

Có thể chỉnh sửa trực tiếp file này, hoặc dùng menu trong app (đổi thư mục tải ở mục 7, đổi chất lượng mặc định ở mục 3).

---

## 8. Giới hạn đã biết

- Chỉ hỗ trợ nội dung công khai hoặc nội dung bạn có quyền truy cập qua cookie hợp lệ.
- Không hỗ trợ Facebook có DRM/CAPTCHA.
- Tốc độ tải phụ thuộc vào kết nối mạng và giới hạn phía nền tảng nguồn.
