#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# TVDL - Termux Video Downloader
# YouTube + Facebook downloader for Termux (Android), no root, no server.
# Engine: yt-dlp + ffmpeg
###############################################################################

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# 0. GLOBAL CONFIG / PATHS
# ---------------------------------------------------------------------------

APP_NAME="TVDL"
APP_VERSION="1.0.0"

CONFIG_DIR="$HOME/.config/termux-video-downloader"
CONFIG_FILE="$CONFIG_DIR/config.conf"
STATE_DIR="$HOME/.termux-video-downloader"
COOKIES_FILE="$STATE_DIR/cookies.txt"
HISTORY_FILENAME="tvdl_history.log"
ERROR_LOG_FILENAME="tvdl_error.log"
# HISTORY_FILE / ERROR_LOG_FILE are derived from DEFAULT_DOWNLOAD_DIR (see get_history_file / get_error_log_file)

# Termux has no reliably writable /tmp (Android sandboxing can deny it),
# so transient run logs go under our own app state dir instead.
TMP_DIR="${TMPDIR:-$STATE_DIR/tmp}"

DEFAULT_DOWNLOAD_DIR="/storage/emulated/0/Download/TermuxVideo"
DEFAULT_FORMAT="mp4"
DEFAULT_QUALITY="best"
DEFAULT_AUDIO_FORMAT="mp3"
DEFAULT_COLOR="1"

USE_COLOR=1
NO_COLOR_FLAG=0

# ---------------------------------------------------------------------------
# 1. ARG PARSING (--no-color)
# ---------------------------------------------------------------------------

for arg in "$@"; do
    case "$arg" in
        --no-color) NO_COLOR_FLAG=1 ;;
    esac
done

# ---------------------------------------------------------------------------
# 2. COLORS
# ---------------------------------------------------------------------------

setup_colors() {
    if [[ "$NO_COLOR_FLAG" == "1" || "$USE_COLOR" == "0" ]]; then
        C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""
        C_BLUE=""; C_CYAN=""; C_MAGENTA=""
    else
        C_RESET="\033[0m"; C_BOLD="\033[1m"; C_RED="\033[31m"; C_GREEN="\033[32m"
        C_YELLOW="\033[33m"; C_BLUE="\033[34m"; C_CYAN="\033[36m"; C_MAGENTA="\033[35m"
    fi
}

# ---------------------------------------------------------------------------
# 3. LOGGING HELPERS
# ---------------------------------------------------------------------------

log_ok()    { echo -e "${C_GREEN}[✓]${C_RESET} $1"; }
log_fail()  { echo -e "${C_RED}[✗]${C_RESET} $1"; }
log_warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $1"; }
log_info()  { echo -e "${C_CYAN}[i]${C_RESET} $1"; }

pause_screen() {
    echo ""
    read -rp "Nhấn Enter để quay lại menu..." _
}

