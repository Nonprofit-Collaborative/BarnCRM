#!/usr/bin/env bash
# package-upgrade-test.sh --from <ref|04t file> --to <ref|04t file> [options]
#
# The real package install-and-upgrade test (Brandon, 2026-11-12: "Please script a real package
# install-and-upgrade test before the first pilot."). For each org shape it creates a scratch
# org, installs version N-1 of every chosen BarnCRM package in dependency order, checks it,
# loads the sample data, upgrades every package to version N, and checks again: installed
# versions, Health Check, Error Log, record counts and smoke assertions. With
# --uninstall-check it then removes one module and checks that Core still works and that the
# module left nothing behind (plan Principle 3). See docs/contributor-guide/ci.md, "Package
# install and upgrade test".
#
# WHY IT REFUSES TO RUN TODAY. It installs real package versions, which need the namespace,
# the Dev Hub and the steward entity to be settled first (plan D-87). D-173 places the first
# run after the v1.0 test cycle and before the first production pilot, as a sandbox-only
# managed beta. Until sfdx-project.json carries the namespace it exits 2 unless --plan is
# given. It reads the namespace, the packages and their dependency order from
# sfdx-project.json and hard-codes none of them.
#
# --plan prints every step and command for the chosen options and touches nothing: no org, no
# Dev Hub, no worktree, no file. It also prints the readiness list (namespace, package
# aliases, ancestors, post-install scripts, global entry points), which a real run requires
# to be clean before it creates anything. scripts/ci/tests/test_package_upgrade_test.py runs
# it this way.
#
# VERSIONS. --from (N-1) and --to (N) each take a git ref, whose source is built into package
# versions in a temporary worktree (`sf package version create --code-coverage
# --installation-key-bypass --wait`), or a file of existing subscriber package version ids,
# one "<package key> <04t id>" per line. --type says how the packages are registered in the
# Dev Hub (it cannot change that; the run checks it): managed (default, D-173) or unlocked.
#   managed: a beta version cannot be upgraded, so N-1 must be released. From a 04t file the
#            ids must be released versions; from a git ref the run refuses unless
#            --promote-from is given, which PROMOTES each N-1 version. Promotion is permanent
#            and needs the owner's approval. Post-install scripts run on their own (they must
#            be named as postInstallScript in sfdx-project.json).
#   unlocked: unpromoted versions install in scratch orgs. A post-install script runs for
#            managed packages only, so after every install and upgrade the run calls each
#            package's runSetup as the admin itself.
#
# CREATING ORGS NEEDS THE OWNER'S APPROVAL (project rules: test orgs are fixed; any other org
# is approved first). A real run creates one scratch org per shape and requires
# --yes-create-orgs as that approval's record. Orgs are deleted at the end unless
# --keep-orgs.
#
# SECRETS. Never prints an auth URL or token and never reads `sf org display --verbose`. The
# JSON from `sf org create scratch` holds an access token, so only the username is taken from
# it (through the helper) and the rest is neither printed nor written.
#
# OPTIONS
#   --devhub <alias>        Dev Hub for versions and scratch orgs (required to run; the CLI
#                           default is never used)
#   --from <ref|file>       version N-1            --to <ref|file>   version N
#   --shapes <list>         platform,sales,npsp,npc (default: all four, plan Section 4.2)
#   --packages <list>       package keys (folder names); default all; dependencies are added
#   --type managed|unlocked default managed (D-173)
#   --promote-from          managed only: promote the N-1 versions built from --from
#   --uninstall-check[=<key>]  after the upgrade, uninstall a module (default volunteers)
#   --keep-orgs             leave the scratch orgs for a look
#   --report <dir>          default test-results/package-upgrade/<run id>
#   --yes-create-orgs       the owner approved creating the scratch orgs
#   --plan                  print the steps and commands; run nothing
#   --project <file>        sfdx-project.json to read (default the repo's; for tests)
#
# Exit codes: 0 = every step passed (or --plan); 1 = a step failed (see the report);
# 2 = refused: usage, readiness, or no namespace.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_PY="$REPO_ROOT/scripts/org/package-upgrade-helper.py"
TEMPLATES="$REPO_ROOT/scripts/org/package-upgrade-test"
PROJECT="$REPO_ROOT/sfdx-project.json"

