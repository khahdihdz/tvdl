# TVDL Android

Ứng dụng Android độc lập cho dự án TVDL. Không yêu cầu cài Termux.

## Build

Yêu cầu JDK 17, Android SDK 35 và Gradle 8.9.

```bash
gradle assembleDebug
```

APK debug: `app/build/outputs/apk/debug/app-debug.apk`.

## Phát hành APK đã ký

Workflow `.github/workflows/android-release.yml` gọi reusable workflow
`khahdihdz/apksign/.github/workflows/android-shared-signing.yml@main`.

Repository này cần được đồng bộ đủ bốn Actions Secrets từ apksign:

- `ANDROID_SIGNING_KEYSTORE_BASE64`
- `ANDROID_SIGNING_STORE_PASSWORD`
- `ANDROID_SIGNING_KEY_ALIAS`
- `ANDROID_SIGNING_KEY_PASSWORD`

Tạo tag `v1.0.0` để build và phát hành, hoặc chạy workflow thủ công trong Actions.
Workflow phát hành file APK đã ký cùng `SHA256SUMS.txt`.

## Phạm vi phiên bản nền tảng

Bản Android nền tảng này có giao diện native, nhận URL từ Share Sheet và tải URL media trực tiếp bằng Android Download Manager. URL trang video của YouTube/Facebook/Instagram/X/Xiaohongshu cần bộ phân tích/trích xuất media riêng; không được coi là đã hỗ trợ tải trực tiếp cho mọi nền tảng. Phần tích hợp extractor sẽ được phát triển tiếp và kiểm thử riêng.
