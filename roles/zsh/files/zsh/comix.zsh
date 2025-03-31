#!/usr/bin/env zsh

cbr2cbz() {
    local input="$1"

    # recursive function call if not a specific file
    if [[ -d "$input" ]]; then
        find "$input" -type f \( -iname '*.cbr' \) | while read -r cbr; do
            cbr2cbz "$cbr"
        done
        return
    fi

    # conversion
    local CBR_FILE="$input"
    local BASENAME="$(basename "${CBR_FILE%.*}")"
    local DIRNAME="$(dirname "$CBR_FILE")"
    local TMP_DIR="$(mktemp -d)"
    local CBZ_FILE="$DIRNAME/$BASENAME.cbz"

    __task "Unpack \"$CBR_FILE\""
    _cmd "unrar x -inul \"$CBR_FILE\" \"$TMP_DIR\""
    _task_done

    __task "Optimize images"
    _cmd "find \"$TMP_DIR\" -iname '*.png' -exec oxipng -o 4 -strip all {} \;"
    _cmd "find \"$TMP_DIR\" -iname '*.jpg' -exec mogrify -quality 85 -strip {} \;"
    _task_done

    __task "Creating .cbz"
    _cmd "(cd \"$TMP_DIR\" && zip -r -q \"$CBZ_FILE\" .)"
    _task_done

    __task "Compress .cbz file with advzip"
    _cmd "advzip -z -4 \"$CBZ_FILE\""
    _task_done

    __task "Cleanup"
    _cmd "rm -r \"$TMP_DIR\""
    _task_done

    echo "Done: \"$CBZ_FILE\""
}
