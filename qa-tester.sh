#!/bin/sh
#
# qa-tester.sh – FreeBSD Kernel QA Testing Environment
#
# After collecting the QA ticket ID and build settings, a persistent menu
# lets the tester choose any action in any order:
#
#   1) Sync source to QA branch  (clone or fetch+reset, auto-detected)
#   2) Build world + kernel + install
#   3) Verify the running kernel matches the QA branch
#   4) Run the specific QA tests   (qa-branches/<ID>/<ID>.sh)
#   q) Quit
#
# After every test run the last output lines show PASS/FAIL and the
# path to the report file.
#
# Usage:
#   ./qa-tester.sh [session-name]
#
# Test scripts:  qa-branches/<QA_ID>/<QA_ID>.sh
# Session log:   reports/<session>/session.log
# Report file:   reports/<session>/qa-report-<timestamp>.txt
#

set -u

# ── Argument pre-processing ────────────────────────────────────────────────────
# Parse --email / --no-email before the path setup so SESSION_NAME is correct.
# Usage: ./qa-tester.sh [--email ADDR[,ADDR…]] [session-name]
#
# Variables set here are finalised; the bottom of the file does NOT reset them.
REPORT_EMAIL="${REPORT_EMAIL:-freebsd-test@mailman-svr.amd.com,ojanerif@amd.com}"
SENDER_EMAIL="${SENDER_EMAIL:-freebsd-ci-actions@amd.com}"
EMAIL_REQUESTED=0

_qa_posargs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --email)
            shift
            if [ $# -eq 0 ]; then
                printf 'Error: --email requires an address.\n' >&2; exit 1
            fi
            REPORT_EMAIL="$1"
            EMAIL_REQUESTED=1
            ;;
        --no-email)
            EMAIL_REQUESTED=0
            ;;
        --) shift; _qa_posargs="${_qa_posargs:+$_qa_posargs }$*"; break ;;
        -*) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
        *)  _qa_posargs="${_qa_posargs:+$_qa_posargs }$1" ;;
    esac
    shift
done
# shellcheck disable=SC2086
set -- ${_qa_posargs}

# ── Paths ──────────────────────────────────────────────────────────────────────

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_NAME="${1:-session_${TIMESTAMP}}"
REPORT_DIR="${SCRIPT_DIR}/reports/${SESSION_NAME}"
LOG_FILE="${REPORT_DIR}/session.log"
REPORT_FILE="${REPORT_DIR}/qa-report-${TIMESTAMP}.txt"
RESULTS_FILE="${REPORT_DIR}/results.tsv"
STATE_FILE="${REPORT_DIR}/state.env"
LAST_SESSION_FILE="${SCRIPT_DIR}/last-session.env"

mkdir -p "${REPORT_DIR}"
: > "${RESULTS_FILE}"
: > "${LOG_FILE}"

# ── Default values ─────────────────────────────────────────────────────────────

QA_ID=""
QA_FILE=""
JIRA_URL=""
UPSTREAM_PR=""
KERNEL_REPO="https://github.com/AMDESE/freebsd-src"
KERNEL_REPO_ALT="ssh://git@sos-git.amd.com/freebsd-src.git"
QA_BRANCH=""
EXPECTED_SHA=""
SRC_DIR="${SCRIPT_DIR}/dev"
OBJ_DIR="/usr/obj"
MAKE_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || printf '4')"
KERNCONF="GENERIC"
ACTUAL_SHA=""
RESUME_MODE="new"

# ── Colour support ─────────────────────────────────────────────────────────────

if [ -t 1 ]; then
    RED=$(printf '\033[0;31m');  GRN=$(printf '\033[0;32m')
    YLW=$(printf '\033[1;33m');  BLU=$(printf '\033[0;34m')
    CYN=$(printf '\033[0;36m');  BLD=$(printf '\033[1m')
    RST=$(printf '\033[0m')
else
    RED=''; GRN=''; YLW=''; BLU=''; CYN=''; BLD=''; RST=''
fi

# ── Logging helpers ────────────────────────────────────────────────────────────

ts()   { date '+%H:%M:%S'; }
info() { printf '%s %b[INFO]%b %s\n' "$(ts)" "$CYN" "$RST" "$*"   | tee -a "${LOG_FILE}"; }
pass() { printf '%s %b[PASS]%b %s\n' "$(ts)" "$GRN" "$RST" "$*"   | tee -a "${LOG_FILE}"; }
fail() { printf '%s %b[FAIL]%b %s\n' "$(ts)" "$RED" "$RST" "$*"   | tee -a "${LOG_FILE}"; }
warn() { printf '%s %b[WARN]%b %s\n' "$(ts)" "$YLW" "$RST" "$*"   | tee -a "${LOG_FILE}"; }

section() {
    local _bar="────────────────────────────────────────────────────────────"
    printf '\n%b%s%b\n%b  %s%b\n%b%s%b\n\n' \
        "$BLD$BLU" "$_bar" "$RST" \
        "$BLD"     "$1"    "$RST" \
        "$BLD$BLU" "$_bar" "$RST"
    printf '\n=== %s ===\n\n' "$1" >> "${LOG_FILE}"
}

# ── Interactive helpers ────────────────────────────────────────────────────────

hint() { printf '  %b%s%b\n' "$CYN" "$*" "$RST"; }

# ask <prompt> <default> <varname>
ask() {
    local _p="$1" _d="$2" _v="$3" _val
    if [ -n "$_d" ]; then
        printf '%b%s%b [%b%s%b]: ' "$BLD" "$_p" "$RST" "$YLW" "$_d" "$RST"
    else
        printf '%b%s%b: ' "$BLD" "$_p" "$RST"
    fi
    read -r _val
    [ -z "$_val" ] && _val="$_d"
    eval "${_v}=\"\${_val}\""
}

