#!/bin/bash
# fm - a simple file viewer & manager
# Version 1.0

# color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# global variables
declare -a FILES # file list
declare -a FILETYPES # file type list  
CURRENT_DIR="$(pwd)" 

# file type detection function
file_type_detailed() {
    local file="$1"

    # directory check
    if [[ -d "$file" ]]; then
        echo "dir"
    elif [[ -x "$file" && -f "file" ]]; then
        if file "$file" | grep -q "text"; then
            echo "script"
        else
            echo "exec"
        fi
    elif [[ -f "$file" ]]; then
        case "${file##*.}" in
            txt|md|readme) echo "text" ;;
            sh|bash|zsh) echo "shell" ;;
            py|python) echo "python" ;;
            js|json) echo "javascript" ;;
            html|htm) echo "web" ;;
            css) echo "style" ;;
            jpg|jpeg|png|gif|bmp) echo "image" ;;
            mp3|wav|flac) echo "audio" ;;
            mp4|avi|mkv) echo "video" ;;
            pdf) echo "pdf" ;;
            zip|tar|gz|7z) echo "archive" ;;
            log) echo "log" ;;
            *)
                if file "$file" | grep -q "text"; then
                    echo "text"
                else
                    echo "binary"
                fi
            ;;
        esac
    else
        echo "unknown"
    fi
}

# 파일 크기를 읽기 쉬운 형식으로 변환
format_size() {
    local bytes="$1"
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B --padding=8 "$bytes" 2>/dev/null || echo "${bytes}B"
    else
        if (( bytes >= 1073741824 )); then
            printf "%.1fGB" "$((bytes * 10 / 1073741824))e-1"
        elif (( bytes >= 1048576 )); then
            printf "%.1fMB" "$((bytes * 10 / 1048576))e-1"
        elif (( bytes >= 1024 )); then
            printf "%.1fKB" "$((bytes * 10 / 1024))e-1"
        else
            printf "%dB" "$bytes"
        fi
    fi
}

# 줄 번호와 함께 파일 내용 출력 (주석 강조)
print_file_with_lines() {
    local file="$1"
    local line_num=1

    echo -e "${CYAN}📄 파일 내용 보기 : ${WHITE}$file${RESET}"
    echo "================================================================================"

    if [[ ! -r "$file" ]]; then
        echo -e "${RED}❌ 파일을 읽을 수 없습니다: $file${RESET}"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            # 주석 라인은 초록색으로 출력
            printf "${YELLOW}%02d${RESET} ${GREEN}%s${RESET}\n" "$line_num" "$line"
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            # 빈 라인
            printf "${YELLOW}%02d${RESET} \n" "$line_num"
        else
            # 일반 라인은 기본 색상으로 출력
            printf "${YELLOW}%02d${RESET} %s\n" "$line_num" "$line"
        fi
        ((line_num++))
    done < "$file"
}

