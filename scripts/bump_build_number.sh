#!/bin/sh

set -eu

COUNTER_FILE="${SRCROOT}/.build-number"
INITIAL_BUILD_NUMBER="${CURRENT_PROJECT_VERSION:-1}"
INFO_PLIST_PATH="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

case "${INITIAL_BUILD_NUMBER}" in
  ''|*[!0-9]*)
    echo "error: CURRENT_PROJECT_VERSION must be a positive integer, got '${INITIAL_BUILD_NUMBER}'" >&2
    exit 1
    ;;
esac

if [ ! -f "${COUNTER_FILE}" ]; then
  mkdir -p "$(dirname "${COUNTER_FILE}")"
  printf '%s\n' "${INITIAL_BUILD_NUMBER}" > "${COUNTER_FILE}"
fi

CURRENT_BUILD_NUMBER="$(tr -d '[:space:]' < "${COUNTER_FILE}")"

case "${CURRENT_BUILD_NUMBER}" in
  ''|*[!0-9]*)
    echo "error: ${COUNTER_FILE} must contain only digits" >&2
    exit 1
    ;;
esac

NEXT_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
printf '%s\n' "${NEXT_BUILD_NUMBER}" > "${COUNTER_FILE}"

if /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST_PATH}" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEXT_BUILD_NUMBER}" "${INFO_PLIST_PATH}"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${NEXT_BUILD_NUMBER}" "${INFO_PLIST_PATH}"
fi

echo "Auto-incremented CFBundleVersion to ${NEXT_BUILD_NUMBER}"