# ask_yn <prompt> <default y|n>  →  0=yes  1=no
ask_yn() {
    local _p="$1" _d="${2:-y}" _val
    if [ "$_d" = "y" ]; then
        printf '%b%s%b [%bY/n%b]: ' "$BLD" "$_p" "$RST" "$GRN" "$RST"
    else
        printf '%b%s%b [%by/N%b]: ' "$BLD" "$_p" "$RST" "$GRN" "$RST"
    fi
    read -r _val
    _val="${_val:-$_d}"
    case "$_val" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ── Result tracking ────────────────────────────────────────────────────────────

# record <STATUS> <name> <note>
record() {
    local _status="$1" _name="$2" _note="$3"
    printf '%s\t%s\t%s\n' "$_status" "$_name" "$_note" >> "${RESULTS_FILE}"
    case "$_status" in
        PASS) pass "${_name}: ${_note}" ;;
        FAIL) fail "${_name}: ${_note}" ;;
        WARN) warn "${_name}: ${_note}" ;;
        SKIP) info "SKIP ${_name}: ${_note}" ;;
    esac
}

# ── Command runners ────────────────────────────────────────────────────────────

# run_cmd <label> <cmd…>  — runs a short command, logs it, reports PASS/FAIL
run_cmd() {
    local _label="$1"; shift
    local _rc_tmp
    _rc_tmp=$(mktemp /tmp/qa-rc.XXXXXX)
    info "CMD: $*"
    printf '\n>>> %s\n' "$*" >> "${LOG_FILE}"
    { "$@"; printf '%s' "$?" > "${_rc_tmp}"; } 2>&1 | tee -a "${LOG_FILE}"
    local _rc
    _rc=$(cat "${_rc_tmp}" 2>/dev/null || printf '1')
    rm -f "${_rc_tmp}"
    if [ "${_rc}" -eq 0 ]; then
        pass "${_label}"
    else
        fail "${_label} (exit=${_rc})"
    fi
    return "${_rc}"
}

# run_long_cmd <label> <cmd…>  — like run_cmd but shows a live spinner
run_long_cmd() {
    local _label="$1"; shift
    local _out_tmp _pid _start _rc _elapsed _m _s _i _sp _last _cols _label_w _log_w

    _out_tmp=$(mktemp /tmp/qa-out.XXXXXX)
    info "CMD: $*"
    printf '\n>>> %s\n' "$*" >> "${LOG_FILE}"

    "$@" > "${_out_tmp}" 2>&1 &
    _pid=$!
    _start=$(date +%s)
    _i=0

    if [ -t 1 ]; then
        _cols=$(tput cols 2>/dev/null || printf '100')
        _label_w=28
        _log_w=$(( _cols - _label_w - 12 ))
        [ "${_log_w}" -lt 10 ] && _log_w=10
        printf '\n'
        while kill -0 "${_pid}" 2>/dev/null; do
            _elapsed=$(( $(date +%s) - _start ))
            _m=$(( _elapsed / 60 ))
            _s=$(( _elapsed % 60 ))
            case $(( _i % 4 )) in
                0) _sp='|' ;; 1) _sp='/' ;; 2) _sp='-' ;; 3) _sp='\\' ;;
            esac
            _last=$(tail -5 "${_out_tmp}" 2>/dev/null \
                | grep -v '^[[:space:]]*$' | tail -1 \
                | tr -d '\r' | cut -c"1-${_log_w}")
            printf '\r\033[K  %b%s%b %02d:%02d  %-*s %b│%b %s' \
                "$CYN" "$_sp" "$RST" "$_m" "$_s" \
                "$_label_w" "$_label" "$BLU" "$RST" "$_last"
            _i=$(( _i + 1 ))
            sleep 1
        done
        printf '\r\033[K\n'
    fi

    wait "${_pid}"
    _rc=$?
    cat "${_out_tmp}" >> "${LOG_FILE}"

    if [ "${_rc}" -eq 0 ]; then
        pass "${_label}"
    else
        fail "${_label} (exit=${_rc})"
        printf '%bLast output (tail -20):%b\n' "$BLD" "$RST"
        tail -20 "${_out_tmp}"
        printf '\n'
    fi

    rm -f "${_out_tmp}"
    return "${_rc}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  State helpers
# ══════════════════════════════════════════════════════════════════════════════

# Locate and parse the QA test file; returns 1 if not found.
_load_qa_testfile() {
    QA_FILE="${SCRIPT_DIR}/qa-branches/${QA_ID}/${QA_ID}.sh"

    if [ ! -f "${QA_FILE}" ]; then
        fail "No test file found for QA ID '${QA_ID}'."
        printf '\n%bExpected path:%b\n  %b%s%b\n\n' \
            "$BLD" "$RST" "$YLW" "${QA_FILE}" "$RST"
        return 1
    fi

    info "Test file found: ${QA_FILE}"

    QA_BRANCH=$(grep '^# Branch:' "${QA_FILE}" | head -1 \
        | sed 's/^# Branch:[[:space:]]*//')
    EXPECTED_SHA=$(grep '^# SHA:' "${QA_FILE}" | head -1 \
        | sed 's/^# SHA:[[:space:]]*//')
    UPSTREAM_PR=$(grep '^# Upstream PR:' "${QA_FILE}" | head -1 \
        | sed 's/^# Upstream PR:[[:space:]]*//')

    if [ -z "${QA_BRANCH}" ]; then
        QA_BRANCH=$(grep '^EXPECTED_BRANCH=' "${QA_FILE}" | head -1 \
            | sed "s/^EXPECTED_BRANCH=//;s/^['\"]//;s/['\"]$//")
    fi
    if [ -z "${EXPECTED_SHA}" ]; then
        EXPECTED_SHA=$(grep '^EXPECTED_SHA=' "${QA_FILE}" | head -1 \
            | sed "s/^EXPECTED_SHA=//;s/^['\"]//;s/['\"]$//")
    fi

    JIRA_URL="https://amd.atlassian.net/browse/${QA_ID}"
    info "QA branch   : ${QA_BRANCH:-<not found in file>}"
    info "Expected SHA: ${EXPECTED_SHA:-<not found in file>}"
    [ -n "${UPSTREAM_PR:-}" ] && info "Upstream PR : ${UPSTREAM_PR}"
    return 0
}

