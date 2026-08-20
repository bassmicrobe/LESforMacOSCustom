#!/bin/sh

set -eu

readonly LUACHECK_WARNING_BASELINE="${LUACHECK_WARNING_BASELINE:-62}"
lint_log="$(mktemp)"
trap 'rm -f "${lint_log}"' EXIT HUP INT TERM

set +e
luacheck extensions/les/ --no-color >"${lint_log}" 2>&1
lint_status=$?
set -e
cat "${lint_log}"

summary="$(sed -n 's/^Total: \([0-9][0-9]*\) warnings \/ \([0-9][0-9]*\) errors.*/\1 \2/p' "${lint_log}")"
if [ "${lint_status}" -ne 0 ]; then
    if [ -z "${summary}" ]; then
        echo "luacheck failed without a parseable summary" >&2
        exit "${lint_status}"
    fi

    warnings="${summary%% *}"
    errors="${summary##* }"
    if [ "${errors}" -ne 0 ] || [ "${warnings}" -gt "${LUACHECK_WARNING_BASELINE}" ]; then
        echo "luacheck exceeded baseline: warnings=${warnings}/${LUACHECK_WARNING_BASELINE}, errors=${errors}" >&2
        exit "${lint_status}"
    fi
    echo "luacheck baseline accepted: ${warnings} existing warnings, 0 errors"
fi

echo ""
echo "=== busted ==="
exec busted extensions/les/tests/