VERSION_WAIT=120
INSTALL_WAIT=60
PUBLISH_WAIT=30
ORG_DAYS=1

PLAN=0
DEVHUB=""
FROM=""
TO=""
SHAPES="platform,sales,npsp,npc"
PACKAGES="all"
TYPE="managed"
PROMOTE=0
UNINSTALL=""
KEEP_ORGS=0
REPORT=""
YES_ORGS=0

usage() { # exit code
  {
    sed -n '2p' "${BASH_SOURCE[0]}"
    awk '/^# OPTIONS/,/^# Exit codes/' "${BASH_SOURCE[0]}"
  } | sed 's/^# \{0,1\}//' >&2
  exit "${1:-2}"
}

helper() { python3 "$HELPER_PY" "$@"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN=1 ;;
    --devhub) DEVHUB="${2:?--devhub needs an alias}"; shift ;;
    --from) FROM="${2:?--from needs a value}"; shift ;;
    --to) TO="${2:?--to needs a value}"; shift ;;
    --shapes) SHAPES="${2:?--shapes needs a list}"; shift ;;
    --packages) PACKAGES="${2:?--packages needs a list}"; shift ;;
    --type) TYPE="${2:?--type needs managed or unlocked}"; shift ;;
    --promote-from) PROMOTE=1 ;;
    --uninstall-check) UNINSTALL="volunteers" ;;
    --uninstall-check=*) UNINSTALL="${1#*=}" ;;
    --keep-orgs) KEEP_ORGS=1 ;;
    --report) REPORT="${2:?--report needs a directory}"; shift ;;
    --yes-create-orgs) YES_ORGS=1 ;;
    --project) PROJECT="${2:?--project needs a file}"; shift ;;
    -h | --help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

[[ -n "$FROM" && -n "$TO" ]] || { echo "Both --from and --to are required." >&2; usage; }
[[ "$TYPE" == managed || "$TYPE" == unlocked ]] || { echo "--type is managed or unlocked." >&2; exit 2; }
if [[ "$PROMOTE" == 1 && "$TYPE" != managed ]]; then
  echo "--promote-from applies to --type managed only." >&2
  exit 2
fi

# A git ref or a file of 04t ids.
kind_of() {
  if [[ -f "$1" ]]; then
    echo list
  elif git -C "$REPO_ROOT" rev-parse --verify --quiet "$1^{commit}" >/dev/null; then
    echo ref
  else
    echo "--from/--to '$1' is neither a file of 04t ids nor a git ref." >&2
    exit 2
  fi
}
FROM_KIND="$(kind_of "$FROM")" || exit 2
TO_KIND="$(kind_of "$TO")" || exit 2

NS="$(helper namespace --project "$PROJECT")"
if [[ -z "$NS" && "$PLAN" == 0 ]]; then
  echo "Refusing to run: the namespace in sfdx-project.json is empty." >&2
  echo "Package versions wait for the namespace, Dev Hub and steward entity (plan D-87, D-173)." >&2
  echo "Use --plan to see what the test would do." >&2
  exit 2
fi
NS_SHOWN="${NS:-<namespace>}"
DEVHUB_SHOWN="${DEVHUB:-<devhub>}"

# The chosen packages, in dependency order, as parallel arrays (bash 3.2 has no maps).
KEYS=()
NAMES=()
HANDLERS=()
PACKAGE_LINES="$(helper packages --project "$PROJECT" --root "$REPO_ROOT" --select "$PACKAGES")" || exit 2
while IFS=$'\t' read -r key name _path handler; do
  KEYS+=("$key")
  NAMES+=("$name")
  HANDLERS+=("$handler")