_save_session_state() {
    local _c
    _c=$(printf \
        "QA_ID='%s'\nQA_FILE='%s'\nJIRA_URL='%s'\nUPSTREAM_PR='%s'\n\
KERNEL_REPO='%s'\nKERNEL_REPO_ALT='%s'\nQA_BRANCH='%s'\nEXPECTED_SHA='%s'\n\
SRC_DIR='%s'\nOBJ_DIR='%s'\nMAKE_JOBS='%s'\nKERNCONF='%s'\n\
REPORT_EMAIL='%s'\nSENDER_EMAIL='%s'\nEMAIL_REQUESTED='%s'\n" \
        "${QA_ID}" "${QA_FILE}" \
        "${JIRA_URL}" "${UPSTREAM_PR:-}" \
        "${KERNEL_REPO}" "${KERNEL_REPO_ALT}" \
        "${QA_BRANCH}" "${EXPECTED_SHA}" \
        "${SRC_DIR}" "${OBJ_DIR}" "${MAKE_JOBS}" "${KERNCONF}" \
        "${REPORT_EMAIL}" "${SENDER_EMAIL}" "${EMAIL_REQUESTED}")
    printf '%s\n' "${_c}" > "${STATE_FILE}"
    printf '%s\n' "${_c}" > "${LAST_SESSION_FILE}"
    info "Session state saved → ${STATE_FILE}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Previous session detection
# ══════════════════════════════════════════════════════════════════════════════

load_previous_session() {
    [ ! -f "${LAST_SESSION_FILE}" ] && return

    # shellcheck disable=SC1090
    . "${LAST_SESSION_FILE}"

    section "Previous Session Detected"
    printf 'A saved QA session was found:\n\n'
    printf '  %-22s %s\n' "QA ID:"        "${QA_ID:-—}"
    printf '  %-22s %s\n' "QA branch:"    "${QA_BRANCH:-—}"
    printf '  %-22s %s\n' "Expected SHA:" "${EXPECTED_SHA:-—}"
    printf '  %-22s %s\n' "Test file:"    "${QA_FILE:-—}"
    printf '  %-22s %s\n' "Source dir:"   "${SRC_DIR:-—}"
    printf '  %-22s %s\n' "Kernel conf:"  "${KERNCONF:-—}"
    printf '\n'
    printf '%bWhat would you like to do?%b\n' "$BLD" "$RST"
    hint "  1) Reuse as-is  — skip all questions, go straight to the menu"
    hint "  2) Modify       — pre-fill with saved values, change if needed"
    hint "  3) New session  — ignore saved session and start fresh"
    printf '\n'
    ask "Choice" "1" _RESUME_CHOICE

    case "${_RESUME_CHOICE}" in
        2)  RESUME_MODE="modify"
            info "Resume mode: MODIFY — saved values pre-filled" ;;
        3)  RESUME_MODE="new"
            QA_ID=""; QA_FILE=""; QA_BRANCH=""; EXPECTED_SHA=""
            JIRA_URL=""; UPSTREAM_PR=""
            KERNEL_REPO="https://github.com/AMDESE/freebsd-src"
            KERNEL_REPO_ALT="ssh://git@sos-git.amd.com/freebsd-src.git"
            SRC_DIR="${SCRIPT_DIR}/dev"; OBJ_DIR="/usr/obj"
            MAKE_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || printf '4')"
            KERNCONF="GENERIC"
            info "Resume mode: NEW" ;;
        *)  RESUME_MODE="reuse"
            info "Resume mode: REUSE — all saved settings unchanged" ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  Phase 1 – Gather info (runs once before the menu loop)
# ══════════════════════════════════════════════════════════════════════════════

