#!/usr/bin/env bash
# create-versions.sh --devhub <alias> [--packages <list>] [--no-code-coverage] [--plan]
#
# Builds one 2GP package version of each chosen BarnCRM package, in dependency order, from the
# current checkout (D-199, D-200 N5). See docs/contributor-guide/ci.md, "Creating package
# versions".
#
# It reads the namespace, the packages, their order and their 0Ho ids from sfdx-project.json
# through scripts/org/package-upgrade-helper.py (the same reader the install and upgrade test
# uses) and hard-codes none of them.
#
# It REFUSES while the namespace is empty (plan D-87, D-199: no version is ever created
# without the registered namespace) and while a chosen package has no 0Ho id in
# packageAliases: `sf package create` is the owner's step, and the ids it prints are pasted
# there. It prints the Dev Hub's Package2VersionCreates limit before anything else, and it
# NEVER PROMOTES: promotion is permanent and is the owner's decision, made per version with
# `sf package version promote`.
#
# OPTIONS
#   --devhub <alias>     Dev Hub linked to the namespace (required; the CLI default is never used)
#   --packages <list>    package keys (folder names); default all; dependencies are added
#   --no-code-coverage   skip the test run (a version built this way can never be promoted)
#   --wait <minutes>     per version (default 120)
#   --out <file>         where the "<key> <04t id>" lines go (default
#                        test-results/package-versions/<run id>.txt, the --from/--to file
#                        format of scripts/org/package-upgrade-test.sh)
#   --plan               print the limit command, the order and every command; run nothing
#   --project <file>     sfdx-project.json to read (default the repo's; for tests)
#
# Exit codes: 0 = every version built (or --plan); 1 = a build failed; 2 = refused.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_PY="$REPO_ROOT/scripts/org/package-upgrade-helper.py"
PROJECT="$REPO_ROOT/sfdx-project.json"
helper() { python3 "$HELPER_PY" "$@"; }

DEVHUB=""
PACKAGES="all"
COVERAGE=1
WAIT=120
OUT=""
PLAN=0

usage() {
  sed -n '2p;/^# OPTIONS/,/^# Exit codes/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit "${1:-2}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --devhub) DEVHUB="${2:?--devhub needs an alias}"; shift ;;
    --packages) PACKAGES="${2:?--packages needs a list}"; shift ;;
    --no-code-coverage) COVERAGE=0 ;;
    --wait) WAIT="${2:?--wait needs minutes}"; shift ;;
    --out) OUT="${2:?--out needs a file}"; shift ;;
    --plan) PLAN=1 ;;
    --project) PROJECT="${2:?--project needs a file}"; shift ;;
    -h | --help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

NS="$(helper namespace --project "$PROJECT")"
DEVHUB_SHOWN="${DEVHUB:-<devhub>}"
ALIAS_LINES="$(helper aliases --project "$PROJECT" --select "$PACKAGES")" || exit 2
KEYS=(); NAMES=(); IDS=()
while IFS=$'\t' read -r key name id; do
  KEYS+=("$key"); NAMES+=("$name"); IDS+=("$id")
done <<<"$ALIAS_LINES"

echo "Create package versions$([[ "$PLAN" == 1 ]] && echo " (PLAN ONLY: nothing is run)")"
echo "Namespace: ${NS:-<empty>}    Dev Hub: $DEVHUB_SHOWN    Packages: ${#KEYS[@]}"
echo "Order: ${KEYS[*]}"
echo "Never promotes. Promotion is permanent and the owner's decision (sf package version promote)."

refuse=()
[[ -n "$NS" ]] || refuse+=("namespace is empty in sfdx-project.json (D-87, D-199: register it and set it first)")
[[ -n "$DEVHUB" ]] || refuse+=("--devhub not given (the CLI default is never used)")
missing=()
for i in "${!KEYS[@]}"; do
  [[ "${IDS[$i]}" == - ]] && missing+=("$i")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  refuse+=("no 0Ho id in packageAliases for ${#missing[@]} package(s); the owner creates each once:")
  for i in "${missing[@]}"; do
    refuse+=("    sf package create --name \"${NAMES[$i]}\" --package-type Managed --path packages/${KEYS[$i]} --target-dev-hub $DEVHUB_SHOWN")
  done
fi

echo
echo "Dev Hub limit (each version counts once against Package2VersionCreates):"
echo "  \$ sf limits api display --target-org $DEVHUB_SHOWN --json"
if [[ "$PLAN" == 0 && ${#refuse[@]} -eq 0 ]]; then
  limit="$(sf limits api display --target-org "$DEVHUB" --json 2>/dev/null | helper limit Package2VersionCreates || true)"
  echo "  Package2VersionCreates remaining/max: ${limit:-unknown} (this run needs ${#KEYS[@]})"
  if [[ -n "$limit" && "${limit%% *}" =~ ^[0-9]+$ && "${limit%% *}" -lt ${#KEYS[@]} ]]; then
    refuse+=("only ${limit%% *} version creates left today; narrow with --packages")
  fi
fi

if [[ ${#refuse[@]} -gt 0 ]]; then
  echo
  echo "Not ready:"
  printf '  %s\n' "${refuse[@]}"
  if [[ "$PLAN" == 0 ]]; then
    echo "Refusing to build." >&2
    exit 2
  fi
fi

flags=(--installation-key-bypass --wait "$WAIT" --target-dev-hub "$DEVHUB_SHOWN" --json)
[[ "$COVERAGE" == 1 ]] && flags=(--code-coverage "${flags[@]}")
OUT="${OUT:-$REPO_ROOT/test-results/package-versions/$(date +%Y%m%d-%H%M%S).txt}"

echo
echo "Builds (dependency order; each dependency resolves to its newest 1.x.y.LATEST build):"
if [[ "$PLAN" == 1 ]]; then
  for i in "${!KEYS[@]}"; do
    echo "  [${KEYS[$i]}] \$ sf package version create --package \"${NAMES[$i]}\" ${flags[*]}"
  done
  echo
  echo "Plan only: nothing was run. The 04t ids would be written to $OUT."
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
: >"$OUT"
LAST="$(mktemp -t barn-version-XXXXXX)"
trap 'rm -f "$LAST"' EXIT
for i in "${!KEYS[@]}"; do
  echo "  [${KEYS[$i]}] building..."
  status=0
  (cd "$REPO_ROOT" && sf package version create --package "${NAMES[$i]}" "${flags[@]}") >"$LAST" 2>/dev/null || status=$?
  id="$(helper jget result.SubscriberPackageVersionId <"$LAST")"
  if [[ "$status" != 0 || "$id" != 04t* ]]; then
    echo "  [${KEYS[$i]}] FAILED: $(helper jget message <"$LAST" | head -c 300)" >&2
    echo "Stopped: the packages after it depend on it. Built so far: $OUT" >&2
    exit 1
  fi
  echo "${KEYS[$i]} $id" >>"$OUT"
  echo "  [${KEYS[$i]}] $id"
done
echo
echo "Built ${#KEYS[@]} version(s), none promoted. Ids: $OUT"