done <<<"$PACKAGE_LINES"

has_key() {
  local key
  for key in "${KEYS[@]}"; do [[ "$key" == "$1" ]] && return 0; done
  return 1
}

if [[ -n "$UNINSTALL" ]]; then
  has_key "$UNINSTALL" || { echo "--uninstall-check: $UNINSTALL is not among the chosen packages." >&2; exit 2; }
  [[ "$UNINSTALL" != core ]] || { echo "--uninstall-check: Core cannot be uninstalled under its modules." >&2; exit 2; }
  NEEDED_BY="$(helper dependents --project "$PROJECT" --root "$REPO_ROOT" --select "$PACKAGES" --key "$UNINSTALL" | tr '\n' ' ')"
  if [[ -n "${NEEDED_BY// /}" ]]; then
    echo "--uninstall-check: $UNINSTALL is needed by $NEEDED_BY; choose a module nothing chosen depends on." >&2
    exit 2
  fi
fi

SHAPE_LIST=()
SHAPE_DEFS=()
SHAPE_EDITIONS=()
IFS=',' read -r -a REQUESTED_SHAPES <<<"$SHAPES"
for shape in "${REQUESTED_SHAPES[@]}"; do
  line="$(helper shape --root "$REPO_ROOT" "$shape")" || exit 2
  SHAPE_LIST+=("$shape")
  SHAPE_DEFS+=("$(cut -f1 <<<"$line")")
  SHAPE_EDITIONS+=("$(cut -f2 <<<"$line")")
done

# Version ids, "<phase>:<key>=<04t>" per line; phase is n1 (N-1) or n (N).
IDS=""
for phase in n1 n; do
  source_value="$FROM"; source_kind="$FROM_KIND"
  [[ "$phase" == n ]] && { source_value="$TO"; source_kind="$TO_KIND"; }
  if [[ "$source_kind" == list ]]; then
    version_lines="$(helper versions --project "$PROJECT" --select "$PACKAGES" --file "$source_value")" || exit 2
    while IFS=$'\t' read -r key id; do
      IDS+="$phase:$key=$id"$'\n'
    done <<<"$version_lines"
  fi
done
id_of() { # phase key
  local found
  found="$(printf '%s' "$IDS" | awk -F= -v k="$1:$2" '$1 == k { print $2 }')"
  echo "${found:-<04t $1 $2>}"
}

# ---------------------------------------------------------------- output and step bookkeeping

quote() {
  local arg out=""
  for arg in "$@"; do
    if [[ "$arg" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]]; then out+="$arg "; else out+="'${arg//\'/\'\\\'\'}' "; fi
  done
  echo "${out% }"
}
show() { echo "      \$ $(quote "$@")"; }

RUN_ID="$(date +%Y%m%d-%H%M%S)"
REPORT="${REPORT:-$REPO_ROOT/test-results/package-upgrade/$RUN_ID}"
WORK=""
STEPS=""
LOG=/dev/null
LAST=/dev/null
STEP_MSG=""
SHAPE_FAILED=0
FAILED=0
LIVE_ORGS=""
WORKTREES=""

# Runs one sf command with --json; output goes to the step log and $LAST, never the terminal.
sfrun() {
  show sf "$@" --json
  [[ "$PLAN" == 1 ]] && return 0
  local status=0
  sf "$@" --json >"$LAST" 2>>"$LOG" || status=$?
  cat "$LAST" >>"$LOG"
  if [[ "$status" != 0 ]]; then
    STEP_MSG="$(helper jget message <"$LAST" | head -c 300 | tr '\n\t' '  ')"
  fi
  return "$status"
}

