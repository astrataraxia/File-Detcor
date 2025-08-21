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

    # check if file exists
    if [[ ! -e "$file" ]]; then
        echo "notfound"
        return 1
    fi

    # check if file is a symbolic link
    if [[ -L "$file" ]]; then
        echo "link"
        return 0
    fi

    # check if file is a directory
    if [[ -d "$file" ]]; then
        echo "dir"
        return 0
    fi

    #Special files unless they are regular files
    if [[ ! -f "$file" ]]; then
        echo "special"
        return 0
    fi

    local basename_file=$(basename "$file")
    local extension="${file##*.}"
    local filename_lower="${basename_file,,}" # 소문자로 변환

    # 
    case "$extension" in
        # text
        txt|md|readme|rst|asciidoc) echo "text" ;;

        # config
        conf|config|cfg|ini|yml|yaml|toml|json) echo "config" ;;

        # shell script
        sh|bash|zsh|fish|csh|tcsh) echo "shell" ;;

        # programing language
        py|python|pyw) echo "python" ;;
        js|mjs|jsx|ts|tsx) echo "javascript" ;;
        c|h|cpp|cxx|cc|hpp) echo "c_cpp" ;;
        java|class|jar) echo "java" ;;
        php|php3|php4|php5) echo "php" ;;
        rb|ruby) echo "ruby" ;;
        go) echo "golang" ;;
        rs|rust) echo "rust" ;;

        # web
        html|htm|xhtml) echo "web" ;;
        css|scss|sass|less) echo "style" ;;
        xml|xsl|xsd) echo "xml" ;;

        # image
        jpg|jpeg|png|gif|bmp|tiff|tif|webp|svg|ico) echo "image" ;;

        # audio
        mp3|wav|flac|aac|ogg|m4a|wma) echo "audio" ;;

        # video
        mp4|avi|mkv|mov|wmv|flv|webm|m4v) echo "video" ;;

        # document
        pdf|doc|docx|odt|rtf) echo "document" ;;
        xls|xlsx|ods|csv) echo "spreadsheet" ;;
        ppt|pptx|odp) echo "presentation" ;;

        # archive
        zip|rar|7z|tar|gz|bz2|xz|lz|lzma) echo "archive" ;;

        # log files
        log|out|err) echo "log" ;;

        # binary/executable file (확장자 없는 경우 포함)
        exe|bin|deb|rpm|dmg|msi) echo "binary" ;;

        *)
            case "$filename_lower" in
                makefile|dockerfile|vagrantfile) echo "config" ;;
                readme*|license*|changelog*|todo*) echo "text" ;;
                *.bak|*.backup|*.tmp|*.temp) echo "backup" ;;
                core|core.*) echo "coredump" ;;
                *)
                    if [[ -x "$file" ]]; then
                        local file_output=$(file -b "$file" 2>/dev/null)
                        case "$file_output" in
                            *"shell script"*|*"bash script"*) echo "shell" ;;
                            *"Python script"*) echo "python" ;;
                            *"text"*) echo "script" ;;
                            *"executable"*|*"ELF"*) echo "exec" ;;
                            *) echo "exec" ;;
                        esac
                    else
                        local file_output=$(file -b "$file" 2>/dev/null)
                        case "$file_output" in
                            *"text"*) echo "text" ;;
                            *"data"*|*"binary"*) echo "data" ;;
                            *"image"*) echo "image" ;;
                            *"audio"*) echo "audio" ;;
                            *"video"*) echo "video" ;;
                            *"archive"*|*"compressed"*) echo "archive" ;;
                            *) echo "unknown" ;;
                        esac
                    fi
                ;;
            esac
        ;;
    esac
}

# Convert file size to easy-to-read format
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

# Print file contents with line numbers (highlight comments)
print_file_with_lines() {
    local file="$1"
    local line_num=1

    echo -e "${CYAN}📄 File contents view: ${WHITE}$file${RESET}"
    echo "================================================================================"

    if [[ ! -r "$file" ]]; then
        echo -e "${RED}❌ Cannot read file: $file${RESET}"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            # Comment lines are printed in green
            printf "${YELLOW}%02d${RESET} ${GREEN}%s${RESET}\n" "$line_num" "$line"
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            # Blank lines are printed without content
            printf "${YELLOW}%02d${RESET} \n" "$line_num"
        else
            # Regular lines are printed in default color
            printf "${YELLOW}%02d${RESET} %s\n" "$line_num" "$line"
        fi
        ((line_num++))
    done < "$file"
}