ask_yes_no() {
    # $1 = prompt, default Yes
    local prompt="$1"
    local ans
    read -rp "$prompt [Y/n] " ans
    ans="${ans,,}"
    if [[ -z "$ans" || "$ans" == "y" || "$ans" == "yes" ]]; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# 4. ERROR HANDLING (so set -e doesn't kill the whole app on expected errors)
# ---------------------------------------------------------------------------

handle_error() {
    local msg="$1"
    local detail="${2:-}"
    echo ""
    log_fail "$msg"
    if [[ -n "$detail" ]]; then
        echo ""
        echo "Chi tiết:"
        echo "$detail" | head -n 15
    fi
    log_error_to_file "$msg" "$detail"
    echo ""
    echo "Gợi ý:"
    echo "  - Kiểm tra URL"
    echo "  - Kiểm tra kết nối Internet"
    echo "  - Cập nhật yt-dlp (menu 8)"
    pause_screen
}

trap 'log_fail "Đã xảy ra lỗi không mong muốn (dòng $LINENO). Script sẽ tiếp tục chạy."; sleep 1' ERR

# ---------------------------------------------------------------------------
# 5. CONFIG LOAD / SAVE
# ---------------------------------------------------------------------------

load_config() {
    mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$TMP_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
DOWNLOAD_DIR=$DEFAULT_DOWNLOAD_DIR
DEFAULT_FORMAT=$DEFAULT_FORMAT
DEFAULT_QUALITY=$DEFAULT_QUALITY
AUDIO_FORMAT=$DEFAULT_AUDIO_FORMAT
COLOR=$DEFAULT_COLOR
EOF
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    DOWNLOAD_DIR="${DOWNLOAD_DIR:-$DEFAULT_DOWNLOAD_DIR}"
    DEFAULT_FORMAT="${DEFAULT_FORMAT:-mp4}"
    DEFAULT_QUALITY="${DEFAULT_QUALITY:-best}"
    AUDIO_FORMAT="${AUDIO_FORMAT:-mp3}"
    COLOR="${COLOR:-1}"
    USE_COLOR="$COLOR"

    mkdir -p "$DEFAULT_DOWNLOAD_DIR" 2>/dev/null || true
    touch "$(get_history_file)" 2>/dev/null || true
    touch "$(get_error_log_file)" 2>/dev/null || true
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
DOWNLOAD_DIR=$DOWNLOAD_DIR
DEFAULT_FORMAT=$DEFAULT_FORMAT
DEFAULT_QUALITY=$DEFAULT_QUALITY
AUDIO_FORMAT=$AUDIO_FORMAT
COLOR=$COLOR
EOF
}

# ---------------------------------------------------------------------------
# 6. DEPENDENCY CHECK / INSTALL
# ---------------------------------------------------------------------------

is_termux() {
    [[ -d "/data/data/com.termux" ]] && return 0
    command -v termux-info >/dev/null 2>&1 && return 0
    return 1
}

check_dependencies() {
    echo "Kiểm tra môi trường..."
    local missing=()

    if is_termux; then
        echo -e "${C_GREEN}[✓]${C_RESET} Termux"
    else
        log_warn "Không phát hiện Termux (script vẫn có thể chạy trên Linux thường)"
    fi

    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        echo -e "${C_GREEN}[✓]${C_RESET} Python"
    else
        echo -e "${C_RED}[✗]${C_RESET} Python"
        missing+=("python")
    fi

    if command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${C_GREEN}[✓]${C_RESET} FFmpeg"
    else
        echo -e "${C_RED}[✗]${C_RESET} FFmpeg"
        missing+=("ffmpeg")
    fi

    if command -v yt-dlp >/dev/null 2>&1; then
        echo -e "${C_GREEN}[✓]${C_RESET} yt-dlp"
    else
        echo -e "${C_RED}[✗]${C_RESET} yt-dlp"
        missing+=("yt-dlp")
    fi

    if ((${#missing[@]} > 0)); then
        echo ""
        log_warn "Chưa cài: ${missing[*]}"
        if ask_yes_no "Tự động cài đặt?"; then
            install_dependencies "${missing[@]}"
        else
            log_warn "Bỏ qua cài đặt. Một số chức năng có thể không hoạt động."
        fi
    fi
}

install_dependencies() {
    local pkgs=("$@")
    local pkg_manager=""

    if command -v pkg >/dev/null 2>&1; then
        pkg_manager="pkg"
    elif command -v apt >/dev/null 2>&1; then
        pkg_manager="apt"
    fi

    for p in "${pkgs[@]}"; do
        case "$p" in
            python)
                if [[ -n "$pkg_manager" ]]; then
                    "$pkg_manager" install -y python || handle_error "Không cài được python"
                fi
                ;;
            ffmpeg)
                if [[ -n "$pkg_manager" ]]; then
                    "$pkg_manager" install -y ffmpeg || handle_error "Không cài được ffmpeg"
                fi
                ;;
            yt-dlp)
                if command -v python3 >/dev/null 2>&1; then
                    python3 -m pip install -U yt-dlp || python3 -m pip install -U yt-dlp --break-system-packages || handle_error "Không cài được yt-dlp"
                elif command -v python >/dev/null 2>&1; then
                    python -m pip install -U yt-dlp || handle_error "Không cài được yt-dlp"
                fi
                ;;
        esac
    done

    log_ok "Cài đặt hoàn tất (nếu không có lỗi ở trên)."
}

# ---------------------------------------------------------------------------
# 7. STORAGE CHECK
# ---------------------------------------------------------------------------

check_storage() {
    if is_termux && command -v termux-setup-storage >/dev/null 2>&1; then
        if [[ ! -d "/storage/emulated/0" ]]; then
            log_warn "Cần cấp quyền truy cập bộ nhớ."
            termux-setup-storage
            sleep 2
        fi
    fi

    mkdir -p "$DOWNLOAD_DIR" 2>/dev/null || {
        handle_error "Không thể tạo thư mục tải: $DOWNLOAD_DIR" "Kiểm tra quyền storage (termux-setup-storage)."
        return 1
    }
    return 0
}

# ---------------------------------------------------------------------------
# 8. BANNER / MENU
# ---------------------------------------------------------------------------

show_banner() {
    clear
    echo -e "${C_CYAN}╔══════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}${C_BOLD}        TERMUX VIDEO DOWNLOADER       ${C_RESET}${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}          Facebook + YouTube          ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════╝${C_RESET}"
}

show_menu() {
    show_banner
    echo ""
    echo -e "  ${C_GREEN}1.${C_RESET} Tải video"
    echo -e "  ${C_GREEN}2.${C_RESET} Tải playlist"
    echo -e "  ${C_GREEN}3.${C_RESET} Chọn chất lượng mặc định"
    echo -e "  ${C_GREEN}4.${C_RESET} Chỉ tải audio"
    echo -e "  ${C_GREEN}5.${C_RESET} Xem thông tin video"
    echo -e "  ${C_GREEN}6.${C_RESET} Lịch sử tải"
    echo -e "  ${C_GREEN}7.${C_RESET} Thư mục tải"
    echo -e "  ${C_GREEN}8.${C_RESET} Cập nhật yt-dlp"
    echo -e "  ${C_GREEN}9.${C_RESET} Kiểm tra hệ thống"
    echo -e "  ${C_RED}0.${C_RESET} Thoát"
    echo ""
    echo -e "Thư mục tải hiện tại: ${C_YELLOW}$DOWNLOAD_DIR${C_RESET}"
    echo ""
    read -rp "Chọn: " MENU_CHOICE
}

# ---------------------------------------------------------------------------
# 9. UTILITIES
# ---------------------------------------------------------------------------

sanitize_filename() {
    # Removes characters invalid on most filesystems: / \ : * ? " < > |
    local name="$1"
    echo "$name" | sed 's/[\/\\:\*\?"<>|]/_/g'
}

detect_platform() {
    local url="$1"
    if [[ "$url" =~ youtube\.com|youtu\.be ]]; then
        echo "YouTube"
    elif [[ "$url" =~ facebook\.com|fb\.watch ]]; then
        echo "Facebook"
    else
        echo "Không xác định"
    fi
}

check_internet() {
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 5 -o /dev/null https://www.google.com && return 0
    fi
    return 1
}

log_history() {
    # timestamp | platform | url | filename | size | status
    local platform="$1" url="$2" filename="$3" size="$4" status="$5"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$DEFAULT_DOWNLOAD_DIR" 2>/dev/null || true
    printf '%s | %s | %s | %s | %s | %s\n' "$ts" "$platform" "$url" "$filename" "$size" "$status" >> "$(get_history_file)" 2>/dev/null || true
}

get_history_file() {
    # History log always lives in TVDL's default download directory
    # (fixed), even if the user changes DOWNLOAD_DIR via menu 7.
    echo "$DEFAULT_DOWNLOAD_DIR/$HISTORY_FILENAME"
}

get_error_log_file() {
    # Error log always lives in TVDL's default download directory (fixed),
    # same rule as the history log.
    echo "$DEFAULT_DOWNLOAD_DIR/$ERROR_LOG_FILENAME"
}

log_error_to_file() {
    local msg="$1"
    local detail="${2:-}"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$DEFAULT_DOWNLOAD_DIR" 2>/dev/null || true
    {
        echo "[$ts] $msg"
        if [[ -n "$detail" ]]; then
            echo "$detail" | sed 's/^/    /'
        fi
        echo "---"
    } >> "$(get_error_log_file)" 2>/dev/null || true
}

yt_dlp_bin() {
    if command -v yt-dlp >/dev/null 2>&1; then
        echo "yt-dlp"
    elif command -v python3 >/dev/null 2>&1; then
        echo "python3 -m yt_dlp"
    else
        echo ""
    fi
}

cookie_args() {
    if [[ -f "$COOKIES_FILE" ]]; then
        echo "--cookies $COOKIES_FILE"
    else
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# 10. VIDEO INFO
# ---------------------------------------------------------------------------

get_video_info() {
    local url="$1"
    local ytdlp
    ytdlp="$(yt_dlp_bin)"
    if [[ -z "$ytdlp" ]]; then
        handle_error "Không tìm thấy yt-dlp." "Cài đặt bằng: python -m pip install -U yt-dlp"
        return 1
    fi

    local platform
    platform="$(detect_platform "$url")"
    echo "Nền tảng: $platform"
    echo "Đang lấy thông tin..."

    local info
    if ! info=$(eval "$ytdlp $(cookie_args) --no-warnings --print '%(title)s|||%(uploader)s|||%(duration_string)s|||%(resolution)s' \"$url\"" 2>"$TMP_DIR/tvdl_err.log"); then
        handle_error "Không lấy được thông tin video." "$(cat "$TMP_DIR/tvdl_err.log" 2>/dev/null)"
        return 1
    fi

    IFS='|||' read -r TITLE UPLOADER DURATION RESOLUTION <<< "$info"
    TITLE="${TITLE:-Không rõ}"
    UPLOADER="${UPLOADER:-Không rõ}"
    DURATION="${DURATION:-Không rõ}"
    RESOLUTION="${RESOLUTION:-Không rõ}"

    echo ""
    echo "Tiêu đề:      $TITLE"
    echo "Uploader:     $UPLOADER"
    echo "Thời lượng:   $DURATION"
    echo "Độ phân giải: $RESOLUTION"
    echo ""
    return 0
}

show_video_info_menu() {
    show_banner
    echo ""
    read -rp "Nhập URL video: " url
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }
    get_video_info "$url" || true
    pause_screen
}

# ---------------------------------------------------------------------------
# 11. QUALITY SELECTION
# ---------------------------------------------------------------------------

show_formats() {
    echo "Chọn chất lượng:"
    echo "  1. Tốt nhất"
    echo "  2. 2160p / 4K"
    echo "  3. 1440p"
    echo "  4. 1080p"
    echo "  5. 720p"
    echo "  6. 480p"
    echo "  7. 360p"
    echo "  8. Chỉ audio"
}

quality_to_format_string() {
    # Returns a yt-dlp -f expression for a given menu choice
    local choice="$1"
    case "$choice" in
        1) echo "bv*+ba/b" ;;
        2) echo "bv*[height<=2160]+ba/b[height<=2160]" ;;
        3) echo "bv*[height<=1440]+ba/b[height<=1440]" ;;
        4) echo "bv*[height<=1080]+ba/b[height<=1080]" ;;
        5) echo "bv*[height<=720]+ba/b[height<=720]" ;;
        6) echo "bv*[height<=480]+ba/b[height<=480]" ;;
        7) echo "bv*[height<=360]+ba/b[height<=360]" ;;
        8) echo "audio-only" ;;
        *) echo "bv*+ba/b" ;;
    esac
}