# run_step <shape> <step> <function> [args]: times the step and records pass, fail or skip.
# After a failure in a shape, the rest of that shape is skipped (cleanup steps excepted).
run_step() {
  local shape="$1" step="$2" always=0
  shift 2
  [[ "$1" == --always ]] && { always=1; shift; }
  echo "  [$step]"
  if [[ "$PLAN" == 1 ]]; then
    "$@"
    return 0
  fi
  if [[ "$SHAPE_FAILED" == 1 && "$always" == 0 ]]; then
    printf '%s\t%s\tskip\t0\t%s\n' "$shape" "$step" "an earlier step failed" >>"$STEPS"
    echo "      skipped"
    return 0
  fi
  LOG="$REPORT/logs/${shape}-${step//[:\/]/-}.log"
  STEP_MSG=""
  local start status=0
  start="$(date +%s)"
  "$@" || status=$?
  local seconds=$(($(date +%s) - start))
  if [[ "$status" == 0 ]]; then
    printf '%s\t%s\tpass\t%s\t%s\n' "$shape" "$step" "$seconds" "$STEP_MSG" >>"$STEPS"
    echo "      pass (${seconds}s)${STEP_MSG:+ $STEP_MSG}"
  else
    printf '%s\t%s\tfail\t%s\t%s\n' "$shape" "$step" "$seconds" "${STEP_MSG:-see logs/}" >>"$STEPS"
    echo "      FAIL (${seconds}s) ${STEP_MSG:-see $LOG}"
    SHAPE_FAILED=1
    FAILED=1
  fi
}

cleanup() {
  local tree
  for tree in $WORKTREES; do git -C "$REPO_ROOT" worktree remove --force "$tree" >/dev/null 2>&1 || true; done
  [[ -n "$WORK" ]] && rm -rf "$WORK"
  if [[ -n "${LIVE_ORGS// /}" ]]; then
    echo "Scratch orgs still alive (delete with sf org delete scratch --target-org <alias> --no-prompt):$LIVE_ORGS" >&2
  fi
}

# ---------------------------------------------------------------- steps

step_package_types() {
  sfrun package list --target-dev-hub "$DEVHUB_SHOWN" || return 1
  [[ "$PLAN" == 1 ]] && { echo "      (each chosen package must be registered as $TYPE)"; return 0; }
  local wanted name problems=""
  wanted="$( [[ "$TYPE" == managed ]] && echo Managed || echo Unlocked )"
  for name in "${NAMES[@]}"; do
    python3 -c '
import json, sys
rows = json.load(open(sys.argv[1])).get("result") or []
match = [r for r in rows if r.get("Name") == sys.argv[2]]
sys.exit(0 if match and match[0].get("ContainerOptions") == sys.argv[3] else 1)
' "$LAST" "$name" "$wanted" || problems+="$name; "
  done
  [[ -z "$problems" ]] || { STEP_MSG="not registered as $wanted: $problems"; return 1; }
}

step_worktree() { # phase ref
  local dir="${WORK:-<work>}/src-$1"
  show git worktree add --detach "$dir" "$2"
  echo "      (each build-$1 step runs in $dir, so it packages that ref's source and sfdx-project.json)"
  [[ "$PLAN" == 1 ]] && return 0
  git -C "$REPO_ROOT" worktree add --detach "$dir" "$2" >>"$LOG" 2>&1 || return 1
  WORKTREES+=" $dir"
}