gather_info() {

    # ── REUSE: skip all prompts ────────────────────────────────────────────────
    if [ "${RESUME_MODE}" = "reuse" ]; then
        section "Reusing Previous Session"
        printf '  %-22s %s\n' "QA ID:"        "${QA_ID:-—}"
        printf '  %-22s %s\n' "QA branch:"    "${QA_BRANCH:-—}"
        printf '  %-22s %s\n' "Expected SHA:" "${EXPECTED_SHA:-—}"
        printf '  %-22s %s\n' "Test file:"    "${QA_FILE:-—}"
        printf '  %-22s %s\n' "Source dir:"   "${SRC_DIR:-—}"
        printf '  %-22s %s\n' "Kernel conf:"  "${KERNCONF:-—}"
        if [ "${EMAIL_REQUESTED}" -eq 1 ]; then
            printf '  %-22s %s\n' "Email report:" "${REPORT_EMAIL}"
        else
            printf '  %-22s %s\n' "Email report:" "no"
        fi
        printf '\n'
        ask_yn "Proceed with these settings?" "y" || { printf 'Aborted.\n'; exit 1; }
        _save_session_state
        return
    fi

    # ── NEW / MODIFY: collect QA ID ───────────────────────────────────────────
    section "QA Handoff"
    if [ "${RESUME_MODE}" = "modify" ]; then
        printf '%bModify mode%b — saved values pre-filled; press Enter to keep.\n\n' \
            "$BLD" "$RST"
    else
        printf 'Enter the QA ticket identifier from the handoff.\n\n'
    fi

    hint "Jira ticket ID.  Example: SWLSVROS-6363"
    local _qa_ok=0
    while [ "${_qa_ok}" -eq 0 ]; do
        ask "QA ID" "${QA_ID:-}" QA_ID
        if _load_qa_testfile; then
            _qa_ok=1
        else
            printf '%bTry a different ID or Ctrl-C to abort.%b\n' "$YLW" "$RST"
        fi
    done

    # ── Build / path settings ─────────────────────────────────────────────────
    section "Build Settings"
    hint "FreeBSD source directory (will be cloned/reset to the QA branch)."
    hint "WARNING: existing content will be reset to branch HEAD."
    ask "FreeBSD source directory" "${SRC_DIR}" SRC_DIR
    printf '\n'
    hint "Directory for build artefacts (object files)."
    ask "Object directory" "${OBJ_DIR}" OBJ_DIR
    printf '\n'
    hint "Parallel make jobs (auto-detected from hw.ncpu)."
    ask "Parallel make jobs" "${MAKE_JOBS}" MAKE_JOBS
    printf '\n'
    hint "Kernel configuration name (e.g. GENERIC, GENERIC-NODEBUG, AMD64)."
    ask "Kernel conf" "${KERNCONF}" KERNCONF

    # ── Email settings ────────────────────────────────────────────────────────
    section "Email Report (optional)"
    hint "Send the QA report by email after tests finish?"
    hint "Delivery: sendmail → dma → atlsmtp10.amd.com"
    hint "Default list: ${REPORT_EMAIL}"
    printf '\n'
    if ask_yn "Send report by email?" "n"; then
        EMAIL_REQUESTED=1
        ask "Recipient(s) — comma-separated" "${REPORT_EMAIL}" REPORT_EMAIL
    else
        EMAIL_REQUESTED=0
    fi

    # ── Confirmation ──────────────────────────────────────────────────────────
    section "Confirmation"
    printf '  %-22s %s\n' "QA ID:"        "${QA_ID}"
    printf '  %-22s %s\n' "Test file:"    "${QA_FILE}"
    printf '  %-22s %s\n' "QA branch:"    "${QA_BRANCH:-<not found>}"
    printf '  %-22s %s\n' "Expected SHA:" "${EXPECTED_SHA:-<not found>}"
    printf '  %-22s %s\n' "Upstream PR:"  "${UPSTREAM_PR:-n/a}"
    printf '  %-22s %s\n' "Kernel repo:"  "${KERNEL_REPO}"
    printf '  %-22s %s\n' "Source dir:"   "${SRC_DIR}"
    printf '  %-22s %s\n' "Obj dir:"      "${OBJ_DIR}"
    printf '  %-22s %s\n' "Make jobs:"    "${MAKE_JOBS}"
    printf '  %-22s %s\n' "Kernel conf:"  "${KERNCONF}"
    if [ "${EMAIL_REQUESTED}" -eq 1 ]; then
        printf '  %-22s %s\n' "Email report:" "${REPORT_EMAIL}"
    else
        printf '  %-22s %s\n' "Email report:" "no"
    fi
    printf '\n'
    ask_yn "Proceed with these settings?" "y" || { printf 'Aborted.\n'; exit 1; }
    _save_session_state
}

# ══════════════════════════════════════════════════════════════════════════════
#  Menu
# ══════════════════════════════════════════════════════════════════════════════

show_menu() {
    local _bar="══════════════════════════════════════════════════════════════"
    printf '\n%b%s%b\n' "$BLD$BLU" "$_bar" "$RST"
    printf '%b  FreeBSD Kernel QA — Action Menu%b\n' "$BLD" "$RST"
    printf '%b  Session: %s%b\n' "$BLD" "${SESSION_NAME}" "$RST"
    printf '%b%s%b\n\n' "$BLD$BLU" "$_bar" "$RST"

    printf '  %b1)%b Sync source to QA branch\n'    "$YLW" "$RST"
    printf '     %bURL   :%b %s\n'   "$CYN" "$RST" "${KERNEL_REPO}"
    printf '     %bBranch:%b %s\n\n' "$CYN" "$RST" "${QA_BRANCH:-<not set>}"

    printf '  %b2)%b Build world + kernel + install\n\n'  "$YLW" "$RST"

    printf '  %b3)%b Verify running kernel matches QA branch\n'  "$YLW" "$RST"
    printf '     %bExpected SHA:%b %s\n\n' "$CYN" "$RST" "${EXPECTED_SHA:-<not set>}"

    printf '  %b4)%b Run specific QA tests\n'  "$YLW" "$RST"
    printf '     %bScript:%b %s\n\n' "$CYN" "$RST" "${QA_FILE:-<not set>}"

    if [ "${EMAIL_REQUESTED}" -eq 1 ]; then
        printf '  %b5)%b Send last report by email\n'  "$YLW" "$RST"
        printf '     %bTo    :%b %s\n\n' "$CYN" "$RST" "${REPORT_EMAIL}"
    fi

    printf '  %bq)%b Quit\n'  "$YLW" "$RST"
    printf '\n%b%s%b\n' "$BLD$BLU" "$_bar" "$RST"
}