# ---------------------------------------------------------------------------
# 12. DOWNLOAD VIDEO
# ---------------------------------------------------------------------------

download_video() {
    show_banner
    echo ""
    echo "Nhập URL Facebook hoặc YouTube:"
    read -rp "> " url
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }

    local ytdlp
    ytdlp="$(yt_dlp_bin)"
    if [[ -z "$ytdlp" ]]; then
        handle_error "Không tìm thấy yt-dlp." "Cài đặt bằng: python -m pip install -U yt-dlp"
        return
    fi

    local platform
    platform="$(detect_platform "$url")"
    echo ""
    echo "Nền tảng: $platform"

    if [[ "$platform" == "Không xác định" ]]; then
        log_warn "URL không thuộc YouTube hoặc Facebook. yt-dlp sẽ vẫn thử tải."
    fi

    get_video_info "$url" || return

    echo ""
    show_formats
    read -rp "Chọn (1-8) [mặc định 1]: " qchoice
    qchoice="${qchoice:-1}"
    local fmt
    fmt="$(quality_to_format_string "$qchoice")"

    if [[ "$fmt" == "audio-only" ]]; then
        download_audio_with_url "$url"
        return
    fi

    echo ""
    echo "Tiêu đề:      $TITLE"
    echo "Nền tảng:     $platform"
    echo "Thời lượng:   $DURATION"
    echo "Chất lượng:   Tùy chọn $qchoice"
    echo "Định dạng:    MP4"
    echo "Thư mục:      $DOWNLOAD_DIR"
    echo ""

    if ! ask_yes_no "Bắt đầu tải?"; then
        log_warn "Đã hủy."
        pause_screen
        return
    fi

    mkdir -p "$DOWNLOAD_DIR"
    local outtmpl="$DOWNLOAD_DIR/%(title)s.%(ext)s"

    echo ""
    echo "Downloading..."
    local log_file="$TMP_DIR/tvdl_dl.log"
    set +e
    eval "$ytdlp $(cookie_args) -f \"$fmt\" --merge-output-format mp4 -c --no-warnings --restrict-filenames -o \"$outtmpl\" \"$url\"" 2>&1 | tee "$log_file"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -ne 0 ]]; then
        # Try nearest quality if requested one not found
        if grep -qi "requested format not available" "$log_file"; then
            log_warn "Không tìm thấy chất lượng đã chọn."
            if ask_yes_no "Chọn chất lượng gần nhất?"; then
                set +e
                eval "$ytdlp $(cookie_args) -f \"bv*+ba/b\" --merge-output-format mp4 -c --no-warnings --restrict-filenames -o \"$outtmpl\" \"$url\"" 2>&1 | tee "$log_file"
                rc=${PIPESTATUS[0]}
                set -e
            fi
        fi
    fi

    if [[ $rc -eq 0 ]]; then
        log_ok "Tải thành công"
        local last_file
        last_file=$(ls -t "$DOWNLOAD_DIR" 2>/dev/null | head -n 1)
        local size="Không rõ"
        if [[ -n "$last_file" && -f "$DOWNLOAD_DIR/$last_file" ]]; then
            size=$(du -h "$DOWNLOAD_DIR/$last_file" | cut -f1)
        fi
        echo ""
        echo "File:"
        echo "  ${DOWNLOAD_DIR#/storage/emulated/0/}/$last_file"
        echo ""
        echo "Dung lượng: $size"
        log_history "$platform" "$url" "$last_file" "$size" "OK"
    else
        handle_error "Không thể tải video." "$(tail -n 15 "$log_file" 2>/dev/null)"
        log_history "$platform" "$url" "-" "-" "FAILED"
    fi

    pause_screen
}

