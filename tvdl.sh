#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# TVDL - Termux Video Downloader
# YouTube + Facebook + Instagram + X (Twitter) downloader for Termux (Android), no root, no server.
# Engine: yt-dlp + ffmpeg
#
# Author:  Khahdihdz
# Website: https://khahdihdz.github.io
#
# TVDL_INSTALL_MARKER - dấu nhận diện file do TVDL cài (dùng khi gỡ lệnh)
###############################################################################

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# 0. GLOBAL CONFIG / PATHS
# ---------------------------------------------------------------------------

APP_NAME="TVDL"
APP_VERSION="1.3.5"
APP_AUTHOR="Khahdihdz"
APP_URL="https://khahdihdz.github.io"

CONFIG_DIR="$HOME/.config/termux-video-downloader"
CONFIG_FILE="$CONFIG_DIR/config.conf"
STATE_DIR="$HOME/.termux-video-downloader"
COOKIES_FILE="$STATE_DIR/cookies.txt"
HISTORY_FILENAME="tvdl_history.log"
ERROR_LOG_FILENAME="tvdl_error.log"
# HISTORY_FILE / ERROR_LOG_FILE are derived from DEFAULT_DOWNLOAD_DIR (see get_history_file / get_error_log_file)

# Gõ nhanh `tvdl` + tự cập nhật
INSTALL_NAME="tvdl"
INSTALL_MARKER="TVDL_INSTALL_MARKER"
SELF_UPDATE_URL="https://raw.githubusercontent.com/khahdihdz/tvdl/main/tvdl.sh"

# Termux has no reliably writable /tmp (Android sandboxing can deny it),
# so transient run logs go under our own app state dir instead.
TMP_DIR="${TMPDIR:-$STATE_DIR/tmp}"

DEFAULT_DOWNLOAD_DIR="/storage/emulated/0/Download/TermuxVideo"
DEFAULT_FORMAT="mp4"
DEFAULT_QUALITY="1"
DEFAULT_AUDIO_FORMAT="mp3"
DEFAULT_COLOR="1"

# Safe defaults until load_config / setup_colors run
DOWNLOAD_DIR="$DEFAULT_DOWNLOAD_DIR"
AUDIO_FORMAT="$DEFAULT_AUDIO_FORMAT"
COLOR="$DEFAULT_COLOR"

USE_COLOR=1
NO_COLOR_FLAG=0

# YTDLP_CMD / COOKIE_ARGS are bash arrays (no eval, no shell injection)
YTDLP_CMD=()
COOKIE_ARGS=()
COOKIE_LAST_FORMAT=""
CURRENT_URL=""
XHS_TITLE=""
XHS_UPLOADER=""
XHS_DURATION_MS=0
XHS_STREAMS=()

# ---------------------------------------------------------------------------
# 1. ARG PARSING
# ---------------------------------------------------------------------------

ACTION="menu"
ASSUME_YES=0
BAD_ARG=""
INTERACTIVE=1

for arg in "$@"; do
    case "$arg" in
        --no-color) NO_COLOR_FLAG=1 ;;
        --install) ACTION="install" ;;
        --uninstall|--remove) ACTION="uninstall" ;;
        --status) ACTION="status" ;;
        --update) ACTION="update" ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) ACTION="help" ;;
        -V|--version) ACTION="version" ;;
        *)
            ACTION="badarg"
            BAD_ARG="$arg"
            ;;
    esac
done

if [[ "$ACTION" != "menu" ]]; then
    INTERACTIVE=0
fi

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
    (( INTERACTIVE )) || return 0
    echo ""
    read -rp "Nhấn Enter để quay lại menu..." _ || true
}

ask_yes_no() {
    # $1 = prompt, default Yes
    local prompt="$1"
    local ans
    (( INTERACTIVE )) || return 1
    read -rp "$prompt [Y/n] " ans || return 1
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
    if echo "$detail" | grep -qiE "not available to everyone|isn't available to everyone|certain audiences|rate-limit|login required|restricted video|private"; then
        echo "  - Bài/video này yêu cầu ĐĂNG NHẬP mới xem được"
        echo "    (bị giới hạn độ tuổi / khu vực / nội dung nhạy cảm)."
        echo "  - Vào menu 10 (Cookies đăng nhập) để nạp cookie trình duyệt"
        echo "    rồi thử tải lại."
    elif echo "$detail" | grep -qiE "must be netscape|netscape formatted|cookies file"; then
        echo "  - File cookie đang ở định dạng JSON, còn yt-dlp chỉ nhận Netscape."
        echo "  - Vào menu 10 → 1 (nạp lại file) hoặc 2 (dán nội dung):"
        echo "    TVDL sẽ tự chuyển JSON sang Netscape và giữ bản gốc .json.bak."
        echo "  - Hoặc menu 10 → 3 để xóa cookie rồi nạp lại từ đầu."
    elif echo "$detail" | grep -qiE "no video could be found"; then
        echo "  - X (Twitter) không hỗ trợ tải ẢNH qua yt-dlp (chỉ video/GIF),"
        echo "    kể cả với bản yt-dlp mới nhất — đây là giới hạn của yt-dlp,"
        echo "    không phải do thiếu cập nhật."
        echo "  - Nếu bài đăng chỉ có ảnh: lưu ảnh thủ công bằng trình duyệt"
        echo "    (nhấn giữ ảnh > Lưu ảnh)."
        echo "  - Nếu bạn chắc bài đăng có video, có thể tài khoản đó riêng tư"
        echo "    → thử menu 10 (Cookies) rồi tải lại."
    elif echo "$detail" | grep -qiE "no video formats found"; then
        echo "  - Nếu đây là bài Xiaohongshu (Tiểu Hồng Thư) chỉ có ẢNH (không"
        echo "    video): yt-dlp hiện chỉ tải được video từ Xiaohongshu, chưa"
        echo "    hỗ trợ tải bài dạng ảnh/图文 — cần lưu ảnh thủ công."
        echo "  - Nếu là link rút gọn xhslink.com, thử mở link đó trên trình"
        echo "    duyệt để lấy URL đầy đủ dạng xiaohongshu.com/explore/... rồi"
        echo "    dán lại URL đó."
        echo "  - Nếu bài đăng riêng tư, thử menu 10 (Cookies) rồi tải lại."
    elif echo "$detail" | grep -qiE "unsupported url"; then
        echo "  - URL không phải trang video mà là trang đăng nhập/trang chủ/link rút gọn."
        echo "  - Xiaohongshu: mở link bằng trình duyệt, đăng nhập, rồi copy URL"
        echo "    dạng xiaohongshu.com/explore/... hoặc /discovery/item/... (kèm xsec_token)."
        echo "  - TVDL đã tự xử lý link chia sẻ dạng /login?redirectPath=...;"
        echo "    nếu vẫn lỗi, nạp cookie Xiaohongshu qua menu 10 rồi thử lại."
    else
        echo "  - Kiểm tra URL"
        echo "  - Kiểm tra kết nối Internet"
        echo "  - Cập nhật yt-dlp (menu 8)"
        echo "  - Nếu là nội dung riêng tư/giới hạn tuổi, thử menu 10 (Cookies)"
    fi
    pause_screen
}

trap 'log_fail "Đã xảy ra lỗi không mong muốn (dòng $LINENO)."' ERR

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
    DEFAULT_QUALITY="${DEFAULT_QUALITY:-1}"
    AUDIO_FORMAT="${AUDIO_FORMAT:-mp3}"
    COLOR="${COLOR:-1}"

    # Migrate old/unknown values so the menu always shows a usable default
    valid_quality "$DEFAULT_QUALITY" || DEFAULT_QUALITY="1"
    case "$AUDIO_FORMAT" in
        mp3|m4a|opus) ;;
        *) AUDIO_FORMAT="mp3" ;;
    esac
    USE_COLOR="$COLOR"

    mkdir -p "$DEFAULT_DOWNLOAD_DIR" 2>/dev/null || true
    touch "$(get_history_file)" 2>/dev/null || true
    touch "$(get_error_log_file)" 2>/dev/null || true

    # Cookie JSON do người dùng nạp trước đây được tự chuyển sang Netscape
    if [[ -f "$COOKIES_FILE" ]]; then
        normalize_cookies_file "$COOKIES_FILE" || true
    fi

    resolve_ytdlp
}