# ── Final result banner ────────────────────────────────────────────────────────
# Called after every test run as the last printed output.

_print_final_result() {
    local _np _nf _nw _bar _label _color
    _np=$(grep -c '^PASS' "${RESULTS_FILE}" 2>/dev/null); _np=${_np:-0}
    _nf=$(grep -c '^FAIL' "${RESULTS_FILE}" 2>/dev/null); _nf=${_nf:-0}
    _nw=$(grep -c '^WARN' "${RESULTS_FILE}" 2>/dev/null); _nw=${_nw:-0}

    _bar="══════════════════════════════════════════════════════════════"

    if [ "${_nf}" -gt 0 ]; then
        _label="FAIL";  _color="${RED}"
    elif [ "${_nw}" -gt 0 ]; then
        _label="PASS WITH WARNINGS"; _color="${YLW}"
    else
        _label="PASS";  _color="${GRN}"
    fi

    printf '\n%b%s%b\n' "$BLD" "$_bar" "$RST"
    printf '%b  RESULT : %b%s%b\n' "$BLD" "$_color" "$_label" "$RST"
    printf '%b  Counts : PASS=%-3d  FAIL=%-3d  WARN=%-3d%b\n' \
        "$BLD" "${_np}" "${_nf}" "${_nw}" "$RST"
    printf '%b  Report : %s%b\n' "$BLD" "${REPORT_FILE}" "$RST"
    printf '%b  Log    : %s%b\n' "$BLD" "${LOG_FILE}" "$RST"
    printf '%b%s%b\n\n' "$BLD" "$_bar" "$RST"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Report generator
# ══════════════════════════════════════════════════════════════════════════════

generate_report() {
    local _np _nf _nw _ns _overall
    _np=$(grep -c '^PASS' "${RESULTS_FILE}" 2>/dev/null); _np=${_np:-0}
    _nf=$(grep -c '^FAIL' "${RESULTS_FILE}" 2>/dev/null); _nf=${_nf:-0}
    _nw=$(grep -c '^WARN' "${RESULTS_FILE}" 2>/dev/null); _nw=${_nw:-0}
    _ns=$(grep -c '^SKIP' "${RESULTS_FILE}" 2>/dev/null); _ns=${_ns:-0}

    if   [ "${_nf}" -gt 0 ]; then _overall="FAIL"
    elif [ "${_nw}" -gt 0 ]; then _overall="PASS WITH WARNINGS"
    else                           _overall="PASS"
    fi

    {
        printf '╔══════════════════════════════════════════════════════════════╗\n'
        printf '║           FreeBSD Kernel QA Test Report                     ║\n'
        printf '╚══════════════════════════════════════════════════════════════╝\n\n'
        printf 'Report file : %s\n' "${REPORT_FILE}"
        printf 'Session     : %s\n' "${SESSION_NAME}"
        printf 'Date        : %s\n' "$(date '+%Y-%m-%d')"
        printf 'Time        : %s\n' "$(date '+%H:%M:%S %Z')"
        printf 'Host        : %s\n' "$(hostname)"
        printf 'System      : %s\n' "$(uname -a)"
        printf '\n'
        printf '─── Handoff Details ────────────────────────────────────────────\n'
        printf 'QA ID         : %s\n' "${QA_ID:-n/a}"
        printf 'Jira          : %s\n' "${JIRA_URL:-n/a}"
        printf 'Upstream PR   : %s\n' "${UPSTREAM_PR:-n/a}"
        printf 'QA Branch     : %s\n' "${QA_BRANCH:-n/a}"
        printf 'Expected SHA  : %s\n' "${EXPECTED_SHA:-n/a}"
        printf 'Actual SHA    : %s\n' "${ACTUAL_SHA:-n/a}"
        printf 'Kernel Repo   : %s\n' "${KERNEL_REPO:-n/a}"
        printf 'Source dir    : %s\n' "${SRC_DIR:-n/a}"
        printf 'Object dir    : %s\n' "${OBJ_DIR:-n/a}"
        printf 'Make jobs     : %s\n' "${MAKE_JOBS:-n/a}"
        printf 'Kernel conf   : %s\n' "${KERNCONF:-n/a}"
        printf '\n'
        printf '─── Test File ──────────────────────────────────────────────────\n'
        printf 'QA ID      : %s\n' "${QA_ID:-n/a}"
        printf 'Test file  : %s\n' "${QA_FILE:-n/a}"
        printf '\n'
        printf '─── Test Results ───────────────────────────────────────────────\n'
        printf 'PASS:%-4d  FAIL:%-4d  WARN:%-4d  SKIP:%-4d\n' \
            "${_np}" "${_nf}" "${_nw}" "${_ns}"
        printf '\n'
        if [ -s "${RESULTS_FILE}" ]; then
            awk -F'\t' '{printf "  [%-4s] %s\n         %s\n", $1, $2, $3}' \
                "${RESULTS_FILE}"
        fi
        printf '\n'
        printf '─── Overall Result ─────────────────────────────────────────────\n'
        printf 'RESULT: %s\n\n' "${_overall}"
        printf '─── Full Session Log ───────────────────────────────────────────\n'
        cat "${LOG_FILE}"
        printf '\n'
        printf '(State  : %s)\n' "${STATE_FILE}"
        printf '(Report : %s)\n' "${REPORT_FILE}"
    } | tee "${REPORT_FILE}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Email report
# ══════════════════════════════════════════════════════════════════════════════

# send_report_email <report_file> <verdict>
# Sends the QA report as a MIME multipart email (body = summary, attachment = report).
# Uses comma-separated REPORT_EMAIL as recipients; delivery via sendmail (dma).
send_report_email() {
    local _report="$1" _verdict="$2"
    local _addr _list _subject _boundary _sep
    _list="${REPORT_EMAIL}"
    _subject="[FreeBSD QA] ${QA_ID}: ${_verdict} — $(hostname -s) $(date '+%Y-%m-%d')"
    _boundary="----=_QAPart_$(date +%s)_$$"
    _sep="--${_boundary}"

    info "Sending email report to: ${_list}"
    local _IFS_save
    _IFS_save="$IFS"
    IFS=','
    for _addr in ${_list}; do
        _addr=$(printf '%s' "${_addr}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "${_addr}" ] && continue
        {
            printf 'From: %s\n' "${SENDER_EMAIL}"
            printf 'To: %s\n' "${_addr}"
            printf 'Subject: %s\n' "${_subject}"
            printf 'MIME-Version: 1.0\n'
            printf 'Content-Type: multipart/mixed; boundary="%s"\n\n' "${_boundary}"
            printf '%s\n' "${_sep}"
            printf 'Content-Type: text/plain; charset=UTF-8\n\n'
            printf 'FreeBSD Kernel QA Report\n'
            printf 'QA ID   : %s\n' "${QA_ID}"
            printf 'Session : %s\n' "${SESSION_NAME}"
            printf 'Verdict : %s\n' "${_verdict}"
            printf 'Host    : %s\n' "$(hostname)"
            printf 'Date    : %s\n\n' "$(date)"
            if [ -f "${_report}" ]; then
                printf '%s\n' "${_sep}"
                printf 'Content-Type: text/plain; charset=UTF-8\n'
                printf 'Content-Disposition: attachment; filename="%s"\n\n' \
                    "$(basename "${_report}")"
                cat "${_report}"
            fi
            printf '%s--\n' "${_sep}"
        } | sendmail -f "${SENDER_EMAIL}" "${_addr}"
    done
    IFS="${_IFS_save}"
    pass "Email sent to: ${_list}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Action 1 – Sync source to QA branch (clone or fetch+reset, auto-detected)
# ══════════════════════════════════════════════════════════════════════════════

# _do_clone — clone KERNEL_REPO (with KERNEL_REPO_ALT fallback) into SRC_DIR.
_do_clone() {
    warn "FreeBSD source is large (~500 MB shallow). This may take several minutes."
    printf '\n'

    if run_long_cmd "git clone: ${QA_BRANCH}" \
            git clone --branch "${QA_BRANCH}" --depth 100 \
            "${KERNEL_REPO}" "${SRC_DIR}"; then
        record PASS "Clone" "${KERNEL_REPO} @ ${QA_BRANCH}"
        return 0
    fi

    fail "Clone from ${KERNEL_REPO} failed."
    printf '%bCommon causes:%b\n' "$BLD" "$RST"
    hint "  • Branch does not exist on this remote"
    hint "  • SSH key not configured (for ssh:// URLs)"
    hint "  • Firewall / VPN blocking access"
    printf '\n'

    if [ -n "${KERNEL_REPO_ALT}" ]; then
        ask "Try fallback URL (Enter to skip)" "${KERNEL_REPO_ALT}" _fb
        if [ -n "${_fb:-}" ]; then
            run_long_cmd "git clone fallback" \
                git clone --branch "${QA_BRANCH}" --depth 100 \
                "${_fb}" "${SRC_DIR}" \
                && record PASS "Clone (fallback)" "${_fb} @ ${QA_BRANCH}" \
                || { record FAIL "Clone" "all clone attempts failed"; return 1; }
        else
            record FAIL "Clone" "aborted by user"
            return 1
        fi
    else
        record FAIL "Clone" "no fallback configured"
        return 1
    fi
}

action_sync_source() {
    section "1 — Sync Source to QA Branch"

    printf '  %-18s %b%s%b\n' "URL:"    "$CYN" "${KERNEL_REPO}"          "$RST"
    printf '  %-18s %b%s%b\n' "Branch:" "$CYN" "${QA_BRANCH:-<not set>}"  "$RST"
    printf '  %-18s %b%s%b\n' "Target:" "$CYN" "${SRC_DIR}"              "$RST"
    printf '\n'

    if [ -d "${SRC_DIR}/.git" ]; then
        local _cur_remote _sync_choice
        _cur_remote=$(git -C "${SRC_DIR}" remote get-url origin 2>/dev/null \
                      || printf 'unknown')
        printf '  %-18s %b%s%b\n' "Current remote:" "$CYN" "${_cur_remote}" "$RST"
        printf '\n'
        printf '%bRepository already exists. Choose:%b\n' "$BLD" "$RST"
        hint "  f) Fetch + reset  — fast incremental update (recommended)"
        hint "  r) Re-clone       — delete and start fresh"
        printf '\n'
        ask "Choice" "f" _sync_choice
        case "${_sync_choice}" in
            r|R)
                run_cmd "rm -rf ${SRC_DIR}" rm -rf "${SRC_DIR}" || return 1
                _do_clone || return 1
                ;;
            *)
                run_cmd "git fetch" \
                    git -C "${SRC_DIR}" fetch --prune origin       || return 1
                run_cmd "git reset to branch HEAD" \
                    git -C "${SRC_DIR}" reset --hard "origin/${QA_BRANCH}" || return 1
                ;;
        esac
    else
        _do_clone || return 1
    fi

    ACTUAL_SHA=$(git -C "${SRC_DIR}" rev-parse HEAD 2>/dev/null || printf 'unknown')
    info "HEAD SHA: ${ACTUAL_SHA}"
    printf 'ACTUAL_SHA=%s\n' "${ACTUAL_SHA}" >> "${STATE_FILE}"

    if [ "${ACTUAL_SHA}" = "${EXPECTED_SHA}" ]; then
        record PASS "Sync" "HEAD matches expected SHA ${EXPECTED_SHA}"
    else
        record WARN "Sync" "HEAD=${ACTUAL_SHA}  expected=${EXPECTED_SHA}"
        warn "HEAD SHA does not match test file. Tests were written for ${EXPECTED_SHA}."
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Action 2 – Build world + kernel + install
# ══════════════════════════════════════════════════════════════════════════════

action_build_world() {
    section "2 — Build World + Kernel + Install"

    if [ ! -d "${SRC_DIR}/.git" ]; then
        fail "${SRC_DIR} is not a git repository."
        hint "Use option 1 to sync the QA branch source first."
        return 1
    fi

    warn "This runs buildworld + buildkernel + installworld + installkernel."
    warn "It can take 30–90 minutes depending on hardware."
    printf '\n'
    ask_yn "Proceed?" "y" || return 0

    run_long_cmd "buildworld (-j${MAKE_JOBS})" \
        make -j"${MAKE_JOBS}" -C "${SRC_DIR}" buildworld \
        || { record FAIL "buildworld" "see ${LOG_FILE}"; return 1; }
    record PASS "buildworld" "completed"

    run_long_cmd "buildkernel (-j${MAKE_JOBS}, KERNCONF=${KERNCONF})" \
        make -j"${MAKE_JOBS}" -C "${SRC_DIR}" buildkernel KERNCONF="${KERNCONF}" \
        || { record FAIL "buildkernel" "see ${LOG_FILE}"; return 1; }
    record PASS "buildkernel" "completed (KERNCONF=${KERNCONF})"

    run_long_cmd "installworld" \
        make -C "${SRC_DIR}" installworld \
        || { record FAIL "installworld" "see ${LOG_FILE}"; return 1; }
    record PASS "installworld" "completed"

    # Install the QA kernel to a temporary directory so the running kernel is
    # untouched.  nextboot(8) schedules /boot/kernel.qa for one boot only;
    # if the new kernel panics or fails, a second reboot automatically falls
    # back to the original /boot/kernel.
    local _qa_kodir
    _qa_kodir="/boot/kernel.qa"
    rm -rf "${_qa_kodir}"
    run_long_cmd "installkernel (→ ${_qa_kodir})" \
        make -C "${SRC_DIR}" installkernel KODIR="${_qa_kodir}" KERNCONF="${KERNCONF}" \
        || { record FAIL "installkernel" "see ${LOG_FILE}"; return 1; }
    record PASS "installkernel" "installed to ${_qa_kodir}"

    nextboot -k "kernel.qa" \
        || { record FAIL "nextboot" "could not schedule next-boot kernel"; return 1; }
    record PASS "nextboot" "kernel.qa scheduled for next boot only"

    printf '\n'
    warn "QA kernel installed to ${_qa_kodir} — original /boot/kernel is untouched."
    warn "nextboot(8) will load kernel.qa on the NEXT boot only."
    warn "If the new kernel fails or panics, reboot again to return to the original kernel."
    printf '\n'
    ask_yn "Reboot now?" "n" && { info "Rebooting..."; sudo reboot; }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Action 3 – Verify running kernel matches the QA branch
# ══════════════════════════════════════════════════════════════════════════════

action_check_kernel() {
    section "3 — Verify Running Kernel Matches QA Branch"

    local _uname_v _running_short _expected_short
    _uname_v=$(uname -v)

    printf '  %-22s %s\n' "Running kernel:"  "$(uname -r)"
    printf '  %-22s %s\n' "Kernel version:"  "${_uname_v}"
    printf '  %-22s %s\n' "Expected branch:" "${QA_BRANCH:-<not set>}"
    printf '  %-22s %s\n' "Expected SHA:"    "${EXPECTED_SHA:-<not set>}"
    printf '\n'

    info "CMD: uname -a"
    info "$(uname -a)"
    info "CMD: uname -v"
    info "${_uname_v}"

    # FreeBSD-CURRENT normally embeds the git short hash as gXXXXXXX in uname -v.
    # AMD QA branches use a different naming convention that appends the SHA as
    # a branch name suffix: <branch>-<sha>:  (no leading 'g').
    # Try the standard pattern first; fall back to the AMD branch-suffix pattern.
    _running_short=$(printf '%s' "${_uname_v}" \
        | grep -oE 'g[0-9a-f]{7,12}' | head -1 | sed 's/^g//')
    if [ -z "${_running_short}" ]; then
        # AMD branch suffix pattern: -<7..12 hex chars>:
        _running_short=$(printf '%s' "${_uname_v}" \
            | grep -oE '\-[0-9a-f]{7,12}:' | head -1 | sed 's/^-//;s/:$//')
    fi
    _expected_short=$(printf '%s' "${EXPECTED_SHA}" | cut -c1-12)

    if [ -n "${_running_short}" ]; then
        info "Hash in uname -v : ${_running_short}"
        info "Expected SHA     : ${EXPECTED_SHA}"
        if printf '%s' "${EXPECTED_SHA}" | grep -q "^${_running_short}"; then
            pass "Running kernel SHA (${_running_short}) matches QA branch"
            record PASS "Kernel check" \
                "running=${_running_short} ⊆ expected=${EXPECTED_SHA}"
        else
            fail "SHA mismatch: running=${_running_short}, expected starts ${_expected_short}"
            record FAIL "Kernel check" \
                "running=${_running_short} expected=${_expected_short}"
            hint "If you ran option 2, reboot to activate the new kernel."
        fi
    else
        warn "No git hash found in uname -v — falling back to source tree check."
        if [ -d "${SRC_DIR}/.git" ]; then
            ACTUAL_SHA=$(git -C "${SRC_DIR}" rev-parse HEAD 2>/dev/null \
                         || printf 'unknown')
            info "CMD: git -C ${SRC_DIR} rev-parse HEAD"
            info "Source tree HEAD: ${ACTUAL_SHA}"
            if [ "${ACTUAL_SHA}" = "${EXPECTED_SHA}" ]; then
                pass "Source tree matches expected SHA (reboot may be needed to activate)"
                record PASS "Kernel check" \
                    "source SHA matches — boot status unknown without uname hash"
            else
                fail "Source tree SHA mismatch: ${ACTUAL_SHA} vs ${EXPECTED_SHA}"
                record FAIL "Kernel check" \
                    "source=${ACTUAL_SHA}  expected=${EXPECTED_SHA}"
            fi
        else
            warn "No source tree at ${SRC_DIR} — cannot verify SHA."
            record WARN "Kernel check" "no source tree available for comparison"
        fi
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Internal test runners (no report — callers decide when to generate it)
# ══════════════════════════════════════════════════════════════════════════════

# _exec_specific_tests — runs qa-branches/<ID>/<ID>.sh, records results.
_exec_specific_tests() {
    if [ -z "${QA_FILE:-}" ] || [ ! -f "${QA_FILE}" ]; then
        fail "QA test file not found: ${QA_FILE:-<unset>}"
        record FAIL "Specific QA: ${QA_ID}" "test file missing"
        return 1
    fi

    info "CMD: sh ${QA_FILE}"
    printf '\n>>> QA test: %s\n' "${QA_FILE}" >> "${LOG_FILE}"

    local _out_tmp _rc _tp _tf _ts
    _out_tmp=$(mktemp /tmp/qa-out.XXXXXX)

    sh "${QA_FILE}" 2>&1 | tee -a "${LOG_FILE}" | tee "${_out_tmp}"
    _rc=$?

    _tp=$(grep -c '^\[PASS\]' "${_out_tmp}" 2>/dev/null || printf '0')
    _tf=$(grep -c '^\[FAIL\]' "${_out_tmp}" 2>/dev/null || printf '0')
    _ts=$(grep -c '^\[SKIP\]' "${_out_tmp}" 2>/dev/null || printf '0')
    rm -f "${_out_tmp}"

    if [ "${_rc}" -eq 0 ]; then
        record PASS "Specific QA: ${QA_ID}" \
            "exit 0 — PASS:${_tp} FAIL:${_tf} SKIP:${_ts}"
    else
        record FAIL "Specific QA: ${QA_ID}" \
            "exit ${_rc} — PASS:${_tp} FAIL:${_tf} SKIP:${_ts}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Action 4  (public wrapper: run tests → report → final banner)
# ══════════════════════════════════════════════════════════════════════════════

action_run_specific() {
    section "4 — Run Specific QA Tests: ${QA_ID}"
    _exec_specific_tests
    generate_report
    _print_final_result
    if [ "${EMAIL_REQUESTED}" -eq 1 ]; then
        local _verdict
        _verdict="PASS"
        grep -q '^FAIL' "${RESULTS_FILE}" 2>/dev/null && _verdict="FAIL"
        send_report_email "${REPORT_FILE}" "${_verdict}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Menu loop
# ══════════════════════════════════════════════════════════════════════════════

run_menu() {
    local _choice
    while true; do
        show_menu
        printf '%b Choice%b: ' "$BLD" "$RST"
        read -r _choice

        case "${_choice}" in
            1) action_sync_source   ;;
            2) action_build_world   ;;
            3) action_check_kernel  ;;
            4) action_run_specific  ;;
            5)
                if [ -f "${REPORT_FILE}" ]; then
                    local _v="UNKNOWN"
                    grep -q '^FAIL' "${RESULTS_FILE}" 2>/dev/null && _v="FAIL" || _v="PASS"
                    send_report_email "${REPORT_FILE}" "${_v}"
                else
                    warn "No report file yet — run option 4 first."
                fi
                ;;
            q|Q)
                printf '\n%bSession log : %s%b\n'    "$BLD" "${LOG_FILE}"  "$RST"
                printf '%bReport dir  : %s%b\n\n'    "$BLD" "${REPORT_DIR}" "$RST"
                exit 0 ;;
            "")
                ;;
            *)
                warn "Unknown choice '${_choice}' — enter 1-5 or q." ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    local _bar="╔══════════════════════════════════════════════════════════════╗"
    local _bar2="╚══════════════════════════════════════════════════════════════╝"
    printf '%b%s%b\n' "$BLD$BLU" "$_bar" "$RST"
    printf '%b║       FreeBSD Kernel QA Testing Environment                 ║%b\n' \
        "$BLD$BLU" "$RST"
    printf '%b%s%b\n' "$BLD$BLU" "$_bar2" "$RST"
    printf '\nSession : %b%s%b\n'  "$YLW" "${SESSION_NAME}" "$RST"
    printf 'Reports : %s\n\n'     "${REPORT_DIR}"

    load_previous_session
    gather_info
    run_menu
}

main