# ---------------------------------------------------------------------------
# 13. DOWNLOAD PLAYLIST
# ---------------------------------------------------------------------------

download_playlist() {
    show_banner
    echo ""
    echo "Nhập URL playlist:"
    read -rp "> " url
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }

    local ytdlp
    ytdlp="$(yt_dlp_bin)"
    if [[ -z "$ytdlp" ]]; then
        handle_error "Không tìm thấy yt-dlp."
        return
    fi

    local range_args=""
    if ask_yes_no "Tải toàn bộ playlist?"; then
        range_args=""
    else
        echo "1. Tất cả"
        echo "2. Video 1-10"
        echo "3. Chỉ video được chọn (nhập chỉ số, ví dụ 1,3,5)"
        read -rp "Chọn: " rchoice
        case "$rchoice" in
            2) range_args="--playlist-items 1-10" ;;
            3)
                read -rp "Nhập danh sách chỉ số (vd 1,3,5): " idxs
                range_args="--playlist-items $idxs"
                ;;
            *) range_args="" ;;
        esac
    fi

    show_formats
    read -rp "Chọn (1-8) [mặc định 1]: " qchoice
    qchoice="${qchoice:-1}"
    local fmt
    fmt="$(quality_to_format_string "$qchoice")"
    [[ "$fmt" == "audio-only" ]] && fmt="ba/b"

    echo ""
    echo "Thư mục:      $DOWNLOAD_DIR"
    if ! ask_yes_no "Bắt đầu tải playlist?"; then
        log_warn "Đã hủy."
        pause_screen
        return
    fi

    mkdir -p "$DOWNLOAD_DIR"
    local outtmpl="$DOWNLOAD_DIR/%(playlist_index)03d - %(title)s.%(ext)s"
    local log_file="$TMP_DIR/tvdl_playlist.log"

    set +e
    eval "$ytdlp $(cookie_args) $range_args -f \"$fmt\" --merge-output-format mp4 -c --no-warnings --restrict-filenames -o \"$outtmpl\" \"$url\"" 2>&1 | tee "$log_file"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -eq 0 ]]; then
        log_ok "Tải playlist hoàn tất"
        log_history "Playlist" "$url" "-" "-" "OK"
    else
        handle_error "Không thể tải toàn bộ hoặc một phần playlist." "$(tail -n 15 "$log_file" 2>/dev/null)"
        log_history "Playlist" "$url" "-" "-" "FAILED"
    fi

    pause_screen
}

