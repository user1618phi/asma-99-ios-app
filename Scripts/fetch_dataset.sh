#!/usr/bin/env bash
# Fetches all 99 Asma'ul Husna names in 3 languages + 99 mp3 audio files
# from islamicapi.com and merges them into Asma/Resources/Data/names.json
# plus Asma/Resources/Audio/<slug>.mp3.
#
# Idempotent — re-running just refreshes files. Audio files are skipped if already present.
#
# Requirements: bash 4+, curl, jq, python3 (all available on macOS).
# Reads ISLAMICAPI_KEY and ISLAMICAPI_BASE from .env in repo root.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

# --- env ---
if [[ ! -f .env ]]; then
    echo "ERROR: .env not found. Copy .env.example to .env and set ISLAMICAPI_KEY." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${ISLAMICAPI_KEY:?ISLAMICAPI_KEY must be set in .env}"
: "${ISLAMICAPI_BASE:=https://islamicapi.com}"

# --- paths ---
DATA_DIR="Asma/Resources/Data"
AUDIO_DIR="Asma/Resources/Audio"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$DATA_DIR" "$AUDIO_DIR"

LANGUAGES=(en ru kk)

# --- fetch JSON per language ---
echo "==> Fetching translations (3 languages)"
for lang in "${LANGUAGES[@]}"; do
    out="$TMP_DIR/$lang.json"
    url="$ISLAMICAPI_BASE/api/v1/asma-ul-husna/?language=$lang&api_key=$ISLAMICAPI_KEY"
    echo "  - $lang"
    http_code=$(curl -sS -w "%{http_code}" -o "$out" "$url")
    if [[ "$http_code" != "200" ]]; then
        echo "ERROR: $lang request returned HTTP $http_code" >&2
        cat "$out" >&2
        exit 1
    fi
    # quick sanity: must be JSON with status=success
    if ! jq -e '.status == "success" and (.data.names | length == 99)' "$out" >/dev/null; then
        echo "ERROR: $lang response is not a valid 99-entry success payload" >&2
        jq '.' "$out" | head -40 >&2 || true
        exit 1
    fi
done

# --- merge into single names.json keyed by number ---
echo "==> Merging into $DATA_DIR/names.json"
python3 <<PYEOF
import json, pathlib, re, sys

tmp = pathlib.Path("$TMP_DIR")
langs = ["en", "ru", "kk"]
per_lang = {l: json.loads((tmp / f"{l}.json").read_text(encoding="utf-8"))["data"]["names"] for l in langs}

# index by number
by_num = {l: {n["number"]: n for n in per_lang[l]} for l in langs}

# Use English as canonical source for arabic/transliteration/audio,
# since those fields are language-independent.
base = by_num["en"]

merged = []
mismatches = []
for num in range(1, 100):
    if num not in base:
        sys.exit(f"Missing number {num} in EN payload")
    en_entry = base[num]

    arabic = en_entry["name"]
    translit = en_entry["transliteration"]
    audio_path = en_entry["audio"]  # e.g. "/audio/asma-ul-husna/rahman.mp3"
    audio_filename = pathlib.PurePosixPath(audio_path).name

    # cross-check that ru/kk have same arabic + audio (canonical fields)
    for lang in ("ru", "kk"):
        other = by_num[lang].get(num)
        if other is None:
            mismatches.append(f"number {num} missing in {lang}")
            continue
        if other["name"] != arabic:
            mismatches.append(f"number {num}: arabic differs in {lang}")
        if pathlib.PurePosixPath(other["audio"]).name != audio_filename:
            mismatches.append(f"number {num}: audio filename differs in {lang}")

    translations = {}
    for lang in langs:
        ent = by_num[lang].get(num)
        if ent is None:
            sys.exit(f"number {num} missing in {lang}")
        translations[lang] = {
            "translation": ent["translation"].strip(),
            "meaning": ent["meaning"].strip(),
        }

    merged.append({
        "number": num,
        "arabic": arabic,
        "transliteration": translit,
        "audio": audio_filename,
        "audioRemotePath": audio_path,
        "translations": translations,
    })

if mismatches:
    print("WARNING: cross-language mismatches detected:")
    for m in mismatches:
        print(f"  - {m}")

out_path = pathlib.Path("$DATA_DIR/names.json")
out_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {out_path} ({len(merged)} entries)")
PYEOF

# --- download audio ---
echo "==> Downloading audio files (skip existing)"
downloaded=0
skipped=0
while IFS=$'\t' read -r remote local; do
    target="$AUDIO_DIR/$local"
    if [[ -s "$target" ]]; then
        skipped=$((skipped + 1))
        continue
    fi
    url="$ISLAMICAPI_BASE$remote"
    http_code=$(curl -sS -L -w "%{http_code}" -o "$target" "$url")
    if [[ "$http_code" != "200" ]]; then
        echo "WARNING: $remote returned HTTP $http_code"
        rm -f "$target"
        continue
    fi
    # tiny sanity: mp3 should be > 1 KB
    size=$(stat -f%z "$target" 2>/dev/null || stat -c%s "$target")
    if [[ "$size" -lt 1024 ]]; then
        echo "WARNING: $target only $size bytes — suspicious"
    fi
    downloaded=$((downloaded + 1))
done < <(jq -r '.[] | "\(.audioRemotePath)\t\(.audio)"' "$DATA_DIR/names.json")

echo "Audio: downloaded=$downloaded skipped=$skipped"

# --- post-checks ---
echo "==> Final verification"
missing=()
while IFS= read -r filename; do
    if [[ ! -s "$AUDIO_DIR/$filename" ]]; then
        missing+=("$filename")
    fi
done < <(jq -r '.[].audio' "$DATA_DIR/names.json")

if (( ${#missing[@]} > 0 )); then
    echo "ERROR: ${#missing[@]} audio files missing or empty:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi

total_audio=$(find "$AUDIO_DIR" -name '*.mp3' | wc -l | tr -d ' ')
echo "OK: 99 names merged, $total_audio audio files present."
