# Shared by pre-commit and pre-push. Sourced, never run.
#
# This repository is public, so there are two leaks and both are checked:
#
#   the identity  git stamps on a commit. A real address shows on every commit
#                 page, forever, and taking it back means rewriting every SHA.
#   the content   of the change. An absolute path names the machine, and
#                 usually whoever owns it.
#
# One copy of the rules, because two would drift and the half that drifted is
# the half nobody tests.

pi_fail=0

pi_flag() {
    if [ "$pi_fail" -eq 0 ]; then
        printf '\n  BLOCKED - personal information in the change.\n\n'
        pi_fail=1
    fi
    printf '  %s\n' "$1"
}

pi_show() {
    printf '%s\n' "$1" | sed 's/^/      /'
}

pi_failed() {
    [ "$pi_fail" -ne 0 ]
}

# pi_check_email <what> <address>
pi_check_email() {
    case "$2" in
        *@users.noreply.github.com|noreply@anthropic.com|'') ;;
        *)
            pi_flag "identity: $1 is <$2>, a real address."
            pi_flag "  git config user.email '<id>+<name>@users.noreply.github.com'"
            ;;
    esac
}

# pi_scan <added lines> [label]
#
# Added lines only. A match already sitting in a file must not block a change
# that did not introduce it - which is what keeps a web re-export, rewriting
# web/index.js whole, from tripping over Emscripten's own /home/web_user.
pi_scan() {
    _added=$1
    _where=${2:+ ($2)}
    [ -n "$_added" ] || return 0

    # An absolute Windows path. The leading boundary keeps ordinary prose out:
    # without it, "missing:\nThe" in a JavaScript string reads as a drive letter.
    _hits=$(printf '%s\n' "$_added" \
        | grep -E '(^|[^A-Za-z0-9_])[A-Za-z]:[\/][A-Za-z0-9_]' | head -3)
    [ -n "$_hits" ] && {
        pi_flag "absolute path$_where: names the machine it was written on."
        pi_show "$_hits"
    }

    # An absolute Unix home path. /home/web_user is Emscripten's own default and
    # is baked into every Godot web export.
    _hits=$(printf '%s\n' "$_added" \
        | grep -E '/(home|Users)/[A-Za-z0-9._-]+' \
        | grep -v '/home/web_user' | head -3)
    [ -n "$_hits" ] && {
        pi_flag "absolute path$_where: names a user account."
        pi_show "$_hits"
    }

    # An email address that is not one of the two anonymous ones.
    _hits=$(printf '%s\n' "$_added" \
        | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
        | grep -v -E '@users\.noreply\.github\.com$|^noreply@anthropic\.com$' \
        | sort -u | head -3)
    [ -n "$_hits" ] && {
        pi_flag "email address$_where in the change."
        pi_show "$_hits"
    }

    # Whatever the machine's owner has said is personal. `grep -f` has no
    # comment syntax - every line of that file is a pattern - so a `#` line in
    # it matches any line containing a `#`, and a blank line matches
    # everything. Strip both.
    _patterns="$(git rev-parse --show-toplevel)/private_patterns.txt"
    if [ -f "$_patterns" ]; then
        _pats=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$_patterns")
        if [ -n "$_pats" ]; then
            _hits=$(printf '%s\n' "$_added" | grep -E "$_pats" | head -3)
            [ -n "$_hits" ] && {
                pi_flag "matches a pattern in private_patterns.txt$_where."
                pi_show "$_hits"
            }
        fi
    fi

    return 0
}