# ---------------------------------------------------------------------------
# 14. DOWNLOAD AUDIO
# ---------------------------------------------------------------------------

download_audio() {
    show_banner
    echo ""
    echo "Nhập URL video:"
    read -rp "> " url
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }
    download_audio_with_url "$url"
}

download_audio_with_url() {
    local url="$1"
    local ytdlp
    ytdlp="$(yt_dlp_bin)"
    if [[ -z "$ytdlp" ]]; then
        handle_error "Không tìm thấy yt-dlp."
        return
    fi

    echo ""
    echo "Chọn định dạng audio:"
    echo "  1. MP3"
    echo "  2. M4A"
    echo "  3. OPUS"
    read -rp "Chọn [mặc định 1]: " achoice
    achoice="${achoice:-1}"
    local afmt
    case "$achoice" in
        2) afmt="m4a" ;;
        3) afmt="opus" ;;
        *) afmt="mp3" ;;
    esac

    local platform
    platform="$(detect_platform "$url")"

    echo ""
    echo "Nền tảng:  $platform"
    echo "Định dạng: $afmt"
    echo "Thư mục:   $DOWNLOAD_DIR"
    if ! ask_yes_no "Bắt đầu tải audio?"; then
        log_warn "Đã hủy."
        pause_screen
        return
    fi

    mkdir -p "$DOWNLOAD_DIR"
    local outtmpl="$DOWNLOAD_DIR/%(title)s.%(ext)s"
    local log_file="$TMP_DIR/tvdl_audio.log"

    set +e
    eval "$ytdlp $(cookie_args) -x --audio-format $afmt -c --no-warnings --restrict-filenames -o \"$outtmpl\" \"$url\"" 2>&1 | tee "$log_file"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -eq 0 ]]; then
        log_ok "Tải audio thành công"
        local last_file
        last_file=$(ls -t "$DOWNLOAD_DIR" 2>/dev/null | head -n 1)
        log_history "$platform" "$url" "$last_file" "-" "OK"
    else
        handle_error "Không thể tải audio." "$(tail -n 15 "$log_file" 2>/dev/null)"
        log_history "$platform" "$url" "-" "-" "FAILED"
    fi
    pause_screen
}

