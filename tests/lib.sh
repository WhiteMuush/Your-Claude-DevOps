# shellcheck shell=bash
# Shared helpers for the tests: throwaway home folders, a scripted run and a simple check.

PASSED=0
FAILED=0
TEST_HOME=""
OUTPUT=""
STATUS=0

TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT
trap 'rm -rf "${TEST_ROOT}"' EXIT

new_home() {
  TEST_HOME=$(mktemp -d "${TEST_ROOT}/home.XXXX")
}

# Runs a script of the repository with the given answers on stdin, one per line, and keeps its output and status.
run_script() {
  local script=$1 answers=$2
  shift 2
  STATUS=0
  OUTPUT=$(printf '%b' "${answers}" | HOME="${TEST_HOME}" INSTALL_ASSUME_TTY=1 NO_COLOR=1 \
    bash "${REPO_DIR}/${script}" "$@" 2>&1) || STATUS=$?
}

run_install() {
  local answers=$1
  shift
  run_script install.sh "${answers}" "$@"
}

run_restore() {
  run_script restore.sh "$1"
}

tree_checksum() {
  (cd "$1" && find . -type f -print0 | sort -z | xargs -0 cksum)
}

check() {
  local description=$1
  shift
  if "$@"; then
    PASSED=$((PASSED + 1))
    printf '  ok      %s\n' "${description}"
  else
    FAILED=$((FAILED + 1))
    printf '  FAILED  %s\n' "${description}"
    printf '%s\n' "${OUTPUT}" | sed 's/^/          | /'
  fi
}

finish() {
  printf '\n%s passed, %s failed\n' "${PASSED}" "${FAILED}"
  (( FAILED == 0 ))
}
