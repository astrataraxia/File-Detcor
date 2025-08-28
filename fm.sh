#!/bin/bash
# fm - a simple file viewer & manager with pagination
# Version 1.7 - Local config file (fm.rc)

# --- Configuration Loading ---
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/fm.rc"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=./fm.rc
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found!"
    echo "Please create fm.rc in the same directory as the script."
    exit 1
fi

# global variables
declare -a FILES # file list
declare -a FILETYPES # file type list  
CURRENT_DIR="$(pwd)"
CURRENT_PAGE=1
TOTAL_PAGES=1

# Fast file type detection (extension-based with fallback)
file_type_fast() {
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

    # Special files unless they are regular files
    if [[ ! -f "$file" ]]; then
        echo "special"
        return 0
    fi

    local basename_file=$(basename "$file")
    local extension="${file##*.}"
    local filename_lower="${basename_file,,}" # Convert to lowercase

    # Fast extension-based detection (covers 90% of files)
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

        # binary/executable file
        exe|bin|deb|rpm|dmg|msi) echo "binary" ;; 

        *)
            # Special filename patterns
            case "$filename_lower" in
                makefile|dockerfile|vagrantfile) echo "config" ;; 
                readme*|license*|changelog*|todo*) echo "text" ;; 
                *.bak|*.backup|*.tmp|*.temp) echo "backup" ;; 
                core|core.*) echo "coredump" ;; 
                *)
                    # Only use 'file' command for executables and unknown files (fallback)
                    if [[ -x "$file" ]]; then
                        local file_output=$(file -b "$file" 2>/dev/null)
                        case "$file_output" in
                            *"shell script"*|*"bash script"*) echo "shell" ;; 
                            *"Python script"*) echo "python" ;; 
                            *"text"*) echo "script" ;; 
                            *"executable"*|*"ELF"*) echo "exec" ;; 
                            *)
                                echo "exec"
                            ;; 
                        esac
                    else
                        echo "unknown"  # Skip file command for non-executables
                    fi
                ;; 
            esac
        ;;
esac
}

# Convert file size to easy-to-read format
format_size() {
    local bytes="$1"

    [[ "$bytes" =~ ^[0-9]+$ ]] || { echo "0B"; return; } 

    if command -v numfmt >/dev/null 2>&1;
    then
        numfmt --to=iec --suffix=B --padding=8 "$bytes" 2>/dev/null && return 
    fi

    local -r KB=1024
    local -r MB=$((KB * 1024))
    local -r GB=$((MB * 1024))

    if (( bytes >= GB )); then
        printf "%.1fGB" "$((bytes * 10 / GB))e-1"
    elif (( bytes >= MB )); then
        printf "%.1fMB" "$((bytes * 10 / MB))e-1"
    elif (( bytes >= KB )); then
        printf "%.1fKB" "$((bytes * 10 / KB))e-1"
    else
        printf "%dB" "$bytes"
    fi
}

# Print file contents with line numbers (highlight comments)
print_file_with_lines() {
    local file="$1"
    local line_num=1

    echo -e "${CYAN}📄 File contents view: ${WHITE}$file${RESET}"
    echo "================================================================================"

    if [[ ! -r "$file" ]]; then
        echo -e "${RED}⚠ Cannot read file: $file${RESET}"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            printf "${YELLOW}%02d${RESET} ${GREEN}%s${RESET}\n" "$line_num" "$line"
        elif [[ "$line" =~ ^[[:space:]]*$ ]]; then
            printf "${YELLOW}%02d${RESET} \n" "$line_num"
        else
            printf "${YELLOW}%02d${RESET} %s\n" "$line_num" "$line"
        fi
        ((line_num++))
    done < "$file"
}