# ---------------------------------------------------------------------------
# 15. HISTORY MENU
# ---------------------------------------------------------------------------

show_history() {
    while true; do
        show_banner
        echo ""
        echo "  1. Xem lịch sử"
        echo "  2. Xóa lịch sử"
        echo "  3. Tìm kiếm lịch sử"
        echo "  4. Xem log lỗi"
        echo "  0. Quay lại"
        read -rp "Chọn: " hchoice
        local hist_file err_file
        hist_file="$(get_history_file)"
        err_file="$(get_error_log_file)"
        case "$hchoice" in
            1)
                echo ""
                if [[ -s "$hist_file" ]]; then
                    tail -n 50 "$hist_file" | column -t -s '|'
                else
                    log_info "Chưa có lịch sử tải."
                fi
                pause_screen
                ;;
            2)
                if ask_yes_no "Xóa toàn bộ lịch sử?"; then
                    : > "$hist_file"
                    log_ok "Đã xóa lịch sử."
                fi
                pause_screen
                ;;
            3)
                read -rp "Nhập từ khóa: " kw
                echo ""
                grep -i --color=never "$kw" "$hist_file" || log_info "Không tìm thấy."
                pause_screen
                ;;
            4)
                echo ""
                if [[ -s "$err_file" ]]; then
                    echo "File: $err_file"
                    echo ""
                    tail -n 60 "$err_file"
                else
                    log_info "Chưa có log lỗi nào."
                fi
                pause_screen
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 16. DOWNLOAD DIRECTORY MENU
# ---------------------------------------------------------------------------