save_config() {
    # %q keeps paths with spaces/UTF-8 safe when the file is sourced again
    {
        printf 'DOWNLOAD_DIR=%q\n' "$DOWNLOAD_DIR"
        printf 'DEFAULT_FORMAT=%q\n' "$DEFAULT_FORMAT"
        printf 'DEFAULT_QUALITY=%q\n' "$DEFAULT_QUALITY"
        printf 'AUDIO_FORMAT=%q\n' "$AUDIO_FORMAT"
        printf 'COLOR=%q\n' "$COLOR"
    } > "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# 6. DEPENDENCY CHECK / INSTALL
# ---------------------------------------------------------------------------

is_termux() {
    [[ -d "/data/data/com.termux" ]] && return 0
    command -v termux-info >/dev/null 2>&1 && return 0
    return 1
}

resolve_ytdlp() {
    YTDLP_CMD=()
    if command -v yt-dlp >/dev/null 2>&1; then
        YTDLP_CMD=(yt-dlp)
    elif command -v python3 >/dev/null 2>&1; then
        YTDLP_CMD=(python3 -m yt_dlp)
    elif command -v python >/dev/null 2>&1; then
        YTDLP_CMD=(python -m yt_dlp)
    fi

    COOKIE_ARGS=()
    if [[ -f "$COOKIES_FILE" ]]; then
        COOKIE_ARGS=(--cookies "$COOKIES_FILE")
    fi
}

have_ytdlp() {
    ((${#YTDLP_CMD[@]} > 0))
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

    if command -v yt-dlp >/dev/null 2>&1 || have_ytdlp; then
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
            resolve_ytdlp
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
    # Logo dạng "thẻ mở": không có viền phải, nên chữ tiếng Việt có dấu
    # không bao giờ làm lệch khung trên mọi độ rộng terminal.
    local rule="────────────────────────────────────"
    local cols="${COLUMNS:-80}"
    local meta="${APP_NAME} v${APP_VERSION} · by ${APP_AUTHOR}"

    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    if (( cols >= 62 )); then
        meta+=" · ${APP_URL}"
    fi

    clear 2>/dev/null || true
    echo -e "  ${C_CYAN}┌${rule}${C_RESET}"
    echo -e "  ${C_GREEN}│${C_RESET}  ${C_GREEN}${C_BOLD}▶${C_RESET}  ${C_BOLD}${APP_NAME}${C_RESET}"
    echo -e "  ${C_GREEN}│${C_RESET}     ${C_CYAN}Termux Video Downloader${C_RESET}"
    echo -e "  ${C_GREEN}│${C_RESET}     Tải video & ảnh đa nền tảng"
    echo -e "  ${C_CYAN}└${rule}${C_RESET}"
    echo "     YouTube · Facebook · Instagram"
    echo "     X (Twitter) · Xiaohongshu"
    echo -e "     ${C_CYAN}${meta}${C_RESET}"
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
    echo -e "  ${C_GREEN}10.${C_RESET} Cookies đăng nhập (Instagram/Facebook riêng tư)"
    echo -e "  ${C_GREEN}11.${C_RESET} Cài đặt / gỡ lệnh tvdl"
    echo -e "  ${C_RED}0.${C_RESET} Thoát"
    echo ""
    echo -e "Thư mục tải hiện tại: ${C_YELLOW}$DOWNLOAD_DIR${C_RESET}"
    echo ""
    if ! read -rp "Chọn: " MENU_CHOICE; then
        echo ""
        log_ok "Tạm biệt!"
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# 9. UTILITIES
# ---------------------------------------------------------------------------

resolve_share_url() {
    # Chuẩn hóa link chia sẻ (đặc biệt Xiaohongshu) trước khi đưa cho yt-dlp:
    # - trích URL từ đoạn text dán kèm
    # - link /login?redirectPath=... -> URL bài viết thật
    # - xhslink.com -> theo redirect
    # - bỏ tham số rác, giữ xsec_token/xsec_source
    local url="$1"

    case "$url" in
        *xhslink.com*)
            if command -v curl >/dev/null 2>&1; then
                local eff
                eff="$(curl -fsSL --max-time 20 -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null || true)"
                [[ -n "$eff" ]] && url="$eff"
            fi
            ;;
    esac

    if ! command -v python3 >/dev/null 2>&1; then
        echo "$url"
        return 0
    fi

    python3 - "$url" <<'PYEOF'
import re
import sys
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit

raw = sys.argv[1].strip().strip('"\'')
match = re.search(r'https?://[^\s<>"\']+', raw)
url = match.group(0) if match else raw
url = url.rstrip(').,;')

for _ in range(3):
    parts = urlsplit(url)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    if "redirectPath" not in query:
        break
    url = unquote(query.pop("redirectPath", ""))

parts = urlsplit(url)
host = parts.netloc.lower()
if not host.endswith("xiaohongshu.com"):
    print(url)
    sys.exit(0)

if not host.startswith("www."):
    host = "www." + host.lstrip(".")

item = re.match(r"^/(?:explore|discovery/item)/([0-9a-fA-F]+)", parts.path)
if not item:
    print(urlunsplit(("https", host, parts.path, parts.query, parts.fragment)))
    sys.exit(0)

prefix = "/explore/" if parts.path.startswith("/explore/") else "/discovery/item/"
query = dict(parse_qsl(parts.query, keep_blank_values=True))
query.pop("redirectPath", None)
for junk in ("app_platform", "app_version", "ignoreEngage", "apptime",
             "shareRedId", "share_id", "share_channel", "xhsshare",
             "author_share", "exSource", "share_from_user_hidden"):
    query.pop(junk, None)

ordered = []
for key in ("xsec_token", "xsec_source", "type", "source"):
    if key in query:
        ordered.append((key, query.pop(key)))
ordered.extend(query.items())
print(urlunsplit(("https", host, prefix + item.group(1), urlencode(ordered), "")))
PYEOF
}

detect_platform() {
    local url="$1"
    if [[ "$url" =~ youtube\.com|youtu\.be ]]; then
        echo "YouTube"
    elif [[ "$url" =~ facebook\.com|fb\.watch ]]; then
        echo "Facebook"
    elif [[ "$url" =~ instagram\.com ]]; then
        echo "Instagram"
    elif [[ "$url" =~ (twitter\.com|x\.com)/ ]]; then
        echo "X (Twitter)"
    elif [[ "$url" =~ xiaohongshu\.com|xhslink\.com ]]; then
        echo "Xiaohongshu"
    else
        echo "Không xác định"
    fi
}

check_internet() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 5 -o /dev/null https://www.google.com && return 0
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

# ---------------------------------------------------------------------------
# 9b. COOKIE MANAGEMENT (needed for Instagram/Facebook age-restricted,
#     private, or "not available to everyone" content)
# ---------------------------------------------------------------------------

cookies_file_is_netscape() {
    head -n 5 "$1" 2>/dev/null | grep -qiE "^# (Netscape )?HTTP Cookie File"
}

cookies_count() {
    local n
    n="$(grep -vcE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true)"
    echo "${n:-0}"
}

detect_cookie_format() {
    # Chỉ dùng để hiển thị cho người dùng biết đã nhận dạng nào
    local f="$1"
    local first
    if cookies_file_is_netscape "$f"; then
        echo "Netscape"
        return
    fi
    first="$(head -c 200 "$f" 2>/dev/null | tr -d '[:space:]\357\273\277' | head -c 1)"
    case "$first" in
        "{"|"[") echo "JSON" ;;
        *)       echo "Chuỗi Cookie" ;;
    esac
}

show_cookie_result() {
    local count fmt
    count="$(cookies_count "$COOKIES_FILE")"
    fmt="${COOKIE_LAST_FORMAT:-Netscape}"

    echo ""
    echo -e "${C_GREEN}────────────────────────────────────────────${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}   ✓ ĐÃ LƯU COOKIE THÀNH CÔNG${C_RESET}"
    echo -e "${C_GREEN}────────────────────────────────────────────${C_RESET}"
    echo "  Số cookie:  $count"
    if [[ "$fmt" == "Netscape" ]]; then
        echo "  Định dạng:  Netscape"
    else
        echo "  Định dạng:  $fmt → Netscape"
    fi
    echo "  File:       $COOKIES_FILE"
    if [[ -f "$COOKIES_FILE.bak" ]]; then
        echo "  Sao lưu:    $COOKIES_FILE.bak"
    fi
    echo ""
    echo "  Cookie này được dùng cho mọi lượt tải tiếp theo."
}

cookies_convert_file() {
    # Chuyển mọi định dạng cookie phổ biến sang Netscape.
    # $1 = nguồn, $2 = đích, $3 = tên miền (chỉ cần cho chuỗi Cookie:)
    # exit 13 = cần tên miền mới xử lý được
    python3 - "$1" "$2" "${3:-}" <<'PYEOF'
import json
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
domain = sys.argv[3] if len(sys.argv) > 3 else ""

try:
    raw = open(src, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(2)

raw = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", raw)
raw = raw.replace("\ufeff", "")
lines = [line.rstrip("\r") for line in raw.splitlines()]
lines = [line for line in lines if line.strip().upper() != "END"]


def write_netscape(rows):
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("# Netscape HTTP Cookie File\n")
        fh.write("# Chuyen tu dong boi TVDL\n\n")
        fh.write("\n".join(rows) + "\n")


# 1) Đã là Netscape (mỗi dòng >= 7 cột tab)
data_lines = [ln for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]
if data_lines and all(len(ln.split("\t")) >= 7 for ln in data_lines):
    write_netscape(["\t".join(ln.split("\t")[:7]) for ln in data_lines])
    sys.exit(0)


def truthy(value):
    return value is True or str(value).lower() in ("1", "true", "yes")


def expiry_of(cookie):
    if truthy(cookie.get("session")):
        return 0
    for key in ("expirationDate", "expiry", "expires", "expiration"):
        value = cookie.get(key)
        if value is None:
            continue
        try:
            return max(0, int(float(value)))
        except (TypeError, ValueError):
            continue
    return 0


# 2) JSON (Chrome, EditThisCookie, Firefox, Playwright...)
decoder = json.JSONDecoder()
start = -1
for ch in ("{", "["):
    pos = raw.find(ch)
    if pos != -1 and (start == -1 or pos < start):
        start = pos
if start != -1:
    try:
        data, _ = decoder.raw_decode(raw[start:])
    except ValueError:
        data = None
    if data is not None:
        if isinstance(data, dict):
            cookies = data.get("cookies") or data.get("Cookies") or []
        elif isinstance(data, list):
            cookies = data
        else:
            cookies = []
        rows = []
        for cookie in cookies if isinstance(cookies, list) else []:
            if not isinstance(cookie, dict):
                continue
            name = str(cookie.get("name") or "").strip()
            dom = str(cookie.get("domain") or "").strip()
            if not name or not dom:
                continue
            value = str(cookie.get("value") or "").replace("\r", "").replace("\n", "")
            path = str(cookie.get("path") or "/").strip() or "/"
            secure = "TRUE" if truthy(cookie.get("secure")) else "FALSE"
            if truthy(cookie.get("hostOnly")):
                dom = dom.lstrip(".")
                include = "FALSE"
            else:
                if not dom.startswith("."):
                    dom = "." + dom
                include = "TRUE"
            rows.append("\t".join([dom, include, path, secure,
                                   str(expiry_of(cookie)), name, value]))
        if rows:
            write_netscape(rows)
            sys.exit(0)

# 3) Chuỗi Cookie: "Cookie: a=b; c=d" hoặc "a=b; c=d"
text = "\n".join(lines).strip()
if not text:
    sys.exit(2)
s = text
if s.lower().startswith("cookie:"):
    s = s[len("cookie:"):]
s = s.strip().strip('"').strip("'").strip()
parts = [p.strip() for p in s.split(";") if p.strip()]
if not parts or not all("=" in p for p in parts):
    sys.exit(2)

if not domain:
    sys.exit(13)  # cần tên miền

dom = re.sub(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", "", domain.strip())
dom = dom.split("/")[0].split(":")[0].strip()
if not dom:
    sys.exit(2)
if not dom.startswith("."):
    dom = "." + dom

rows = []
for part in parts:
    name, value = part.split("=", 1)
    name = name.strip()
    value = value.strip().replace("\r", "").replace("\n", "")
    if not name:
        continue
    rows.append("\t".join([dom, "TRUE", "/", "FALSE", "0", name, value]))
if not rows:
    sys.exit(2)

write_netscape(rows)
sys.exit(0)
PYEOF
}

normalize_cookies_file() {
    # Tự nhận diện Netscape / JSON / chuỗi Cookie và chuẩn hóa tại chỗ.
    # Giữ bản gốc dưới <file>.bak, chỉ ghi khi nội dung mới hợp lệ.
    local f="$1"
    local domain="${2:-}"
    local backup="$f.bak"
    local tmp="$f.tmp.$$"
    local rc=0

    [[ -f "$f" ]] || return 1
    COOKIE_LAST_FORMAT="$(detect_cookie_format "$f")"
    cookies_file_is_netscape "$f" && return 0
    [[ -s "$f" ]] || return 1

    cookies_convert_file "$f" "$tmp" "$domain" || rc=$?
    if [[ $rc -eq 13 ]]; then
        rm -f "$tmp"
        log_info "Cookie ở dạng chuỗi 'name=value; ...' nên cần biết tên miền."
        if (( INTERACTIVE )); then
            read -rp "Tên miền của cookie (vd .facebook.com): " domain || domain=""
        fi
        if [[ -z "$domain" ]]; then
            log_fail "Thiếu tên miền, không thể tạo file cookie."
            return 1
        fi
        rc=0
        cookies_convert_file "$f" "$tmp" "$domain" || rc=$?
    fi

    if [[ $rc -eq 0 && -s "$tmp" ]] && cookies_file_is_netscape "$tmp"; then
        # File tạm (nội dung vừa dán/nhập) không cần sao lưu
        if [[ "$f" != "$TMP_DIR"/* ]]; then
            cp "$f" "$backup" 2>/dev/null || true
        fi
        if mv "$tmp" "$f" 2>/dev/null || cp "$tmp" "$f" 2>/dev/null; then
            rm -f "$tmp"
            chmod 600 "$f" 2>/dev/null || true
            log_ok "Đã chuẩn hóa cookie ($(cookies_count "$f") cookie)."
            if [[ "$f" != "$TMP_DIR"/* && -f "$backup" ]]; then
                log_info "Bản gốc: $backup"
            fi
            return 0
        fi
    fi

    rm -f "$tmp"
    log_warn "Nội dung cookie không hợp lệ (cần Netscape, JSON hoặc chuỗi Cookie:)."
    return 1
}

show_cookie_menu() {
    while true; do
        show_banner
        echo ""
        if [[ -f "$COOKIES_FILE" ]]; then
            echo -e "  Cookie hiện tại: ${C_GREEN}Đã nạp${C_RESET} ($(cookies_count "$COOKIES_FILE") cookie · $COOKIES_FILE)"
        else
            echo -e "  Cookie hiện tại: ${C_YELLOW}Chưa có${C_RESET}"
        fi
        echo ""
        echo "  1. Nạp cookie từ file (.txt Netscape hoặc .json)"
        echo "  2. Dán nội dung cookie (Netscape, JSON hoặc chuỗi Cookie:)"
        echo "  3. Xóa cookie đã lưu"
        echo "  4. Hướng dẫn lấy cookie Instagram/Facebook"
        echo "  0. Quay lại"
        read -rp "Chọn: " cchoice || return 0
        case "$cchoice" in
            1)
                echo "Nhận file Netscape (.txt) hoặc JSON (.json) — TVDL tự chuyển đổi."
                read -rp "Nhập đường dẫn file cookie: " cpath || cpath=""
                cpath="${cpath/#\~/$HOME}"
                if [[ -z "$cpath" || ! -f "$cpath" ]]; then
                    log_fail "Không tìm thấy file: $cpath"
                else
                    local tmpc="$TMP_DIR/cookies_import.$$"
                    rm -f "$tmpc" "$tmpc.bak"
                    echo "Đang kiểm tra cookie..."
                    if cp "$cpath" "$tmpc" 2>/dev/null && normalize_cookies_file "$tmpc"; then
                        mkdir -p "$STATE_DIR"
                        if [[ -f "$COOKIES_FILE" ]]; then
                            cp "$COOKIES_FILE" "$COOKIES_FILE.bak" 2>/dev/null || true
                        fi
                        if cp "$tmpc" "$COOKIES_FILE" 2>/dev/null; then
                            chmod 600 "$COOKIES_FILE"
                            resolve_ytdlp
                            show_cookie_result
                        else
                            log_fail "Không ghi được $COOKIES_FILE"
                        fi
                    else
                        log_warn "Không nạp; cookie cũ (nếu có) được giữ nguyên."
                    fi
                    rm -f "$tmpc" "$tmpc.bak"
                fi
                pause_screen
                ;;
            2)
                echo "Dán nội dung cookie: Netscape, JSON, hoặc chuỗi 'Cookie: a=b; c=d'."
                echo "Nhập xong, gõ một dòng END rồi Enter (hoặc nhấn Ctrl+D)."
                echo ""
                local tmpc="$TMP_DIR/cookies_paste.$$"
                rm -f "$tmpc" "$tmpc.bak"
                : > "$tmpc"
                while IFS= read -r line; do
                    line="${line%$'\r'}"
                    [[ "${line^^}" == "END" ]] && break
                    echo "$line" >> "$tmpc"
                done
                if [[ ! -s "$tmpc" ]]; then
                    rm -f "$tmpc" "$tmpc.bak"
                    log_warn "Không nhận được nội dung cookie."
                    pause_screen
                    continue
                fi
                echo "Đang kiểm tra cookie..."
                if normalize_cookies_file "$tmpc"; then
                    mkdir -p "$STATE_DIR"
                    if [[ -f "$COOKIES_FILE" ]]; then
                        cp "$COOKIES_FILE" "$COOKIES_FILE.bak" 2>/dev/null || true
                    fi
                    if cp "$tmpc" "$COOKIES_FILE" 2>/dev/null; then
                        chmod 600 "$COOKIES_FILE"
                        resolve_ytdlp
                        show_cookie_result
                    else
                        log_fail "Không ghi được $COOKIES_FILE"
                    fi
                else
                    log_warn "Cookie không hợp lệ; cookie cũ (nếu có) được giữ nguyên."
                fi
                rm -f "$tmpc" "$tmpc.bak"
                pause_screen
                ;;
            3)
                if [[ -f "$COOKIES_FILE" ]]; then
                    rm -f "$COOKIES_FILE"
                    resolve_ytdlp
                    log_ok "Đã xóa cookie."
                else
                    log_info "Chưa có cookie nào để xóa."
                fi
                pause_screen
                ;;
            4)
                echo ""
                echo "Cách lấy cookie Instagram/Facebook:"
                echo "  1. Trên điện thoại, cài extension \"Get cookies.txt LOCALLY\""
                echo "     (Kiwi Browser / Firefox đều dùng được tiện ích Chrome)."
                echo "  2. Đăng nhập Instagram/Facebook trên trình duyệt đó."
                echo "  3. Mở bài viết/video cần tải, bấm extension, chọn Export"
                echo "     (Netscape .txt hay JSON .json đều được)."
                echo "  4. Quay lại đây: mục 1 để nạp file, hoặc mục 2 để dán"
                echo "     trực tiếp nội dung cookie — TVDL tự nhận định dạng."
                echo ""
                echo "Lưu ý: không chia sẻ file cookie này cho ai, nó chứa"
                echo "phiên đăng nhập tài khoản của bạn."
                pause_screen
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 9c. INSTALL / UNINSTALL `tvdl` COMMAND + SELF UPDATE
# ---------------------------------------------------------------------------

script_path() {
    local src="${BASH_SOURCE[0]:-$0}"
    local resolved=""
    if command -v readlink >/dev/null 2>&1; then
        resolved="$(readlink -f -- "$src" 2>/dev/null || true)"
    fi
    [[ -n "$resolved" ]] && src="$resolved"
    case "$src" in
        /*) ;;
        *) src="$PWD/$src" ;;
    esac
    echo "$src"
}

install_bin_dir() {
    if [[ -n "${PREFIX:-}" && -d "$PREFIX/bin" ]]; then
        echo "$PREFIX/bin"
    elif is_termux && [[ -d "/data/data/com.termux/files/usr/bin" ]]; then
        echo "/data/data/com.termux/files/usr/bin"
    else
        echo "$HOME/.local/bin"
    fi
}

installed_path() {
    echo "$(install_bin_dir)/$INSTALL_NAME"
}

fix_shebang() {
    # Termux's bash lives outside /usr/bin; on regular Linux installs the
    # copied script needs the local bash path instead.
    local file="$1" bash_path
    is_termux && return 0
    bash_path="$(command -v bash 2>/dev/null || true)"
    [[ -n "$bash_path" ]] || return 0
    sed -i "1s|^#!.*|#!$bash_path|" "$file" 2>/dev/null || true
}

is_tvdl_script() {
    # Accept both the new marker and older TVDL copies installed manually
    # (before v1.3.0 the script had no marker).
    [[ -f "$1" ]] || return 1
    grep -q "$INSTALL_MARKER" "$1" 2>/dev/null && return 0
    head -n 12 "$1" 2>/dev/null | grep -q "TVDL - Termux Video Downloader" && return 0
    return 1
}

path_hint() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *)
            log_warn "$dir chưa có trong PATH."
            echo "  Thêm dòng sau vào ~/.bashrc rồi mở lại Termux:"
            echo "    export PATH=\"$dir:\$PATH\""
            ;;
    esac
}

install_command() {
    local src dir target
    src="$(script_path)"
    dir="$(install_bin_dir)"
    target="$dir/$INSTALL_NAME"

    if [[ ! -f "$src" ]]; then
        log_fail "Không tìm thấy file script: $src"
        return 1
    fi
    if ! mkdir -p "$dir" 2>/dev/null; then
        log_fail "Không tạo được thư mục: $dir"
        return 1
    fi
    if [[ -e "$target" && "$src" != "$target" ]] && ! is_tvdl_script "$target"; then
        log_warn "Đã có file khác tại $target."
        if (( ! ASSUME_YES )); then
            ask_yes_no "Ghi đè bằng TVDL?" || { log_warn "Đã hủy."; return 1; }
        fi
    fi

    if [[ "$src" == "$target" ]]; then
        chmod 755 "$target" 2>/dev/null || true
        log_ok "Lệnh tvdl đã nằm đúng vị trí: $target"
    else
        if ! cp "$src" "$target" 2>/dev/null; then
            log_fail "Không sao chép được vào $target (thiếu quyền?)."
            return 1
        fi
        chmod 755 "$target" 2>/dev/null || true
        fix_shebang "$target"
        log_ok "Đã cài lệnh: $target"
    fi

    path_hint "$dir"
    return 0
}

uninstall_command() {
    local target
    target="$(installed_path)"

    if [[ ! -e "$target" ]]; then
        log_info "Chưa cài lệnh tvdl ($target không tồn tại)."
        return 0
    fi
    if ! is_tvdl_script "$target"; then
        log_fail "Từ chối xóa: $target không phải do TVDL cài."
        return 1
    fi
    if (( ! ASSUME_YES )); then
        ask_yes_no "Gỡ lệnh tvdl tại $target?" || { log_warn "Đã hủy."; return 1; }
    fi

    if [[ "$(script_path)" == "$target" ]]; then
        log_warn "Bạn đang chạy chính file sắp xóa; phiên hiện tại vẫn tiếp tục bình thường."
    fi
    if ! rm -f "$target" 2>/dev/null; then
        log_fail "Không xóa được $target (thiếu quyền?)."
        return 1
    fi
    log_ok "Đã gỡ lệnh tvdl."
    return 0
}

show_install_status() {
    local target dir
    target="$(installed_path)"
    dir="$(install_bin_dir)"

    echo "TVDL:        v$APP_VERSION"
    echo "Đang chạy:   $(script_path)"
    echo "Vị trí cài:  $target"

    if [[ ! -e "$target" ]]; then
        echo "Trạng thái:  Chưa cài"
    elif is_tvdl_script "$target"; then
        echo "Trạng thái:  Đã cài"
    else
        echo "Trạng thái:  Có file khác cùng tên"
    fi

    case ":$PATH:" in
        *":$dir:"*) echo "PATH:        OK ($dir)" ;;
        *)          echo "PATH:        Thiếu $dir" ;;
    esac
}

update_tvdl() {
    local src tmp backup target new_version
    src="$(script_path)"
    mkdir -p "$TMP_DIR" 2>/dev/null || true
    tmp="$TMP_DIR/tvdl_update_$$.sh"

    if ! command -v curl >/dev/null 2>&1; then
        handle_error "Thiếu curl để cập nhật TVDL." "Cài bằng: pkg install curl"
        return 1
    fi

    echo "Đang kiểm tra bản mới từ GitHub..."
    if ! curl -fsSL --max-time 30 "$SELF_UPDATE_URL" -o "$tmp"; then
        rm -f "$tmp"
        handle_error "Không tải được bản cập nhật." "URL: $SELF_UPDATE_URL"
        return 1
    fi

    if [[ ! -s "$tmp" ]] || ! is_tvdl_script "$tmp" || ! bash -n "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        handle_error "Bản tải về không hợp lệ." "Đã hủy cập nhật, script hiện tại giữ nguyên."
        return 1
    fi

    if [[ "$(cat "$tmp")" == "$(cat "$src")" ]]; then
        rm -f "$tmp"
        log_ok "Bạn đang dùng bản mới nhất (v$APP_VERSION)."
        return 0
    fi

    new_version="$(sed -n 's/^APP_VERSION="\(.*\)"$/\1/p' "$tmp" | head -n1)"
    echo "Phiên bản hiện tại: v$APP_VERSION"
    echo "Phiên bản mới:      v${new_version:-?}"

    if (( ! ASSUME_YES )); then
        ask_yes_no "Cập nhật ngay?" || { rm -f "$tmp"; log_warn "Đã hủy."; return 1; }
    fi

    backup="$src.bak.$(date '+%Y%m%d-%H%M%S')"
    cp "$src" "$backup" 2>/dev/null || true
    if ! cat "$tmp" > "$src"; then
        log_fail "Không ghi được $src. Bản sao lưu: $backup"
        rm -f "$tmp"
        return 1
    fi
    chmod 755 "$src" 2>/dev/null || true
    fix_shebang "$src"
    rm -f "$tmp"
    log_ok "Đã cập nhật: $src"
    [[ -f "$backup" ]] && log_info "Bản sao lưu: $backup"

    target="$(installed_path)"
    if [[ -f "$target" && "$target" != "$src" ]] && is_tvdl_script "$target"; then
        if cp "$src" "$target" 2>/dev/null; then
            chmod 755 "$target" 2>/dev/null || true
            fix_shebang "$target"
            log_ok "Đã đồng bộ lệnh tvdl: $target"
        fi
    fi

    log_info "Khởi động lại TVDL để dùng bản mới."
    return 0
}

show_install_menu() {
    while true; do
        show_banner
        echo ""
        local target
        target="$(installed_path)"
        if is_tvdl_script "$target"; then
            echo -e "Lệnh tvdl: ${C_GREEN}Đã cài${C_RESET} ($target)"
        else
            echo -e "Lệnh tvdl: ${C_YELLOW}Chưa cài${C_RESET} ($target)"
        fi
        echo ""
        echo "  1. Cài đặt lệnh gõ nhanh tvdl"
        echo "  2. Gỡ lệnh tvdl"
        echo "  3. Xem trạng thái cài đặt"
        echo "  4. Cập nhật TVDL từ GitHub"
        echo "  0. Quay lại"
        read -rp "Chọn: " ichoice || return 0
        case "$ichoice" in
            1) install_command || true; pause_screen ;;
            2) uninstall_command || true; pause_screen ;;
            3) echo ""; show_install_status; pause_screen ;;
            4) update_tvdl || true; pause_screen ;;
            0) return ;;
            *) ;;
        esac
    done
}

show_help() {
    echo "${APP_NAME} v${APP_VERSION} — ${APP_AUTHOR} (${APP_URL})"
    echo ""
    echo "Cách dùng: ${INSTALL_NAME} [tuỳ chọn]"
    echo ""
    echo "  (không tuỳ chọn)   Mở menu chính"
    echo "  --install          Cài lệnh gõ nhanh '${INSTALL_NAME}' vào PATH"
    echo "  --uninstall        Gỡ lệnh '${INSTALL_NAME}' đã cài"
    echo "  --status           Xem trạng thái cài đặt lệnh '${INSTALL_NAME}'"
    echo "  --update           Cập nhật TVDL từ GitHub"
    echo "  --no-color         Tắt màu ANSI"
    echo "  -y, --yes          Không hỏi xác nhận (dùng với --install/--uninstall/--update)"
    echo "  -h, --help         Hiển thị trợ giúp này"
    echo "  -V, --version      Hiển thị phiên bản"
}

# ---------------------------------------------------------------------------
# 10. VIDEO INFO
# ---------------------------------------------------------------------------

get_video_info() {
    local url="$1"
    local info

    if ! have_ytdlp; then
        handle_error "Không tìm thấy yt-dlp." "Cài đặt bằng: python -m pip install -U yt-dlp"
        return 1
    fi

    local platform
    platform="$(detect_platform "$url")"
    echo "Nền tảng: $platform"
    echo "Đang lấy thông tin..."

    if ! info=$("${YTDLP_CMD[@]}" "${COOKIE_ARGS[@]}" --no-warnings --print '%(title)s|||%(uploader)s|||%(duration_string)s|||%(resolution)s' "$url" 2>"$TMP_DIR/tvdl_err.log"); then
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
    read -rp "Nhập URL video: " url || url=""
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }
    url="$(resolve_share_url "$url")"
    if [[ "$(detect_platform "$url")" == "Xiaohongshu" ]] && xhs_probe "$url"; then
        echo ""
        echo "Nền tảng:     Xiaohongshu"
        echo "Tiêu đề:      $XHS_TITLE"
        echo "Uploader:     ${XHS_UPLOADER:-Không rõ}"
        echo "Thời lượng:   $(format_ms_duration "$XHS_DURATION_MS")"
        echo "Độ phân giải: $(xhs_best_height)p"
        echo ""
        log_info "Đọc trực tiếp từ trang Xiaohongshu (không phụ thuộc extractor yt-dlp)."
    else
        get_video_info "$url" || true
    fi
    pause_screen
}

# ---------------------------------------------------------------------------
# 11. QUALITY SELECTION
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 10b. XIAOHONGSHU FALLBACK (yt-dlp chưa hỗ trợ cấu trúc trang mới)
# ---------------------------------------------------------------------------

format_ms_duration() {
    local ms="${1:-0}" s
    [[ "$ms" =~ ^[0-9]+$ ]] || ms=0
    s=$((ms / 1000))
    printf '%d:%02d' $((s / 60)) $((s % 60))
}

xhs_best_height() {
    local entry h best=0
    for entry in "${XHS_STREAMS[@]}"; do
        h="${entry%%|*}"
        [[ "$h" =~ ^[0-9]+$ ]] || continue
        (( h > best )) && best=$h
    done
    echo "$best"
}

xhs_safe_name() {
    printf '%s' "$1" | tr '/\\:*?"<>|' '_' | tr '\n\r\t' '   ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

xhs_unique_path() {
    local path="$1" dir base ext n=1
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    ext=""
    if [[ "$base" == *.* ]]; then
        ext=".${base##*.}"
        base="${base%.*}"
    fi
    while [[ -e "$dir/$base$ext" ]]; do
        path="$dir/$base ($n)$ext"
        n=$((n + 1))
    done
    echo "$path"
}

xhs_probe() {
    # Đọc trực tiếp trang Xiaohongshu và lấy link video CDN.
    # Dùng khi yt-dlp báo "No video formats found" (site đổi cấu trúc).
    local url="$1"
    local html="$TMP_DIR/xhs_page.html"
    local out cookie_opt=()

    XHS_TITLE=""; XHS_UPLOADER=""; XHS_DURATION_MS=0; XHS_STREAMS=()

    command -v curl >/dev/null 2>&1 || return 1
    mkdir -p "$TMP_DIR" 2>/dev/null || true
    [[ -f "$COOKIES_FILE" ]] && cookie_opt=(-b "$COOKIES_FILE")

    if ! curl -fsSL --compressed --max-time 30 \
        -A "Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36" \
        -H "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8" \
        "${cookie_opt[@]}" "$url" -o "$html" 2>/dev/null; then
        return 1
    fi

    out="$(python3 - "$html" <<'PYEOF'
import json
import re
import sys

try:
    html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(2)


def clean_js(text):
    out = []
    i = 0
    in_str = False
    esc = False
    while i < len(text):
        ch = text[i]
        if in_str:
            out.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            out.append(ch)
            i += 1
            continue
        if text.startswith("undefined", i):
            out.append("null")
            i += 9
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def find_note(node):
    if isinstance(node, dict):
        if "noteId" in node and ("video" in node or "imageList" in node):
            return node
        for value in node.values():
            found = find_note(value)
            if found:
                return found
    elif isinstance(node, list):
        for value in node:
            found = find_note(value)
            if found:
                return found
    return None


note = None
for match in re.finditer(r"window\.__[A-Z_]+__\s*=\s*", html):
    raw = html[match.end():]
    try:
        obj, _ = json.JSONDecoder().raw_decode(clean_js(raw).lstrip())
    except Exception:
        continue
    note = find_note(obj)
    if note:
        break

if not note:
    sys.exit(3)

title = str(note.get("title") or "").strip()
desc = str(note.get("desc") or "").strip()
if not title:
    title = desc.splitlines()[0] if desc else "Xiaohongshu"
user = note.get("user") or {}
uploader = user.get("nickname") or user.get("nickName") or ""

video = note.get("video") or {}
stream = (video.get("media") or {}).get("stream") or {}
rows = []
for codec, items in stream.items():
    if not isinstance(items, list):
        continue
    for item in items:
        if not isinstance(item, dict):
            continue
        link = item.get("masterUrl")
        if not link and item.get("backupUrls"):
            link = item["backupUrls"][0]
        if not link:
            continue
        try:
            height = int(item.get("height") or 0)
        except (TypeError, ValueError):
            height = 0
        try:
            bitrate = int(item.get("avgBitrate") or 0)
        except (TypeError, ValueError):
            bitrate = 0
        try:
            duration = int(item.get("duration") or 0)
        except (TypeError, ValueError):
            duration = 0
        rows.append((height, bitrate, duration, str(codec), str(link)))

if not rows:
    key = (video.get("consumer") or {}).get("originVideoKey")
    if key:
        rows.append((0, 0, 0, "direct", "https://sns-video-bd.xhscdn.com/" + str(key)))

if not rows:
    sys.exit(4)


def flat(value):
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()


print("TITLE\t" + flat(title))
print("UPLOADER\t" + flat(uploader))
print("DURATION\t" + str(max(row[2] for row in rows)))
for height, bitrate, _duration, codec, link in sorted(rows, key=lambda r: (r[0], r[1])):
    print("STREAM\t%d\t%d\t%s\t%s" % (height, bitrate, codec, link))
PYEOF
)" || return 1

    [[ -n "$out" ]] || return 1

    local kind a b c d
    while IFS=$'\t' read -r kind a b c d; do
        case "$kind" in
            TITLE)    XHS_TITLE="$a" ;;
            UPLOADER) XHS_UPLOADER="$a" ;;
            DURATION) XHS_DURATION_MS="${a:-0}" ;;
            STREAM)   [[ -n "$d" ]] && XHS_STREAMS+=("$a|$b|$c|$d") ;;
        esac
    done <<< "$out"

    ((${#XHS_STREAMS[@]} > 0)) || return 1
    return 0
}

xhs_pick_stream() {
    # $1 = lựa chọn chất lượng 1-8; trả về height|bitrate|codec|url
    # Ưu tiên h264 khi cùng độ phân giải (dễ phát trên mọi máy).
    local choice="$1"
    local target=0
    local entry h t codec link rank
    local best="" best_h=-1 best_t=-1 best_rank=-1
    local fallback="" fallback_h=999999 fallback_t=-1 fallback_rank=-1

    case "$choice" in
        2) target=2160 ;;
        3) target=1440 ;;
        4) target=1080 ;;
        5) target=720 ;;
        6) target=480 ;;
        7) target=360 ;;
        *) target=0 ;;
    esac

    for entry in "${XHS_STREAMS[@]}"; do
        IFS='|' read -r h t codec link <<< "$entry"
        [[ "$h" =~ ^[0-9]+$ ]] || h=0
        [[ "$t" =~ ^[0-9]+$ ]] || t=0
        case "$codec" in
            h264) rank=2 ;;
            *)    rank=1 ;;
        esac

        if (( target == 0 )); then
            if (( h > best_h )) || { (( h == best_h )) && { (( t > best_t )) || { (( t == best_t )) && (( rank > best_rank )); }; }; }; then
                best="$entry"; best_h=$h; best_t=$t; best_rank=$rank
            fi
        else
            if (( h <= target )); then
                if (( h > best_h )) || { (( h == best_h )) && { (( t > best_t )) || { (( t == best_t )) && (( rank > best_rank )); }; }; }; then
                    best="$entry"; best_h=$h; best_t=$t; best_rank=$rank
                fi
            fi
            if (( h < fallback_h )) || { (( h == fallback_h )) && { (( rank > fallback_rank )) || { (( rank == fallback_rank )) && (( t > fallback_t )); }; }; }; then
                fallback="$entry"; fallback_h=$h; fallback_t=$t; fallback_rank=$rank
            fi
        fi
    done

    if [[ -n "$best" ]]; then
        echo "$best"
    else
        echo "$fallback"
    fi
}

xhs_download_entry() {
    # $1 = height|bitrate|codec|url, $2 = video|audio, $3 = audio format
    local entry="$1" mode="$2" afmt="${3:-mp3}"
    local h t codec link name out tmp
    local codecarg=()

    IFS='|' read -r h t codec link <<< "$entry"
    if [[ -z "$link" ]]; then
        handle_error "Không có URL video Xiaohongshu." "Thử lại hoặc nạp cookie (menu 10)."
        return 1
    fi

    mkdir -p "$DOWNLOAD_DIR"
    name="$(xhs_safe_name "${XHS_TITLE:-xiaohongshu}")"
    log_info "Luồng video: ${h}p (${codec:-?})"

    if [[ "$mode" == "audio" ]]; then
        tmp="$DOWNLOAD_DIR/.tvdl_xhs_$$.mp4"
        echo "Đang tải video tạm để tách audio..."
        if ! curl -fL --progress-bar -o "$tmp" "$link"; then
            rm -f "$tmp"
            handle_error "Không tải được video Xiaohongshu." "URL CDN có thể đã hết hạn; thử lại sau."
            return 1
        fi
        case "$afmt" in
            m4a)  codecarg=(-c:a aac -b:a 192k) ;;
            opus) codecarg=(-c:a libopus -b:a 128k) ;;
            *)    codecarg=(-c:a libmp3lame -q:a 2) ;;
        esac
        out="$(xhs_unique_path "$DOWNLOAD_DIR/$name.$afmt")"
        echo "Đang tách audio..."
        if ffmpeg -y -loglevel error -i "$tmp" -vn "${codecarg[@]}" "$out"; then
            rm -f "$tmp"
            log_ok "Đã tải audio: $(basename "$out") ($(du -h "$out" 2>/dev/null | cut -f1))"
            log_history "Xiaohongshu" "${CURRENT_URL:-$link}" "$(basename "$out")" "$(du -h "$out" 2>/dev/null | cut -f1)" "OK"
            return 0
        fi
        rm -f "$tmp"
        handle_error "Không tách được audio." "Kiểm tra ffmpeg (pkg install ffmpeg)."
        return 1
    fi

    out="$(xhs_unique_path "$DOWNLOAD_DIR/$name.mp4")"
    echo "Đang tải..."
    if curl -fL --progress-bar -o "$out" "$link"; then
        log_ok "Đã tải: $(basename "$out") ($(du -h "$out" 2>/dev/null | cut -f1))"
        log_history "Xiaohongshu" "${CURRENT_URL:-$link}" "$(basename "$out")" "$(du -h "$out" 2>/dev/null | cut -f1)" "OK"
        return 0
    fi
    rm -f "$out"
    handle_error "Không tải được video Xiaohongshu." "URL CDN có thể đã hết hạn; thử lại hoặc cập nhật TVDL."
    return 1
}


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

valid_quality() {
    [[ "${1:-}" =~ ^[1-8]$ ]]
}

ask_quality() {
    # $1 = prompt label. Only the chosen value goes to stdout, so callers can
    # safely use qchoice="$(ask_quality ...)".
    local title="$1"
    local default="$DEFAULT_QUALITY"
    local qchoice
    valid_quality "$default" || default="1"

    read -rp "${title} (1-8) [mặc định $default]: " qchoice || qchoice=""
    qchoice="${qchoice:-$default}"
    valid_quality "$qchoice" || qchoice="$default"
    echo "$qchoice"
}

ask_audio_format() {
    # $1 = default choice. Menu text goes to stderr, result to stdout.
    local default="$1"
    local achoice afmt
    case "$AUDIO_FORMAT" in
        m4a) default=2 ;;
        opus) default=3 ;;
    esac

    {
        echo ""
        echo "Chọn định dạng audio:"
        echo "  1. MP3"
        echo "  2. M4A"
        echo "  3. OPUS"
    } >&2
    read -rp "Chọn [mặc định $default]: " achoice || achoice=""
    achoice="${achoice:-$default}"
    case "$achoice" in
        2|m4a) afmt="m4a" ;;
        3|opus) afmt="opus" ;;
        *) afmt="mp3" ;;
    esac
    echo "$afmt"
}

# ---------------------------------------------------------------------------
# 12. DOWNLOAD VIDEO
# ---------------------------------------------------------------------------

download_video() {
    show_banner
    echo ""
    echo "Nhập URL Facebook, YouTube, Instagram, X (Twitter) hoặc Xiaohongshu:"
    read -rp "> " url || url=""
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }
    url="$(resolve_share_url "$url")"

    local platform
    platform="$(detect_platform "$url")"
    echo ""
    echo "Nền tảng: $platform"

    if [[ "$platform" == "Không xác định" ]]; then
        log_warn "URL không thuộc YouTube, Facebook, Instagram, X hoặc Xiaohongshu. yt-dlp sẽ vẫn thử tải."
    fi

    local is_xhs=0
    if [[ "$platform" == "Xiaohongshu" ]] && xhs_probe "$url"; then
        is_xhs=1
        TITLE="$XHS_TITLE"
        UPLOADER="$XHS_UPLOADER"
        DURATION="$(format_ms_duration "$XHS_DURATION_MS")"
        RESOLUTION="$(xhs_best_height)p"
        echo ""
        echo "Tiêu đề:      $TITLE"
        echo "Uploader:     ${UPLOADER:-Không rõ}"
        echo "Thời lượng:   $DURATION"
        echo "Độ phân giải: $RESOLUTION"
        echo ""
    else
        if ! have_ytdlp; then
            handle_error "Không tìm thấy yt-dlp." "Cài đặt bằng: python -m pip install -U yt-dlp"
            return
        fi
        get_video_info "$url" || return 0
    fi

    echo ""
    show_formats
    local qchoice
    qchoice="$(ask_quality "Chọn")"
    local fmt
    fmt="$(quality_to_format_string "$qchoice")"

    if [[ "$is_xhs" == "1" ]]; then
        CURRENT_URL="$url"
        local selected
        selected="$(xhs_pick_stream "$qchoice")"
        if [[ -z "$selected" ]]; then
            handle_error "Không tìm thấy luồng video Xiaohongshu." "Trang có thể yêu cầu đăng nhập (menu 10)."
            return 0
        fi
        echo ""
        echo "Tiêu đề:      $TITLE"
        echo "Nền tảng:     Xiaohongshu"
        echo "Thời lượng:   $DURATION"
        echo "Chất lượng:   ${selected%%|*}p"
        echo "Thư mục:      $DOWNLOAD_DIR"
        echo ""
        if ! ask_yes_no "Bắt đầu tải?"; then
            log_warn "Đã hủy."
            pause_screen
            return
        fi
        if [[ "$qchoice" == "8" ]]; then
            local afmt
            afmt="$(ask_audio_format "$AUDIO_FORMAT")"
            AUDIO_FORMAT="$afmt"
            save_config
            xhs_download_entry "$selected" audio "$afmt" || true
        else
            xhs_download_entry "$selected" video || true
        fi
        pause_screen
        return
    fi

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
    # %(playlist_index&...)s only adds a suffix when the URL is an album/carousel
    # (multiple photos/videos in one post) so items don't overwrite each other;
    # a normal single video/photo keeps a plain filename.
    local outtmpl="$DOWNLOAD_DIR/%(title)s%(playlist_index&_{}|)s.%(ext)s"

    echo ""
    echo "Downloading..."
    local log_file="$TMP_DIR/tvdl_dl.log"
    local start_marker="$TMP_DIR/.dl_marker_$$"
    touch "$start_marker"
    set +e
    "${YTDLP_CMD[@]}" "${COOKIE_ARGS[@]}" -f "$fmt" --merge-output-format mp4 -c --no-warnings --ignore-errors --restrict-filenames -o "$outtmpl" "$url" 2>&1 | tee "$log_file"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -ne 0 ]]; then
        # Try nearest quality if requested one not found
        # (yt-dlp's actual message is "Requested format is not available.")
        if grep -qiE "requested format( is)? not available" "$log_file"; then
            log_warn "Không tìm thấy chất lượng đã chọn."
            if ask_yes_no "Thử tự động chọn chất lượng gần nhất có sẵn?"; then
                local fallback_fmt
                for fallback_fmt in "bv*+ba/b" "b"; do
                    [[ "$fallback_fmt" == "$fmt" ]] && continue
                    set +e
                    "${YTDLP_CMD[@]}" "${COOKIE_ARGS[@]}" -f "$fallback_fmt" --merge-output-format mp4 -c --no-warnings --ignore-errors --restrict-filenames -o "$outtmpl" "$url" 2>&1 | tee "$log_file"
                    rc=${PIPESTATUS[0]}
                    set -e
                    [[ $rc -eq 0 ]] && break
                done
            fi
        fi
    fi

    # Collect every file this run produced (an album/carousel yields more than one)
    local new_files=()
    while IFS= read -r -d '' f; do
        new_files+=("$f")
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -newer "$start_marker" -print0 2>/dev/null)
    rm -f "$start_marker"

    if [[ $rc -eq 0 && ${#new_files[@]} -gt 0 ]]; then
        log_ok "Tải thành công (${#new_files[@]} file)"
        echo ""
        echo "File:"
        local f size last_name="-" last_size="Không rõ"
        for f in "${new_files[@]}"; do
            size=$(du -h "$f" 2>/dev/null | cut -f1)
            echo "  ${f#"$DOWNLOAD_DIR"/}  ($size)"
            last_name="$(basename "$f")"
            last_size="$size"
        done
        log_history "$platform" "$url" "$last_name" "$last_size" "OK"
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
    read -rp "> " url || url=""
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }
    url="$(resolve_share_url "$url")"

    if ! have_ytdlp; then
        handle_error "Không tìm thấy yt-dlp."
        return
    fi

    local range_args=()
    if ask_yes_no "Tải toàn bộ playlist?"; then
        range_args=()
    else
        echo "1. Tất cả"
        echo "2. Video 1-10"
        echo "3. Chỉ video được chọn (nhập chỉ số, ví dụ 1,3,5)"
        read -rp "Chọn: " rchoice || rchoice=""
        case "$rchoice" in
            2) range_args=(--playlist-items "1-10") ;;
            3)
                read -rp "Nhập danh sách chỉ số (vd 1,3,5): " idxs || idxs=""
                if [[ -n "$idxs" ]]; then
                    range_args=(--playlist-items "$idxs")
                fi
                ;;
            *) range_args=() ;;
        esac
    fi

    show_formats
    local qchoice
    qchoice="$(ask_quality "Chọn")"
    local fmt
    fmt="$(quality_to_format_string "$qchoice")"

    local audio_fmt=""
    if [[ "$fmt" == "audio-only" ]]; then
        fmt="ba/b"
        audio_fmt="$(ask_audio_format "$AUDIO_FORMAT")"
    fi

    local merge_args=()
    local extra_args=()
    if [[ -n "$audio_fmt" ]]; then
        extra_args=(-x --audio-format "$audio_fmt")
    else
        merge_args=(--merge-output-format mp4)
    fi

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
    "${YTDLP_CMD[@]}" "${COOKIE_ARGS[@]}" "${range_args[@]}" "${extra_args[@]}" "${merge_args[@]}" \
        -f "$fmt" -c --no-warnings --ignore-errors --restrict-filenames -o "$outtmpl" "$url" 2>&1 | tee "$log_file"
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
    read -rp "> " url || url=""
    [[ -z "$url" ]] && { log_warn "URL trống."; pause_screen; return; }
    url="$(resolve_share_url "$url")"
    if [[ "$(detect_platform "$url")" == "Xiaohongshu" ]] && xhs_probe "$url"; then
        CURRENT_URL="$url"
        local afmt selected
        afmt="$(ask_audio_format "$AUDIO_FORMAT")"
        AUDIO_FORMAT="$afmt"
        save_config
        echo ""
        echo "Nền tảng:  Xiaohongshu"
        echo "Tiêu đề:   $XHS_TITLE"
        echo "Định dạng: $afmt"
        echo "Thư mục:   $DOWNLOAD_DIR"
        if ! ask_yes_no "Bắt đầu tải audio?"; then
            log_warn "Đã hủy."
            pause_screen
            return
        fi
        selected="$(xhs_pick_stream 1)"
        xhs_download_entry "$selected" audio "$afmt" || true
        pause_screen
        return
    fi
    download_audio_with_url "$url"
}

download_audio_with_url() {
    local url="$1"

    if ! have_ytdlp; then
        handle_error "Không tìm thấy yt-dlp."
        return
    fi

    local afmt
    afmt="$(ask_audio_format "$AUDIO_FORMAT")"
    AUDIO_FORMAT="$afmt"
    save_config

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
    local outtmpl="$DOWNLOAD_DIR/%(title)s%(playlist_index&_{}|)s.%(ext)s"
    local log_file="$TMP_DIR/tvdl_audio.log"
    local start_marker="$TMP_DIR/.dl_marker_$$"
    touch "$start_marker"

    set +e
    "${YTDLP_CMD[@]}" "${COOKIE_ARGS[@]}" -x --audio-format "$afmt" -c --no-warnings --ignore-errors --restrict-filenames -o "$outtmpl" "$url" 2>&1 | tee "$log_file"
    local rc=${PIPESTATUS[0]}
    set -e

    local new_files=()
    while IFS= read -r -d '' f; do
        new_files+=("$f")
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -newer "$start_marker" -print0 2>/dev/null)
    rm -f "$start_marker"

    if [[ $rc -eq 0 && ${#new_files[@]} -gt 0 ]]; then
        log_ok "Tải audio thành công (${#new_files[@]} file)"
        local f last_name="-"
        for f in "${new_files[@]}"; do
            echo "  ${f#"$DOWNLOAD_DIR"/}"
            last_name="$(basename "$f")"
        done
        log_history "$platform" "$url" "$last_name" "-" "OK"
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
        read -rp "Chọn: " hchoice || return 0
        local hist_file err_file
        hist_file="$(get_history_file)"
        err_file="$(get_error_log_file)"
        case "$hchoice" in
            1)
                echo ""
                if [[ -s "$hist_file" ]]; then
                    if command -v column >/dev/null 2>&1; then
                        tail -n 50 "$hist_file" | column -t -s '|'
                    else
                        tail -n 50 "$hist_file"
                    fi
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
                read -rp "Nhập từ khóa: " kw || kw=""
                echo ""
                if [[ -n "$kw" ]]; then
                    grep -i --color=never -- "$kw" "$hist_file" || log_info "Không tìm thấy."
                else
                    log_info "Từ khóa trống."
                fi
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
        read -rp "Chọn: " dchoice || return 0
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
                read -rp "Nhập đường dẫn thư mục mới: " newdir || newdir=""
                newdir="${newdir/#\~/$HOME}"
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
    local old_version="Không rõ"
    if have_ytdlp; then
        old_version=$("${YTDLP_CMD[@]}" --version 2>/dev/null || echo "Không rõ")
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

    resolve_ytdlp
    local new_version="Không rõ"
    if have_ytdlp; then
        new_version=$("${YTDLP_CMD[@]}" --version 2>/dev/null || echo "Không rõ")
    fi
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

    echo "TVDL:         v$APP_VERSION"

    if is_termux; then echo "Termux:       OK"; else echo "Termux:       Không phát hiện"; fi

    if command -v python3 >/dev/null 2>&1; then
        echo "Python:       $(python3 --version 2>&1 | awk '{print $2}')"
    elif command -v python >/dev/null 2>&1; then
        echo "Python:       $(python --version 2>&1 | awk '{print $2}')"
    else
        echo "Python:       [✗] Chưa cài"
    fi

    if have_ytdlp; then
        echo "yt-dlp:       $("${YTDLP_CMD[@]}" --version 2>/dev/null || echo "Không rõ")"
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

    if is_tvdl_script "$(installed_path)"; then
        echo "Lệnh tvdl:     OK ($(installed_path))"
    else
        echo "Lệnh tvdl:     Chưa cài (menu 11 hoặc --install)"
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
    read -rp "Chọn chất lượng mặc định (1-8) [hiện tại: $DEFAULT_QUALITY]: " qchoice || qchoice=""
    if [[ -n "$qchoice" ]]; then
        if valid_quality "$qchoice"; then
            DEFAULT_QUALITY="$qchoice"
            save_config
            log_ok "Đã lưu chất lượng mặc định: $qchoice"
        else
            log_fail "Chỉ nhận giá trị 1-8."
        fi
    fi
    pause_screen
}

# ---------------------------------------------------------------------------
# 20. MAIN LOOP
# ---------------------------------------------------------------------------

main() {
    setup_colors

    case "$ACTION" in
        help) show_help; exit 0 ;;
        version) echo "${APP_NAME} v${APP_VERSION}"; exit 0 ;;
        badarg)
            log_fail "Tham số không hợp lệ: $BAD_ARG"
            echo ""
            show_help
            exit 2
            ;;
        install)
            load_config
            setup_colors
            if install_command; then exit 0; else exit 1; fi
            ;;
        uninstall)
            load_config
            setup_colors
            if uninstall_command; then exit 0; else exit 1; fi
            ;;
        status)
            load_config
            setup_colors
            show_install_status
            exit 0
            ;;
        update)
            load_config
            setup_colors
            if update_tvdl; then exit 0; else exit 1; fi
            ;;
    esac

    load_config
    setup_colors   # re-apply in case COLOR came from config
    check_dependencies
    check_storage || true

    while true; do
        show_menu
        case "$MENU_CHOICE" in
            1) download_video || true ;;
            2) download_playlist || true ;;
            3) choose_default_quality || true ;;
            4) download_audio || true ;;
            5) show_video_info_menu || true ;;
            6) show_history || true ;;
            7) show_download_dir_menu || true ;;
            8) update_ytdlp || true ;;
            9) system_check || true ;;
            10) show_cookie_menu || true ;;
            11) show_install_menu || true ;;
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
