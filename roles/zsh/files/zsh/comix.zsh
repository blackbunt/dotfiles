#!/usr/bin/env zsh

cbr2cbz() {
    set -e

    if [[ -z "$1" ]]; then
        echo "Usage: $0 <comic.cbr>"
        return 1
    fi

    CBR_FILE="$1"
    NAME="${CBR_FILE%.*}"
    BASENAME="$(basename "$NAME")"
    TMP_DIR="$(mktemp -d)"
    CBZ_FILE="$(realpath "$BASENAME.cbz")"

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