show_download_dir_menu() {
    while true; do
        show_banner
        echo ""
        echo "  1. Mở thư mục"
        echo "  2. Đổi thư mục"
        echo "  3. Hiển thị thư mục hiện tại"
        echo "  0. Quay lại"
        read -rp "Chọn: " dchoice
        case "$dchoice" in
            1)
                if command -v termux-open >/dev/null 2>&1; then
                    termux-open "$DOWNLOAD_DIR" || log_warn "Không mở được thư mục."
                else
                    log_warn "Cần Termux:API để mở thư mục (termux-open)."
                fi
                pause_screen
                ;;
            2)
                read -rp "Nhập đường dẫn thư mục mới: " newdir
                if [[ -n "$newdir" ]]; then
                    mkdir -p "$newdir" 2>/dev/null && {
                        DOWNLOAD_DIR="$newdir"
                        save_config
                        log_ok "Đã đổi thư mục tải sang: $DOWNLOAD_DIR"
                    } || log_fail "Không tạo được thư mục đó."
                fi
                pause_screen
                ;;
            3)
                echo "Thư mục hiện tại: $DOWNLOAD_DIR"
                pause_screen
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 17. UPDATE YT-DLP
# ---------------------------------------------------------------------------

update_ytdlp() {
    show_banner
    echo ""
    local ytdlp
    ytdlp="$(yt_dlp_bin)"
    local old_version="Không rõ"
    if [[ -n "$ytdlp" ]]; then
        old_version=$(eval "$ytdlp --version" 2>/dev/null || echo "Không rõ")
    fi
    echo "Phiên bản cũ: $old_version"
    echo ""
    echo "Đang cập nhật..."

    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -m pip install -U yt-dlp 2>"$TMP_DIR/tvdl_upd.log"; then
            python3 -m pip install -U yt-dlp --break-system-packages 2>>"$TMP_DIR/tvdl_upd.log" || {
                handle_error "Cập nhật thất bại." "$(cat "$TMP_DIR/tvdl_upd.log")"
                return
            }
        fi
    else
        handle_error "Không tìm thấy Python."
        return
    fi

    local new_version
    new_version=$(eval "$(yt_dlp_bin) --version" 2>/dev/null || echo "Không rõ")
    echo ""
    echo "Phiên bản mới: $new_version"
    log_ok "Cập nhật thành công."
    pause_screen
}