# 파일 목록 출력
list_files() {
    local dir="${1:-.}"
    FILES=()
    FILETYPES=()

    echo -e "${BLUE}📁 현재 디렉토리: ${WHITE}$(realpath "$dir")${RESET}"
    echo "=============================================="

    # 헤더 출력
    printf "${WHITE}%-4s %-25s %-12s %-9s %-9s %-9s %-12s${RESET}\n" \
           "번호" "파일명" "수정일" "크기" "소유자" "그룹" "권한"
    echo "================================================================================"

    local count=1

    # 현재 디렉토리가 루트가 아니면 상위 디렉토리 항목 추가
    if [[ "$dir" != "/" ]]; then
        FILES+=("..")
        FILETYPES+=("parent")
        printf "${CYAN}%-4d${RESET} ${BLUE}%-25s${RESET} %-12s %-9s %-9s %-9s %-12s\n" \
               "$count" ".." "--------" "-----" "---" "---" "drwxr-xr-x"
        ((count++))
    fi

    # 파일과 디렉토리 처리
    for file in "$dir"/*; do
        [[ ! -e "$file" ]] && continue

        local basename_file=$(basename "$file")
        FILES+=("$file")

        # 파일 정보 수집
        local mod_time=$(date -r "$file" +"%Y-%m-%d" 2>/dev/null || echo "unknown")
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        local size=$(format_size "$file_size")
        local owner=$(stat -f%Su "$file" 2>/dev/null || stat -c%U "$file" 2>/dev/null || echo "unknown")
        local group=$(stat -f%Sg "$file" 2>/dev/null || stat -c%G "$file" 2>/dev/null || echo "unknown")
        local perm=$(stat -f%Sp "$file" 2>/dev/null || stat -c%A "$file" 2>/dev/null || echo "unknown")
        local ftype=$(file_type_detailed "$file")

        FILETYPES+=("$ftype")

        # 파일 타입별 색상 및 아이콘
        local color=""
        local icon=""
        case "$ftype" in
            "dir") color="$BLUE"; icon="📁" ;;
            "exec") color="$GREEN"; icon="⚡" ;;
            "script"|"shell") color="$GREEN"; icon="📜" ;;
            "text") color="$WHITE"; icon="📄" ;;
            "image") color="$MAGENTA"; icon="🖼️" ;;
            "archive") color="$YELLOW"; icon="📦" ;;
            "log") color="$CYAN"; icon="📋" ;;
            *) color="$WHITE"; icon="📄" ;;
        esac

        printf "${CYAN}%-4d${RESET} ${color}%-25s${RESET} %-12s %-9s %-9s %-9s %-12s\n" \
               "$count" "$basename_file" "$mod_time" "$size" "$owner" "$group" "$perm"

        ((count++))
    done

    echo "=============================================="
    echo -e "${GREEN}✅ 완료${RESET}"
}

# 파일 작업 메뉴
file_menu() {
    local file="$1"
    local ftype="$2"

    echo ""
    echo "=============================================="
    echo -e "${YELLOW}📁 파일 작업 메뉴: ${WHITE}$(basename "$file")${RESET}"
    echo "=============================================="
    echo "[1] 파일 내용으로 들어가기"
    echo "[2] 파일 수정"
    echo "[3] 파일 삭제"
    echo "[c] 취소"
    echo "[0] 프로그램 종료"
    echo "=============================================="

    while true; do
        echo -ne "${CYAN}메뉴 선택 >>> ${RESET}"
        read -r choice

        case "$choice" in
            1)
                if [[ "$ftype" == "dir" ]]; then
                    if [[ "$(basename "$file")" == ".." ]]; then
                        CURRENT_DIR=$(dirname "$CURRENT_DIR")
                    else
                        CURRENT_DIR="$file"
                    fi
                    return 0
                elif [[ "$ftype" == "parent" ]]; then
                    CURRENT_DIR=$(dirname "$CURRENT_DIR")
                    return 0
                elif [[ -f "$file" ]]; then
                    print_file_with_lines "$file"
                    echo ""
                    echo -e "${GREEN}파일을 확인했습니다. 엔터를 눌러 계속...${RESET}"
                    read -r
                    return 0
                else
                    echo -e "${RED}❌ 읽을 수 없는 파일입니다.${RESET}"
                fi
                ;;
            2)
                if [[ -f "$file" && -w "$file" ]]; then
                    echo -e "${YELLOW}vi로 파일을 편집합니다...${RESET}"
                    vi "$file"
                    return 0
                else
                    echo -e "${RED}❌ 편집할 수 없는 파일입니다.${RESET}"
                fi
                ;;
            3)
                echo -ne "${RED}정말로 '$file' 파일을 삭제하시겠습니까? (y/N) ${RESET}"
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if rm -rf "$file" 2>/dev/null; then
                        echo -e "${GREEN}✅ 파일이 삭제되었습니다.${RESET}"
                    else
                        echo -e "${RED}❌ 파일 삭제에 실패했습니다.${RESET}"
                    fi
                    sleep 2
                    return 0
                else
                    echo -e "${YELLOW}삭제가 취소되었습니다.${RESET}"
                fi
                ;;
            c|C)
                echo -e "${YELLOW}파일 목록으로 돌아갑니다.${RESET}"
                return 0
                ;;
            0)
                echo -e "${YELLOW}🔸 프로그램을 종료합니다.${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 잘못된 선택입니다. 다시 선택해주세요.${RESET}"
                ;;
        esac
    done
}

# 메인 루프
main() {
    while true; do
        clear
        list_files "$CURRENT_DIR"

        echo ""
        echo "[>>] 원하는 파일 번호를 입력하세요"
        echo "[c] 취소 (현재 화면 새로고침)"
        echo "[0] 종료"
        echo "================================================================================"

        while true; do
            echo -ne "${CYAN}번호 입력 >>> ${RESET}"
            read -r selection

            if [[ "$selection" == "0" ]]; then
                echo -e "${YELLOW}🔸 프로그램을 종료합니다.${RESET}"
                echo -e "${RESET}"
                exit 0
            elif [[ "$selection" == "c" || "$selection" == "C" ]]; then
                echo -e "${YELLOW}화면을 새로고침합니다.${RESET}"
                break
            elif [[ "$selection" =~ ^[0-9]+$ ]] && (( selection > 0 && selection <= ${#FILES[@]} )); then
                local selected_file="${FILES[$((selection-1))]}"
                local selected_type="${FILETYPES[$((selection-1))]}"
                file_menu "$selected_file" "$selected_type"
                break
            else
                echo -e "${RED}❌ 잘못된 번호입니다. 다시 입력해주세요. (1-${#FILES[@]}, c, 0 중 선택)${RESET}"
            fi
        done
    done
}

# 프로그램 시작
echo -e "${BLUE}================================================${RESET}"
echo -e "${WHITE}    🔍 File Viewer & Manager 시작${RESET}"
echo -e "${BLUE}================================================${RESET}"

main