# Print file list
list_files() {
    local dir="${1:-.}"
    FILES=()
    FILETYPES=()

    echo -e "${BLUE}📁 Current directory: ${WHITE}$(realpath "$dir")${RESET}"
    echo "=============================================="

    # Header output
    printf "${WHITE}%-4s %-25s %-12s %-9s %-9s %-9s %-12s${RESET}\n" \
           "No" "Filename" "Modified" "Size" "Owner" "Group" "Permissions"
    echo "================================================================================"

    local count=1

    # If the current directory is not root, add the parent directory entry
    if [[ "$dir" != "/" ]]; then
        FILES+=("..")
        FILETYPES+=("parent")
        printf "${CYAN}%-4d${RESET} ${BLUE}%-25s${RESET} %-12s %-9s %-9s %-9s %-12s\n" \
               "$count" ".." "--------" "-----" "---" "---" "drwxr-xr-x"
        ((count++))
    fi

    # Process files and directories
    for file in "$dir"/*; do
        [[ ! -e "$file" ]] && continue

        local basename_file=$(basename "$file")
        FILES+=("$file")

        # Collect file information
        local mod_time=$(date -r "$file" +"%Y-%m-%d" 2>/dev/null || echo "unknown")
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        local size=$(format_size "$file_size")
        local owner=$(stat -f%Su "$file" 2>/dev/null || stat -c%U "$file" 2>/dev/null || echo "unknown")
        local group=$(stat -f%Sg "$file" 2>/dev/null || stat -c%G "$file" 2>/dev/null || echo "unknown")
        local perm=$(stat -f%Sp "$file" 2>/dev/null || stat -c%A "$file" 2>/dev/null || echo "unknown")
        local ftype=$(file_type_detailed "$file")

        FILETYPES+=("$ftype")

        # File type-specific colors and icons
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
    echo -e "${GREEN}✅ Completed${RESET}"
}

# File operations menu
file_menu() {
    local file="$1"
    local ftype="$2"

    echo ""
    echo "=============================================="
    echo -e "${YELLOW}📁 File operations menu: ${WHITE}$(basename "$file")${RESET}"
    echo "=============================================="
    echo "[1] Enter file contents"
    echo "[2] Edit file"
    echo "[3] Delete file"
    echo "[c] Cancel"
    echo "[0] Exit program"
    echo "=============================================="

    while true; do
        echo -ne "${CYAN}Select menu >>> ${RESET}"
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
                    echo -e "${GREEN}File has been checked. Press Enter to continue...${RESET}"
                    read -r
                    return 0
                else
                    echo -e "${RED}❌ Cannot read file: $file${RESET}"
                fi
                ;;
            2)
                if [[ -f "$file" && -w "$file" ]]; then
                    echo -e "${YELLOW}Editing file with vi...${RESET}"
                    vi "$file"
                    return 0
                else
                    echo -e "${RED}❌ Cannot edit file: $file${RESET}"
                fi
                ;;
            3)
                echo -ne "${RED}Are you sure you want to delete the file '$file'? (y/n) ${RESET}"
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if rm -rf "$file" 2>/dev/null; then
                        echo -e "${GREEN}✅ File has been deleted.${RESET}"
                    else
                        echo -e "${RED}❌ Failed to delete file: $file${RESET}"
                    fi
                    sleep 2
                    return 0
                else
                    echo -e "${YELLOW}Cancellation has been made.${RESET}"
                fi
                ;;
            c|C)
                echo -e "${YELLOW}Returning to file list.${RESET}"
                return 0
                ;;
            0)
                echo -e "${YELLOW}🔸 Exiting program.${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Invalid selection, please try again.${RESET}"
                ;;
        esac
    done
}

# Main loop
main() {
    while true; do
        clear
        list_files "$CURRENT_DIR"

        echo ""
        echo "[>>] Please enter the desired file number"
        echo "[c] Cancel (Current Screen Refresh)"
        echo "[0] Exit"
        echo "================================================================================"

        while true; do
            echo -ne "${CYAN}Enter Number >>> ${RESET}"
            read -r selection

            if [[ "$selection" == "0" ]]; then
                echo -e "${YELLOW}🔸 Shut down the program.${RESET}"
                echo -e "${RESET}"
                exit 0
            elif [[ "$selection" == "c" || "$selection" == "C" ]]; then
                echo -e "${YELLOW}Refresh the screen.${RESET}"
                break
            elif [[ "$selection" =~ ^[0-9]+$ ]] && (( selection > 0 && selection <= ${#FILES[@]} )); then
                local selected_file="${FILES[$((selection-1))]}"
                local selected_type="${FILETYPES[$((selection-1))]}"
                file_menu "$selected_file" "$selected_type"
                break
            else
                echo -e "${RED}❌ Invalid number, please re-enter. (Choose from 1-${#FILES[@]}, c, 0)${RESET}"
            fi
        done
    done
}

# Program start message
echo -e "${BLUE}================================================${RESET}"
echo -e "${WHITE}    🔍 File Viewer & Manager Open${RESET}"
echo -e "${BLUE}================================================${RESET}"

main