# ---------------------------------------------------------------------------
# 18. SYSTEM CHECK
# ---------------------------------------------------------------------------

system_check() {
    show_banner
    echo ""

    if is_termux; then echo "Termux:       OK"; else echo "Termux:       Không phát hiện"; fi

    if command -v python3 >/dev/null 2>&1; then
        echo "Python:       $(python3 --version 2>&1 | awk '{print $2}')"
    elif command -v python >/dev/null 2>&1; then
        echo "Python:       $(python --version 2>&1 | awk '{print $2}')"
    else
        echo "Python:       [✗] Chưa cài"
    fi

    local ytdlp
    ytdlp="$(yt_dlp_bin)"
    if [[ -n "$ytdlp" ]]; then
        echo "yt-dlp:       $(eval "$ytdlp --version" 2>/dev/null || echo "Không rõ")"
    else
        echo "yt-dlp:       [✗] Chưa cài"
    fi

    if command -v ffmpeg >/dev/null 2>&1; then
        echo "FFmpeg:       $(ffmpeg -version 2>/dev/null | head -n1 | awk '{print $3}')"
    else
        echo "FFmpeg:       [✗] Chưa cài đặt"
        echo ""
        echo "  Sửa bằng: pkg install ffmpeg"
    fi

    if [[ -d "/storage/emulated/0" || ! -d "/data/data/com.termux" ]]; then
        echo "Storage:      OK"
    else
        echo "Storage:      [✗] Chưa cấp quyền (chạy termux-setup-storage)"
    fi

    if mkdir -p "$DOWNLOAD_DIR" 2>/dev/null; then
        echo "Download dir: OK ($DOWNLOAD_DIR)"
    else
        echo "Download dir: [✗] Không tạo được"
    fi

    if check_internet; then
        echo "Internet:     OK"
    else
        echo "Internet:     [✗] Không có kết nối"
    fi

    pause_screen
}

# ---------------------------------------------------------------------------
# 19. DEFAULT QUALITY MENU
# ---------------------------------------------------------------------------

choose_default_quality() {
    show_banner
    echo ""
    show_formats
    read -rp "Chọn chất lượng mặc định [hiện tại: $DEFAULT_QUALITY]: " qchoice
    if [[ -n "$qchoice" ]]; then
        DEFAULT_QUALITY="$qchoice"
        save_config
        log_ok "Đã lưu chất lượng mặc định."
    fi
    pause_screen
}

# ---------------------------------------------------------------------------
# 20. MAIN LOOP
# ---------------------------------------------------------------------------

main() {
    setup_colors
    load_config
    setup_colors   # re-apply in case COLOR came from config
    check_dependencies
    check_storage || true

    while true; do
        show_menu
        case "$MENU_CHOICE" in
            1) download_video ;;
            2) download_playlist ;;
            3) choose_default_quality ;;
            4) download_audio ;;
            5) show_video_info_menu ;;
            6) show_history ;;
            7) show_download_dir_menu ;;
            8) update_ytdlp ;;
            9) system_check ;;
            0)
                echo ""
                log_ok "Tạm biệt!"
                exit 0
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                sleep 1
                ;;
        esac
    done
}

main "$@"
