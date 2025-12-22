#!/usr/bin/env zsh

# Provide no-op fallbacks for task helper functions if not defined
if ! typeset -f __task >/dev/null 2>&1; then
    __task() { echo "-- $*"; }
fi
if ! typeset -f _cmd >/dev/null 2>&1; then
    _cmd() { eval "$*"; }
fi
if ! typeset -f _task_done >/dev/null 2>&1; then
    _task_done() { :; }
fi

_cbr2cbz_usage() {
    cat <<'EOF'
Usage: cbr2cbz [options] [PATH]

Convert .cbr files to .cbz. PATH may be a file or directory.
If PATH is omitted, the current directory is used.

Options:
    -f, --force           Overwrite existing .cbz if present
    -k, --keep            Keep original .cbr after successful conversion
            --no-optimize     Skip image optimization (faster, larger files)
            --jpg-quality N   JPEG quality (default: 85) when optimizing
            --analyze         Analyze potential savings only; do not modify/create files
            --analyze-th N    Report only if potential saving >= N%% (default: 2)
    -h, --help            Show this help

Notes:
    - Extraction tries unrar, then unar, then 7z.
    - Image optimization uses oxipng (PNG) and mogrify (JPEG) if available.
EOF
}

_extract_cbr() {
    local src="$1" dest="$2"
    if command -v unrar >/dev/null 2>&1; then
        if unrar x -inul -- "$src" "$dest"; then
            return 0
        fi
    fi
    if command -v unar >/dev/null 2>&1; then
        if unar -quiet -o "$dest" -- "$src"; then
            return 0
        fi
    fi
    if command -v 7z >/dev/null 2>&1; then
        if 7z x -y -o"$dest" -- "$src" >/dev/null; then
            return 0
        fi
    fi
    return 1
}

_optimize_images() {
    local root="$1" jpg_q="$2"; shift 2
    local have_oxipng=0 have_mogrify=0
    command -v oxipng >/dev/null 2>&1 && have_oxipng=1
    command -v mogrify >/dev/null 2>&1 && have_mogrify=1

    if (( have_oxipng )); then
        _cmd "find \"$root\" -type f -iname '*.png' -print0 | xargs -0 -r oxipng -o 4 -strip all"
    else
        echo "warn: oxipng not found; skipping PNG optimization" >&2
    fi

    if (( have_mogrify )); then
        _cmd "find \"$root\" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | xargs -0 -r mogrify -quality $jpg_q -strip"
    else
        echo "warn: mogrify not found; skipping JPEG optimization" >&2
    fi
}

