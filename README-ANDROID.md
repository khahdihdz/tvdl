# TVDL Android

Ứng dụng Android độc lập cho dự án TVDL. Không yêu cầu cài Termux.

## Build

Yêu cầu JDK 17, Android SDK 35 và Gradle 8.9.

```bash
gradle assembleDebug
```

APK debug: `app/build/outputs/apk/debug/app-debug.apk`.

## Tự động phát hành APK đã ký

Workflow `.github/workflows/android-release.yml` tự chạy sau khi workflow **Android CI** hoàn tất thành công trên nhánh `main` (chỉ sự kiện push, không phát hành từ Pull Request).

Quy trình tự động:

1. Android CI kiểm tra build Debug.
2. Nếu CI thành công, workflow Release build `assembleRelease`.
3. Gọi reusable workflow `khahdihdz/apksign/.github/workflows/android-shared-signing.yml@main` để ký APK bằng keystore dùng chung.
4. Tạo GitHub Release với APK đã ký và `SHA256SUMS.txt`.

Phiên bản tự động có dạng `1.0.N`, trong đó `N` là số thứ tự chạy Android CI. Có thể phát hành thủ công bằng cách tạo tag `vX.Y.Z` hoặc chạy workflow trong Actions.

### Secrets bắt buộc

Repository `tvdl` phải có đủ bốn Actions Secrets tương ứng với keystore dùng chung từ `khahdihdz/apksign`:

- `ANDROID_SIGNING_KEYSTORE_BASE64`
- `ANDROID_SIGNING_STORE_PASSWORD`
- `ANDROID_SIGNING_KEY_ALIAS`
- `ANDROID_SIGNING_KEY_PASSWORD`

Không đưa keystore hoặc mật khẩu vào mã nguồn. Nếu thiếu secrets hoặc ký thất bại, Release sẽ dừng và không xuất bản APK chưa ký.

## Phạm vi phiên bản nền tảng

Bản Android nền tảng này có giao diện native, nhận URL từ Share Sheet và tải URL media trực tiếp bằng Android Download Manager. URL trang video của YouTube/Facebook/Instagram/X/Xiaohongshu cần bộ phân tích/trích xuất media riêng; không được coi là đã hỗ trợ tải trực tiếp cho mọi nền tảng. Phần tích hợp extractor sẽ được phát triển tiếp và kiểm thử riêng.
