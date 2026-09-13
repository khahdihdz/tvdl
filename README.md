# TVDL — Termux Video Downloader

Công cụ tải video/ảnh **YouTube**, **Facebook**, **Instagram** và **X (Twitter)** chạy trực tiếp trên **Termux (Android)**, không cần root, không cần server riêng, không dùng API trả phí.

Engine tải: [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) + `ffmpeg` (để ghép audio/video).

Tác giả: **Khahdihdz** · [khahdihdz.github.io](https://khahdihdz.github.io)

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
- `~/.termux-video-downloader/cookies.txt` — cookie đăng nhập (chỉ tạo khi bạn nạp qua menu 10, xem mục 6)
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
╔══════════════════════════════════════════╗
║         TERMUX VIDEO DOWNLOADER          ║
║    YouTube + Facebook + Instagram + X    ║
╚══════════════════════════════════════════╝
        TVDL v1.1.0 · by Khahdihdz · https://khahdihdz.github.io

  1. Tải video
  2. Tải playlist
  3. Chọn chất lượng mặc định
  4. Chỉ tải audio
  5. Xem thông tin video
  6. Lịch sử tải
  7. Thư mục tải
  8. Cập nhật yt-dlp
  9. Kiểm tra hệ thống
  10. Cookies đăng nhập (Instagram/Facebook riêng tư)
  0. Thoát
```

- **Tải video (1):** dán URL YouTube/Facebook/Instagram/X → xem thông tin video → chọn chất lượng (1–8) → xác nhận trước khi tải → file MP4 (hoặc audio nếu chọn "Chỉ audio"). Nếu bài đăng là **album/carousel nhiều ảnh hoặc video** (thường gặp trên Instagram), script tự tải **toàn bộ các item** và đặt tên file khác nhau để không ghi đè lên nhau; kết quả sau khi tải xong liệt kê đầy đủ từng file.
- **Tải playlist (2):** hỗ trợ tải toàn bộ, một khoảng (1–10), hoặc các chỉ số tuỳ chọn (`1,3,5`). Tên file theo mẫu `001 - Tên video.mp4`.
- **Chỉ tải audio (4):** xuất MP3 / M4A / OPUS, không giả bitrate. Cũng hỗ trợ tải nhiều item nếu URL là album/carousel.
- **Xem thông tin video (5):** hiển thị tiêu đề, uploader, thời lượng, độ phân giải mà không tải.
- **Lịch sử tải (6):** xem / xóa / tìm kiếm lịch sử, và xem log lỗi chi tiết (`tvdl_history.log` và `tvdl_error.log`, cả hai đều lưu trong thư mục tải **mặc định** của TVDL, không đổi theo thư mục tải hiện tại).
- **Thư mục tải (7):** mở (cần Termux:API), đổi, hoặc xem thư mục hiện tại.
- **Cập nhật yt-dlp (8):** chạy `pip install -U yt-dlp`, hiển thị phiên bản cũ/mới. Không tự cập nhật ngầm khi khởi động.
- **Kiểm tra hệ thống (9):** trạng thái Termux, Python, yt-dlp, FFmpeg, storage, thư mục tải, kết nối mạng.
- **Cookies đăng nhập (10):** nạp cookie (từ file, hoặc dán trực tiếp nội dung Netscape cookies.txt), xóa cookie đã lưu, hoặc xem hướng dẫn lấy cookie bằng extension trình duyệt. Dùng cho nội dung riêng tư / giới hạn độ tuổi trên Instagram, Facebook, X.

Trước khi tải, script **luôn hiển thị lại** tiêu đề / nền tảng / thời lượng / chất lượng / định dạng / thư mục và chờ xác nhận `[Y/n]` — không tự động tải khi chưa đồng ý.

---

## 4. Cập nhật yt-dlp

Có 2 cách:

- Trong menu: chọn **8. Cập nhật yt-dlp**
- Thủ công:

```bash
python -m pip install -U yt-dlp
```

Các nền tảng thường xuyên thay đổi cơ chế, nên nếu tải lỗi, hãy thử cập nhật yt-dlp trước tiên — **trừ** trường hợp lỗi "No video could be found in this tweet" trên X (xem mục 8, đây là giới hạn cố định của yt-dlp chứ không phải do thiếu bản cập nhật).

---

## 5. Xử lý lỗi thường gặp

| Tình huống | Cách xử lý |
|---|---|
| `FFmpeg chưa cài` | `pkg install ffmpeg` hoặc chọn Y khi script hỏi tự cài |
| Video/bài đăng riêng tư / yêu cầu đăng nhập (`not available to everyone`, `login required`...) | Nạp cookie tài khoản của bạn qua menu **10** rồi thử lại |
| Facebook/Instagram giới hạn khu vực / thay đổi cơ chế | Kiểm tra lại URL, thử video khác, hoặc cập nhật yt-dlp |
| X (Twitter) báo `No video could be found in this tweet` | Bài đăng đó chỉ có ảnh — yt-dlp **không hỗ trợ tải ảnh từ X** dù ở bản mới nhất (xem mục 8). Lưu ảnh thủ công bằng trình duyệt |
| Không tìm thấy chất lượng đã chọn (`Requested format is not available`) | Script hỏi có muốn tự động chọn chất lượng gần nhất không |
| Mất mạng / tải bị gián đoạn | Chạy lại — script hỗ trợ tiếp tục tải dở (`-c`) |
| Không đủ dung lượng / không có quyền storage | Chạy `termux-setup-storage`, kiểm tra dung lượng máy |
| yt-dlp báo lỗi khác | Xem "Chi tiết" hiển thị trong hộp thoại lỗi, hoặc cập nhật yt-dlp |

Script không bao giờ hiển thị traceback Python/Bash thô cho người dùng — mọi lỗi được bọc lại thành thông báo tiếng Việt dễ hiểu kèm gợi ý khắc phục, đồng thời **ghi lại đầy đủ chi tiết vào `tvdl_error.log`** (trong thư mục tải mặc định) để xem lại sau qua menu 6 → 4. Một lỗi tải thất bại không bao giờ làm thoát cả chương trình — bạn luôn được đưa về lại menu chính.

---

## 6. Cookies đăng nhập (nội dung riêng tư / giới hạn độ tuổi)

Một số bài đăng Instagram/Facebook/X yêu cầu đăng nhập mới xem được (giới hạn độ tuổi, khu vực, hoặc tài khoản riêng tư). Vào menu **10** để:

1. **Nạp cookie từ file** — chỉ đường dẫn tới file `cookies.txt` (định dạng Netscape).
2. **Dán nội dung cookie trực tiếp** — dán nội dung, kết thúc bằng dòng `END`.
3. **Xóa cookie đã lưu**.
4. **Xem hướng dẫn** lấy cookie bằng extension trình duyệt (ví dụ *Get cookies.txt LOCALLY*): đăng nhập trên trình duyệt → mở bài viết cần tải → export cookie → nạp vào TVDL.

Cookie được lưu tại `~/.termux-video-downloader/cookies.txt` (quyền `600`, chỉ chủ tài khoản đọc được) và tự động dùng cho mọi lượt tải sau đó. **Không chia sẻ file này cho ai** — nó chứa phiên đăng nhập tài khoản của bạn.

---

## 7. Bảo mật & quyền riêng tư

- Không bao giờ yêu cầu mật khẩu Facebook / YouTube / Google / Instagram / X.
- Không upload video hoặc URL lên server trung gian nào — mọi thứ chạy hoàn toàn cục bộ trên máy bạn.
- Không thu thập dữ liệu người dùng.
- Có thể dùng cookie tự cung cấp (mục 6) để tải nội dung mà tài khoản của bạn có quyền truy cập — script **không** tự tạo hay yêu cầu cookie, đây là tuỳ chọn nâng cao và cookie có thể chứa thông tin phiên đăng nhập, hãy tự bảo quản cẩn thận.
- Không triển khai bypass DRM, CAPTCHA hoặc cơ chế kiểm soát truy cập. Chỉ tải nội dung bạn có quyền tải xuống.

---

## 8. Giới hạn đã biết

- Chỉ hỗ trợ nội dung công khai hoặc nội dung bạn có quyền truy cập qua cookie hợp lệ.
- Không hỗ trợ Facebook có DRM/CAPTCHA.
- **X (Twitter): không hỗ trợ tải ảnh**, kể cả khi yt-dlp đã cập nhật bản mới nhất. Đây là giới hạn cố định trong extractor của yt-dlp — extractor chủ động bỏ qua media loại ảnh và chỉ xử lý video/GIF, nên tweet chỉ có ảnh sẽ luôn báo `No video could be found in this tweet`. Instagram không bị giới hạn này.
- Tốc độ tải phụ thuộc vào kết nối mạng và giới hạn phía nền tảng nguồn.

---

## 9. Lịch sử phiên bản

- **v1.1.0** — Thêm hỗ trợ X 