cbr2cbz() {
    # Ensure this function doesn't abort due to external tool failures
    setopt local_options no_nomatch no_err_exit

    local force=0 keep=0 do_optimize=1 jpg_quality=85 analyze=0 analyze_th=2
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=1; shift ;;
            -k|--keep) keep=1; shift ;;
            --no-optimize) do_optimize=0; shift ;;
            --analyze) analyze=1; shift ;;
            --analyze-th) shift; [[ -n "$1" ]] || { echo "--analyze-th requires a value" >&2; return 2; }; analyze_th="$1"; shift ;;
            --jpg-quality)
                shift; [[ -n "$1" ]] || { echo "--jpg-quality requires a value" >&2; return 2; }
                jpg_quality="$1"; shift ;;
            --jpg-quality=*) jpg_quality="${1#*=}"; shift ;;
            -h|--help) _cbr2cbz_usage; return 0 ;;
            --) shift; while [[ $# -gt 0 ]]; do args+=("$1"); shift; done ;;
            *) args+=("$1"); shift ;;
        esac
    done

    # Default path is current directory
    if (( ${#args} == 0 )); then
        args=(".")
    fi

    # Process each argument
    local input
    for input in "$args[@]"; do
        # Tilde expand if provided as string
        if [[ "$input" = ~* ]]; then
            input="${input/#\~/$HOME}"
        fi

        if [[ ! -e "$input" ]]; then
            echo "Error: File or directory not found: $input" >&2
            continue
        fi

        if [[ -d "$input" ]]; then
            __task "Scan directory for .cbr: $input"
            local file _opts
            while IFS= read -r -d '' file; do
                _opts=()
                (( force )) && _opts+=(--force)
                (( keep )) && _opts+=(--keep)
                (( do_optimize )) || _opts+=(--no-optimize)
                (( analyze )) && _opts+=(--analyze)
                _opts+=(--analyze-th "$analyze_th" --jpg-quality "$jpg_quality")
                cbr2cbz "${_opts[@]}" "$file"
            done < <(find "$input" -type f -iname '*.cbr' -print0)
            _task_done
            continue
        fi

        # Single file
        local CBR_FILE="$input"
        local BASENAME
        BASENAME="$(basename "${CBR_FILE%.*}")"
        local DIRNAME
        DIRNAME="$(dirname "$CBR_FILE")"
        local TMP_DIR
        TMP_DIR="$(mktemp -d)"
        local CBZ_FILE="$DIRNAME/$BASENAME.cbz"

        # Ensure cleanup on exit/error
        local cleanup
        cleanup() { [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
        trap cleanup EXIT INT TERM

        if [[ -e "$CBZ_FILE" && $force -ne 1 ]]; then
            echo "Skip (exists): $CBZ_FILE (use -f to overwrite)" >&2
            cleanup; trap - EXIT INT TERM
            continue
        fi

        __task "Unpack \"$CBR_FILE\""
        if ! _extract_cbr "$CBR_FILE" "$TMP_DIR"; then
            echo "Error: failed to extract '$CBR_FILE' (need unrar/unar/7z)" >&2
            cleanup; trap - EXIT INT TERM
            continue
        fi
        _task_done

        if (( analyze )); then
            __task "Analyze potential savings in extracted content"
            local orig_total=0 opt_total=0 count_png=0 count_jpg=0 save_png=0 save_jpg=0
            local f ext src_size new_size pct tmp_anadir
            tmp_anadir="$(mktemp -d)"
            # Walk images
            while IFS= read -r -d '' f; do
                ext="${f##*.}"; ext="${ext:l}"
                src_size=$(wc -c < "$f" | tr -d ' ')
                (( orig_total += src_size ))
                mkdir -p "$tmp_anadir"
                local tmpf="$tmp_anadir/$(basename "$f")"
                cp -f -- "$f" "$tmpf" 2>/dev/null || { continue; }
                case "$ext" in
                    png)
                        (( count_png++ ))
                        if command -v oxipng >/dev/null 2>&1; then
                            oxipng -o 4 -strip all -q "$tmpf" >/dev/null 2>&1 || true
                            new_size=$(wc -c < "$tmpf" | tr -d ' ')
                            (( opt_total += new_size ))
                            if (( src_size > 0 )); then
                                pct=$(( (100*(src_size-new_size))/src_size ))
                                (( pct >= analyze_th )) && (( save_png++ ))
                            fi
                        fi
                        ;;
                    jpg|jpeg)
                        (( count_jpg++ ))
                        if command -v jpegoptim >/dev/null 2>&1; then
                            jpegoptim --max=$jpg_quality --strip-all --all-progressive --quiet "$tmpf" >/dev/null 2>&1 || true
                            new_size=$(wc -c < "$tmpf" | tr -d ' ')
                            (( opt_total += new_size ))
                            if (( src_size > 0 )); then
                                pct=$(( (100*(src_size-new_size))/src_size ))
                                (( pct >= analyze_th )) && (( save_jpg++ ))
                            fi
                        elif command -v jpegtran >/dev/null 2>&1; then
                            # lossless try
                            local tmpf2="$tmpf.out"
                            jpegtran -copy none -optimize -progressive "$f" > "$tmpf2" 2>/dev/null || cp -f "$f" "$tmpf2"
                            new_size=$(wc -c < "$tmpf2" | tr -d ' ')
                            mv -f "$tmpf2" "$tmpf" 2>/dev/null || true
                            (( opt_total += new_size ))
                            if (( src_size > 0 )); then
                                pct=$(( (100*(src_size-new_size))/src_size ))
                                (( pct >= analyze_th )) && (( save_jpg++ ))
                            fi
                        fi
                        ;;
                esac
            done < <(find "$TMP_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0)
            rm -rf "$tmp_anadir" 2>/dev/null || true
            _task_done
            # Summary
            local saved=$(( orig_total - opt_total ))
            if (( orig_total > 0 )); then
                local pct_total=$(( (100*saved)/orig_total ))
                echo "ANALYZE: images=$((count_png+count_jpg)) png=$count_png(jobs>=$analyze_th%:$save_png) jpg=$count_jpg(jobs>=$analyze_th%:$save_jpg) potential_saved=${saved}B (~${pct_total}%)"
            else
                echo "ANALYZE: no images found"
            fi
            __task "Cleanup"
            cleanup; trap - EXIT INT TERM
            _task_done
            continue
        fi

        if (( do_optimize )); then
            __task "Optimize images (PNG/JPEG)"
            _optimize_images "$TMP_DIR" "$jpg_quality"
            _task_done
        fi

        __task "Create .cbz archive"
        local OUT_TMP="$CBZ_FILE.$$"
        _cmd "(cd \"$TMP_DIR\" && zip -r -q -X \"$OUT_TMP\" .)" || { echo "Error: zip failed" >&2; cleanup; trap - EXIT INT TERM; continue; }
        _task_done

        if command -v advzip >/dev/null 2>&1; then
            __task "Compress .cbz with advzip"
            _cmd "advzip -z -4 \"$OUT_TMP\""
            _task_done
        fi

        __task "Finalize"
        _cmd "mv -f \"$OUT_TMP\" \"$CBZ_FILE\""
        if [[ $keep -ne 1 ]]; then
            _cmd "rm -f -- \"$CBR_FILE\""
        fi
        _task_done

        __task "Cleanup"
        cleanup; trap - EXIT INT TERM
        _task_done

        echo "Done: \"$CBZ_FILE\""
    done
}