step_build() { # phase index
  local phase="$1" i="$2" dir="${WORK:-<work>}/src-$1"
  local status=0
  if [[ "$PLAN" == 1 ]]; then
    sfrun package version create --package "${NAMES[$i]}" --code-coverage --installation-key-bypass \
      --wait "$VERSION_WAIT" --target-dev-hub "$DEVHUB_SHOWN"
  else
    (cd "$dir" && sfrun package version create --package "${NAMES[$i]}" --code-coverage \
      --installation-key-bypass --wait "$VERSION_WAIT" --target-dev-hub "$DEVHUB_SHOWN") || status=$?
  fi
  [[ "$PLAN" == 1 ]] && return 0
  [[ "$status" == 0 ]] || { STEP_MSG="$(helper jget message <"$LAST" | head -c 300)"; return 1; }
  local id
  id="$(helper jget result.SubscriberPackageVersionId <"$LAST")"
  [[ "$id" == 04t* ]] || { STEP_MSG="no 04t id in the result"; return 1; }
  IDS+="$phase:${KEYS[$i]}=$id"$'\n'
  STEP_MSG="$id"
}

step_promote() { # index
  echo "      !! PROMOTION IS PERMANENT: a released version can never be deleted (owner approval)."
  sfrun package version promote --package "$(id_of n1 "${KEYS[$1]}")" --target-dev-hub "$DEVHUB_SHOWN" --no-prompt
}