# Calculate pages
calculate_pages() {
    local total_files=${#FILES[@]}
    TOTAL_PAGES=$(( (total_files + PAGE_SIZE - 1) / PAGE_SIZE ))

    (( TOTAL_PAGES == 0 )) && TOTAL_PAGES=1

    (( CURRENT_PAGE > TOTAL_PAGES )) && CURRENT_PAGE=$TOTAL_PAGES
    (( CURRENT_PAGE < 1 )) && CURRENT_PAGE=1
}

# Fast file listing - only collect filenames first
collect_files() {
    local dir="${1:-.}"
    FILES=()
    FILETYPES=()

    # Add parent directory entry if not root
    if [[ "$dir" != "/" ]]; then
        FILES+=("..")
        FILETYPES+=("parent")
    fi

    # Fast collection of filenames only
    local file
    for file in "$dir"/*;
    do
        [[ ! -e "$file" ]] && continue
        FILES+=("$file")
        # Only do basic type detection for display purposes
        if [[ -d "$file" ]]; then
            FILETYPES+=("dir")
        else
            FILETYPES+=("file")  # Defer detailed type detection
        fi
    done
}

# Get detailed file info (optimized with single stat call)
get_file_info() {
    local file="$1"
    local info_array_name="$2"
    
    if [[ ! -e "$file" ]]; then
        return 1
    fi
    
    # Single stat call to get all information at once
    local stat_format="%Y|%s|%U|%G|%A"
    local stat_info
    
    # Try different stat formats based on OS
    if stat_info=$(stat --format="$stat_format" "$file" 2>/dev/null);
    then
        # GNU stat (Linux)
        :
    elif stat_info=$(stat -f "%m|%z|%Su|%Sg|%Sp" "$file" 2>/dev/null);
    then
        # BSD stat (macOS)
        :
    else
        # Fallback
        stat_info="0|0|unknown|unknown|unknown"
    fi
    
    # Parse the stat info
    IFS='|' read -r mtime size owner group perm <<< "$stat_info"
    
    # Format modification time
    local mod_time
    if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime > 0 )); then
        mod_time=$(date -d "@$mtime" +"%Y-%m-%d" 2>/dev/null || date -r "$mtime" +"%Y-%m-%d" 2>/dev/null || echo "unknown")
    else
        mod_time="unknown"
    fi
    
    # Format size
    local formatted_size=$(format_size "$size")
    
    # Get detailed file type only when needed
    local ftype=$(file_type_fast "$file")
    
    # Return info via array reference
    declare -n info_ref=$info_array_name
    info_ref=("$ftype" "$mod_time" "$formatted_size" "$owner" "$group" "$perm")
}

# Print file list with lazy loading
list_files() {
    local dir="${1:-.}"
    
    echo -e "${BLUE}📁 Current directory: ${WHITE}$(realpath "$dir")${RESET}"
    echo "=============================================="

    # Fast collection of filenames
    collect_files "$dir"
    calculate_pages
    
    # Header output
    printf "${WHITE}%-4s %-25s %-12s %-9s %-9s %-9s %-12s${RESET}\n" \
           "No" "Filename" "Modified" "Size" "Owner" "Group" "Permissions"
    echo "================================================================================"

    # Only process files for current page
    local start_idx=$(( (CURRENT_PAGE - 1) * PAGE_SIZE ))
    local end_idx=$(( start_idx + PAGE_SIZE - 1 ))
    local display_count=$((start_idx + 1))

    for (( i=start_idx; i<=end_idx && i<${#FILES[@]}; i++ )); do
        local file="${FILES[i]}"
        local initial_ftype="${FILETYPES[i]}"
        
        if [[ "$initial_ftype" == "parent" ]]; then
            printf "${CYAN}%-4d${RESET} ${BLUE}%-25s${RESET} %-12s %-9s %-9s %-9s %-12s\n" \
                   "$display_count" ".." "--------" "-----" "---" "---" "drwxr-xr-x"
            FILETYPES[i]="parent"  # Update with correct type
        else
            # Get detailed info only for files being displayed
            local file_info
            if get_file_info "$file" file_info;
            then
                local ftype="${file_info[0]}"
                local mod_time="${file_info[1]}"
                local size="${file_info[2]}"
                local owner="${file_info[3]}"
                local group="${file_info[4]}"
                local perm="${file_info[5]}"
                
                # Update the FILETYPES array with correct type
                FILETYPES[i]="$ftype"
                
                local basename_file=$(basename "$file")
                
                # File type-specific colors
                local color=""
                case "$ftype" in
                    "dir") color="$BLUE" ;; 
                    "exec") color="$GREEN" ;; 
                    "script"|"shell") color="$GREEN" ;; 
                    "text") color="$WHITE" ;; 
                    "image") color="$MAGENTA" ;; 
                    "archive") color="$YELLOW" ;; 
                    "log") color="$CYAN" ;; 
                    *) color="$WHITE" ;; 
                esac

                printf "${CYAN}%-4d${RESET} ${color}%-25s${RESET} %-12s %-9s %-9s %-9s %-12s\n" \
                       "$display_count" "$basename_file" "$mod_time" "$size" "$owner" "$group" "$perm"
            else
                # Fallback if stat fails
                local basename_file=$(basename "$file")
                printf "${CYAN}%-4d${RESET} ${WHITE}%-25s${RESET} %-12s %-9s %-9s %-9s %-12s\n" \
                       "$display_count" "$basename_file" "unknown" "unknown" "unknown" "unknown" "unknown"
            fi
        fi

        ((display_count++))
    done

    echo "=============================================="
    echo -e "${GREEN}✅ Page ${CURRENT_PAGE}/${TOTAL_PAGES} | Total files: ${#FILES[@]} | Page size: ${PAGE_SIZE}${RESET}"
}

# File operations menu
file_menu() {
    local file="$1"
    local ftype="$2"

    echo ""
    echo "=============================================="
    echo -e "${YELLOW}🔧 File operations menu: ${WHITE}$(basename "$file")${RESET}"
    echo "=============================================="
    echo "[1] Enter file contents"
    echo "[2] Edit file"
    echo "[3] Delete file"
    echo "[c] Cancel"
    echo "[0] Exit program"
    echo "=============================================="

    while true;
    do
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
                    CURRENT_PAGE=1
                    return 0
                elif [[ "$ftype" == "parent" ]]; then
                    CURRENT_DIR=$(dirname "$CURRENT_DIR")
                    CURRENT_PAGE=1
                    return 0
                elif [[ -f "$file" ]]; then
                    print_file_with_lines "$file"
                    echo ""
                    echo -e "${GREEN}File has been checked. Press Enter to continue...${RESET}"
                    read -r
                    return 0
                else
                    echo -e "${RED}⚠ Cannot read file: $file${RESET}"
                fi
                ;;
            2)
                if [[ -f "$file" ]]; then
                    if [[ -w "$file" ]]; then
                        echo -e "${YELLOW}Editing file with ${EDITOR}...${RESET}"
                        "$EDITOR" "$file"
                        return 0
                    else
                        # File exists but no write permission
                        echo -e "${YELLOW}⚠ No write permission for: $(basename "$file")${RESET}"
                        echo -e "${CYAN}This file requires elevated privileges to edit.${RESET}"
                        echo ""
                        echo "[1] Edit with sudo ${EDITOR}"
                        echo "[2] Edit with sudoedit (recommended)"
                        echo "[c] Cancel"
                        echo ""
                        
                        while true;
                        do
                            echo -ne "${CYAN}Choose editing method >>> ${RESET}"
                            read -r edit_choice
                            
                            case "$edit_choice" in
                                1)
                                    echo -e "${YELLOW}Editing with sudo ${EDITOR}... (You may need to enter your password)${RESET}"
                                    sudo "$EDITOR" "$file"
                                    if [[ $? -eq 0 ]]; then
                                        echo -e "${GREEN}✅ File edited successfully with sudo ${EDITOR}${RESET}"
                                    else
                                        echo -e "${RED}⚠ Failed to edit file with sudo ${EDITOR}${RESET}"
                                    fi
                                    return 0
                                    ;; 
                                2)
                                    echo -e "${YELLOW}Editing with sudoedit... (You may need to enter your password)${RESET}"
                                    sudoedit "$file"
                                    if [[ $? -eq 0 ]]; then
                                        echo -e "${GREEN}✅ File edited successfully with sudoedit${RESET}"
                                    else
                                        echo -e "${RED}⚠ Failed to edit file with sudoedit${RESET}"
                                    fi
                                    return 0
                                    ;; 
                                c|C)
                                    echo -e "${YELLOW}Edit cancelled${RESET}"
                                    break
                                    ;; 
                                *)
                                    echo -e "${RED}⚠ Invalid choice. Please enter 1, 2, or c${RESET}"
                                    ;; 
                            esac
                        done
                    fi
                else
                    echo -e "${RED}⚠ File does not exist or is not a regular file: $file${RESET}"
                fi
                ;; 
            3)
                echo -ne "${RED}Are you sure you want to delete the file '$file'? (y/n) ${RESET}"
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    if rm -rf "$file" 2>/dev/null;
                    then
                        echo -e "${GREEN}✅ File has been deleted.${RESET}"
                    else
                        echo -e "${RED}⚠ Failed to delete file: $file${RESET}"
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
                echo -e "${YELLOW}📸 Exiting program.${RESET}"
                exit 0
                ;; 
            *)
                echo -e "${RED}⚠ Invalid selection, please try again.${RESET}"
                ;; 
        esac
    done
}

# Main loop
main() {
    while true;
    do
        clear
        list_files "$CURRENT_DIR"

        echo ""
        echo "[>>] Please enter the desired file number"
        echo "[p] Previous page  [n] Next page  [s] Set page size"
        echo "[c] Cancel (Current Screen Refresh)"
        echo "[0] Exit"
        echo "================================================================================"

        while true;
        do
            echo -ne "${CYAN}Enter Number >>> ${RESET}"
            read -r selection

            # Calculate the range of valid file numbers for the current page
            local start_num=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))
            local end_num=$(( start_num + PAGE_SIZE - 1 ))
            if (( end_num > ${#FILES[@]} )); then
                end_num=${#FILES[@]}
            fi

            case "$selection" in
                0)
                    echo -e "${YELLOW}📸 Shut down the program.${RESET}"
                    echo -e "${RESET}"
                    exit 0
                    ;; 
                c|C)
                    echo -e "${YELLOW}Refresh the screen.${RESET}"
                    break
                    ;; 
                n|N)
                    if (( CURRENT_PAGE < TOTAL_PAGES )); then
                        ((CURRENT_PAGE++))
                        echo -e "${GREEN}Moving to page ${CURRENT_PAGE}${RESET}"
                    else
                        echo -e "${YELLOW}Already on last page${RESET}"
                    fi
                    break
                    ;; 
                p|P)
                    if (( CURRENT_PAGE > 1 )); then
                        ((CURRENT_PAGE--))
                        echo -e "${GREEN}Moving to page ${CURRENT_PAGE}${RESET}"
                    else
                        echo -e "${YELLOW}Already on first page${RESET}"
                    fi
                    break
                    ;; 
                s|S)
                    echo -ne "${CYAN}Enter new page size (current: ${PAGE_SIZE}) >>> ${RESET}"
                    read -r new_size
                    if [[ "$new_size" =~ ^[0-9]+$ ]] && (( new_size > 0 && new_size <= 100 )); then
                        PAGE_SIZE=$new_size
                        CURRENT_PAGE=1
                        echo -e "${GREEN}Page size changed to ${PAGE_SIZE}${RESET}"
                    else
                        echo -e "${RED}⚠ Invalid page size. Please enter a number between 1-100.${RESET}"
                    fi
                    break
                    ;; 
                *)
                    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= start_num && selection <= end_num )); then
                        local selected_file="${FILES[$((selection-1))]}"
                        local selected_type="${FILETYPES[$((selection-1))]}"
                        file_menu "$selected_file" "$selected_type"
                        break
                    else
                        echo -e "${RED}⚠ Invalid input. Enter file number (${start_num}-${end_num}), n/p for page navigation, s for page size, c to refresh, or 0 to exit.${RESET}"
                    fi
                    ;; 
            esac
        done
    done
}

# Program start message
echo -e "${BLUE}================================================${RESET}"
echo -e "${WHITE}    📁 File Viewer & Manager Open (v1.7)${RESET}"
echo -e "${BLUE}================================================${RESET}"

main