step_create_org() { # alias definition
  show sf org create scratch --definition-file "$2" --alias "$1" --target-dev-hub "$DEVHUB_SHOWN" \
    --duration-days "$ORG_DAYS" --no-namespace --wait 30 --json
  [[ "$PLAN" == 1 ]] && return 0
  local out status=0 username
  # The JSON holds an access token: it stays in this variable and only the username leaves it.
  out="$(sf org create scratch --definition-file "$REPO_ROOT/$2" --alias "$1" --target-dev-hub "$DEVHUB" \
    --duration-days "$ORG_DAYS" --no-namespace --wait 30 --json 2>/dev/null)" || status=$?
  username="$(printf '%s' "$out" | helper jget result.username)"
  if [[ "$status" != 0 || -z "$username" ]]; then
    STEP_MSG="$(printf '%s' "$out" | helper jget message | head -c 300)"
    return 1
  fi
  LIVE_ORGS+=" $1"
  STEP_MSG="$username"
  ERRORS_SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

step_npsp() { # alias
  show scripts/org/install-npsp.sh "$1"
  [[ "$PLAN" == 1 ]] && return 0
  "$REPO_ROOT/scripts/org/install-npsp.sh" "$1" >>"$LOG" 2>&1 || { STEP_MSG="install-npsp.sh failed (no verified NPSP ids?)"; return 1; }
}

step_install() { # alias phase index
  sfrun package install --package "$(id_of "$2" "${KEYS[$3]}")" --target-org "$1" --wait "$INSTALL_WAIT" \
    --publish-wait "$PUBLISH_WAIT" --security-type AdminsOnly --no-prompt
}

render() { # template out [helper args]
  local template="$1" out="$2"
  shift 2
  echo "      (render scripts/org/package-upgrade-test/$template with namespace $NS_SHOWN${1:+ $*})"
  [[ "$PLAN" == 1 ]] && return 0
  helper render --project "$PROJECT" --root "$REPO_ROOT" "$TEMPLATES/$template" "$out" --ns "$NS" "$@"
}

apex() { # alias file: runs anonymous Apex as the org's admin; fails on compile or assertion
  local status=0
  sfrun apex run --file "$2" --target-org "$1" || status=$?
  [[ "$PLAN" == 1 ]] && return 0
  if [[ "$status" != 0 || "$(helper jget result.success <"$LAST")" != True ]]; then
    local detail
    detail="$( (helper jget result.compileProblem <"$LAST"; helper jget result.exceptionMessage <"$LAST") | tr '\n' ' ' | cut -c1-300)"
    if [[ -n "${detail// /}" ]]; then STEP_MSG="$detail"; fi
    STEP_MSG="${STEP_MSG:-anonymous Apex failed}"
    return 1
  fi
}

step_setup() { # alias index: unlocked only, the package's post-install as the admin
  local out="${WORK:-<work>}/apex/setup-${KEYS[$2]}.apex"
  render post-install.apex "$out" --set "CLASS=${HANDLERS[$2]}" || return 1
  apex "$1" "$out"
}

step_template() { # alias template [helper args]
  local alias="$1" template="$2" out
  shift 2
  out="${WORK:-<work>}/apex/${alias}-${template}"
  render "$template" "$out" "$@" || return 1
  apex "$alias" "$out"
}

# Unlocked only: no post-install script runs, so run each package's setup as the admin.
setup_all() { # shape alias phase
  local i
  if [[ "$TYPE" != unlocked ]]; then
    return 0
  fi
  for i in "${!KEYS[@]}"; do
    if [[ "${HANDLERS[$i]}" != - ]]; then
      run_step "$1" "setup-$3:${KEYS[$i]}" step_setup "$2" "$i"
    fi
  done
}

step_error_log() { # alias
  sfrun data query --target-org "$1" \
    --query "SELECT COUNT() FROM ${NS_SHOWN}__Error_Log__c WHERE CreatedDate >= ${ERRORS_SINCE:-<org created>}" || return 1
  [[ "$PLAN" == 1 ]] && return 0
  local rows
  rows="$(helper jget result.totalSize <"$LAST")"
  [[ "$rows" == 0 ]] && return 0
  sfrun data query --target-org "$1" --query "SELECT ${NS}__Context__c, ${NS}__Message__c FROM ${NS}__Error_Log__c WHERE CreatedDate >= ${ERRORS_SINCE} ORDER BY CreatedDate LIMIT 20" || true
  STEP_MSG="$rows Error Log row(s); the first 20 are in the log"
  return 1
}

step_seed() { # alias
  show scripts/org/seed-sample-data.sh "$1" --namespace "$NS_SHOWN"
  [[ "$PLAN" == 1 ]] && return 0
  "$REPO_ROOT/scripts/org/seed-sample-data.sh" "$1" --namespace "$NS" >>"$LOG" 2>&1
}

step_counts() { # alias file [select]
  local object count objects
  [[ "$PLAN" == 1 ]] || : >"$2"
  objects="$(helper objects --project "$PROJECT" --select "${3:-$PACKAGES}" --ns "$NS_SHOWN")" || return 1
  while read -r object; do
    [[ -n "$object" ]] || continue
    sfrun data query --target-org "$1" --query "SELECT COUNT() FROM $object" || return 1
    [[ "$PLAN" == 1 ]] && continue
    count="$(helper jget result.totalSize <"$LAST")"
    printf '%s\t%s\n' "$object" "$count" >>"$2"
  done <<<"$objects"
  [[ "$PLAN" == 1 ]] && return 0
  STEP_MSG="$(tr '\t\n' '= ' <"$2")"
}

step_compare() { # before after
  echo "      (compare the counts: every one unchanged)"
  [[ "$PLAN" == 1 ]] && return 0
  local changed
  changed="$(diff "$1" "$2" | grep '^[<>]' | tr '\t\n' '= ' || true)"
  [[ -z "$changed" ]] || { STEP_MSG="counts changed: $changed"; return 1; }
}

step_installed() { # alias phase [absent key]
  sfrun package installed list --target-org "$1" || return 1
  local args=() i
  for i in "${!KEYS[@]}"; do
    if [[ -n "${3:-}" && "${KEYS[$i]}" == "$3" ]]; then
      args+=(--absent "${NAMES[$i]}")
    else
      args+=(--expect "${NAMES[$i]}=$(id_of "$2" "${KEYS[$i]}")")
    fi
  done
  if [[ "$PLAN" == 1 ]]; then
    echo "      (expect: ${args[*]})"
    return 0
  fi
  STEP_MSG="$(helper installed "${args[@]}" <"$LAST" | tr '\n' ' ')" || return 1
}

step_uninstall() { # alias key
  sfrun package uninstall --package "$(id_of n "$2")" --target-org "$1" --wait "$INSTALL_WAIT"
}

step_delete_org() { # alias
  sfrun org delete scratch --target-org "$1" --no-prompt || return 1
  LIVE_ORGS="${LIVE_ORGS/ $1/}"
}

# ---------------------------------------------------------------- run

echo "Package install and upgrade test"
if [[ "$PLAN" == 1 ]]; then echo "PLAN ONLY: nothing below is run, created or written."; fi
echo "Namespace: $NS_SHOWN    Type: $TYPE    Dev Hub: $DEVHUB_SHOWN"
echo "Packages (dependency order): ${KEYS[*]}"
echo "N-1: $FROM ($FROM_KIND)    N: $TO ($TO_KIND)"
if [[ "$TYPE" == managed && "$FROM_KIND" == ref ]]; then
  if [[ "$PROMOTE" == 1 ]]; then
    echo "N-1 path: build from $FROM and PROMOTE (permanent; owner approval)"
  else
    echo "N-1 path: build from $FROM as a beta: REFUSED for managed (a beta cannot be upgraded); add --promote-from or use a 04t file of released versions"
  fi
elif [[ "$FROM_KIND" == list ]]; then
  echo "N-1 path: install the 04t ids in $FROM$( [[ "$TYPE" == managed ]] && echo " (managed: they must be released versions)")"
else
  echo "N-1 path: build from $FROM, unpromoted (unlocked)"
fi
for i in "${!SHAPE_LIST[@]}"; do
  echo "Shape ${SHAPE_LIST[$i]}: ${SHAPE_DEFS[$i]} (${SHAPE_EDITIONS[$i]})"
done
echo
echo "Readiness:"
READY=0
READINESS_ARGS=(readiness --project "$PROJECT" --root "$REPO_ROOT" --select "$PACKAGES" --type "$TYPE"
  --devhub "$DEVHUB" --from-kind "$FROM_KIND" --from-ref "$FROM" --to-kind "$TO_KIND" --to-ref "$TO"
  --shapes "$(IFS=,; echo "${SHAPE_LIST[*]}")" --uninstall "$UNINSTALL")
[[ "$PROMOTE" == 1 ]] && READINESS_ARGS+=(--promote)
helper "${READINESS_ARGS[@]}" | sed 's/^/  /' || READY=$?
echo
echo "!! Creating scratch orgs needs the owner's approval (project rules). This creates ${#SHAPE_LIST[@]} org(s)."
if [[ "$PLAN" == 0 ]]; then
  if [[ "$READY" != 0 ]]; then
    echo "Refusing to run: fix every MISSING line above first." >&2
    exit 2
  fi
  if [[ "$YES_ORGS" != 1 ]]; then
    echo "Refusing to run without --yes-create-orgs (record of the owner's approval)." >&2
    exit 2
  fi
  WORK="$(mktemp -d -t barn-upgrade-XXXXXX)"
  mkdir -p "$WORK/apex" "$REPORT/logs"
  STEPS="$REPORT/steps.tsv"
  : >"$STEPS"
  LAST="$WORK/last.json"
  trap cleanup EXIT
fi
echo

needs_build=0
[[ "$FROM_KIND" == ref || "$TO_KIND" == ref ]] && needs_build=1
echo "== Versions (built once, shared by every shape)"
if [[ "$needs_build" == 1 ]]; then
  run_step build package-types step_package_types
fi
for phase in n1 n; do
  ref="$FROM"; kind="$FROM_KIND"
  [[ "$phase" == n ]] && { ref="$TO"; kind="$TO_KIND"; }
  if [[ "$kind" == list ]]; then
    for i in "${!KEYS[@]}"; do echo "  [$phase:${KEYS[$i]}] $(id_of "$phase" "${KEYS[$i]}") from $ref"; done
    continue
  fi
  run_step build "worktree-$phase" step_worktree "$phase" "$ref"
  for i in "${!KEYS[@]}"; do
    run_step build "build-$phase:${KEYS[$i]}" step_build "$phase" "$i"
    if [[ "$phase" == n1 && "$TYPE" == managed && "$PROMOTE" == 1 ]]; then
      run_step build "promote-n1:${KEYS[$i]}" step_promote "$i"
    fi
  done
done
BUILD_FAILED="$SHAPE_FAILED"

for s in "${!SHAPE_LIST[@]}"; do
  shape="${SHAPE_LIST[$s]}"
  alias="barn-upg-$shape-$RUN_ID"
  ERRORS_SINCE=""
  SHAPE_FAILED="$BUILD_FAILED"
  echo
  echo "== Shape $shape (org alias $alias)"
  run_step "$shape" create-org step_create_org "$alias" "${SHAPE_DEFS[$s]}"
  if [[ "$shape" == npsp ]]; then run_step "$shape" install-npsp step_npsp "$alias"; fi
  for i in "${!KEYS[@]}"; do run_step "$shape" "install-n1:${KEYS[$i]}" step_install "$alias" n1 "$i"; done
  setup_all "$shape" "$alias" n1
  run_step "$shape" installed-n1 step_installed "$alias" n1
  run_step "$shape" health-n1 step_template "$alias" health-check.apex
  run_step "$shape" error-log-n1 step_error_log "$alias"
  run_step "$shape" seed step_seed "$alias"
  run_step "$shape" counts-before step_counts "$alias" "${WORK:-<work>}/$shape-before.tsv"
  for i in "${!KEYS[@]}"; do run_step "$shape" "upgrade:${KEYS[$i]}" step_install "$alias" n "$i"; done
  setup_all "$shape" "$alias" n
  run_step "$shape" installed-n step_installed "$alias" n
  run_step "$shape" health-n step_template "$alias" health-check.apex
  run_step "$shape" error-log-n step_error_log "$alias"
  run_step "$shape" counts-after step_counts "$alias" "${WORK:-<work>}/$shape-after.tsv"
  run_step "$shape" counts-unchanged step_compare "${WORK:-<work>}/$shape-before.tsv" "${WORK:-<work>}/$shape-after.tsv"
  for key in "${KEYS[@]}"; do
    if [[ -f "$TEMPLATES/smoke-$key.apex" ]]; then
      run_step "$shape" "smoke:$key" step_template "$alias" "smoke-$key.apex"
    fi
  done
  if [[ -n "$UNINSTALL" ]]; then
    run_step "$shape" "uninstall:$UNINSTALL" step_uninstall "$alias" "$UNINSTALL"
    run_step "$shape" uninstalled step_installed "$alias" n "$UNINSTALL"
    run_step "$shape" left-nothing step_template "$alias" uninstall-check.apex --module "$UNINSTALL"
    run_step "$shape" health-after-uninstall step_template "$alias" health-check.apex
    run_step "$shape" smoke-after-uninstall:core step_template "$alias" smoke-core.apex
  fi
  if [[ "$KEEP_ORGS" == 1 ]]; then
    echo "  [delete-org] kept (--keep-orgs): sf org delete scratch --target-org $alias --no-prompt"
  elif [[ "$PLAN" == 1 ]] || [[ " $LIVE_ORGS " == *" $alias "* ]]; then
    run_step "$shape" delete-org --always step_delete_org "$alias"
  fi
done

[[ "$PLAN" == 1 ]] && { echo; echo "Plan only: nothing was run."; exit 0; }

echo
RESULT="$(helper summary --steps "$STEPS" --out "$REPORT" --meta "namespace=$NS" --meta "type=$TYPE" \
  --meta "from=$FROM" --meta "to=$TO" --meta "packages=${KEYS[*]}" --meta "shapes=${SHAPE_LIST[*]}")"
echo "Result: $RESULT. Report: $REPORT/summary.md"
[[ "$RESULT" == PASS && "$FAILED" == 0 ]] || exit 1
