#!/usr/bin/env bash
# check-apex-offline.sh
#
# Offline Apex compile check using apex-ls (nawforce/apex-dev-tools) CheckForIssues.
# Requires no Salesforce org or Dev Hub. Requires Java 21+ and Maven (both already
# present in the standard dev/CI environment) to resolve the tool from Maven Central
# on first run; results are cached under .tools/ so later runs are fast and, once
# cached, work fully offline.
#
# Exit codes: 0 = no errors found, non-zero = errors found or the tool could not run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$REPO_ROOT/.tools/apex-ls"
APEX_LS_VERSION="6.2.0"
SCALA_BINARY="2.13"
ARTIFACT="apex-ls_${SCALA_BINARY}"
CP_FILE="$TOOLS_DIR/classpath.txt"
POM_FILE="$TOOLS_DIR/pom.xml"

mkdir -p "$TOOLS_DIR"

if ! command -v java >/dev/null 2>&1; then
  echo "check-apex-offline: java is required but not found on PATH." >&2
  exit 1
fi

if [[ ! -s "$CP_FILE" ]]; then
  if ! command -v mvn >/dev/null 2>&1; then
    echo "check-apex-offline: maven is required (first run only, to fetch apex-ls" >&2
    echo "  from Maven Central) but 'mvn' was not found on PATH." >&2
    exit 1
  fi

  echo "check-apex-offline: resolving apex-ls ${APEX_LS_VERSION} from Maven Central (first run only)..."

  cat > "$POM_FILE" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>barncrm.tools</groupId>
  <artifactId>apex-ls-runner</artifactId>
  <version>1.0</version>
  <dependencies>
    <dependency>
      <groupId>io.github.apex-dev-tools</groupId>
      <artifactId>${ARTIFACT}</artifactId>
      <version>${APEX_LS_VERSION}</version>
    </dependency>
  </dependencies>
</project>
EOF

  if ! mvn -q -f "$POM_FILE" dependency:build-classpath -Dmdep.outputFile="$CP_FILE"; then
    echo "check-apex-offline: failed to resolve apex-ls from Maven Central." >&2
    rm -f "$CP_FILE"
    exit 1
  fi
fi

APEX_LS_JAR="$(find "$HOME/.m2/repository/io/github/apex-dev-tools/${ARTIFACT}/${APEX_LS_VERSION}" -maxdepth 1 -name "${ARTIFACT}-${APEX_LS_VERSION}.jar" | head -1)"
if [[ -z "$APEX_LS_JAR" ]]; then
  echo "check-apex-offline: could not locate the resolved apex-ls jar under ~/.m2." >&2
  exit 1
fi

CLASSPATH="${APEX_LS_JAR}:$(cat "$CP_FILE")"

# KNOWN APEX-LS STDLIB GAPS. apex-ls 6.2.0's standard library (API 67.0) lacks these three
# ConnectApi.NamedCredentials methods, which BarnCRM Connector calls (CN-01, ConnectorOrg and
# ConnectorConnectionsController). Each one compiled in an org: anonymous Apex on barn-sales
# (API 67 scratch org), verified 2026-11-20. Only a "No matching method found" error naming one
# of these methods on ConnectApi.NamedCredentials is ignored; every other error still fails.
# Remove a name once apex-ls knows it.
KNOWN_GAPS="No matching method found for '(deleteNamedCredential|deleteExternalCredential|updateNamedCredential)' on 'ConnectApi\.NamedCredentials'"

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT
set +e
java -cp "$CLASSPATH" io.github.apexdevtools.apexls.CheckForIssues \
  --workspace "$REPO_ROOT" --detail errors --format text > "$OUTPUT_FILE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" == "4" ]]; then
  # Print each remaining error under its file; a file whose only errors are known gaps is dropped.
  set +e
  REMAINING="$(awk -v gaps="$KNOWN_GAPS" '
    /^\// { file = $0; shown = 0; next }
    $0 ~ gaps { next }
    { if (!shown && file != "") { print file; shown = 1 } print; count++ }
    END { exit count > 0 ? 1 : 0 }
  ' "$OUTPUT_FILE")"
  LEFT=$?
  set -e
  if [[ "$LEFT" -eq 0 ]]; then
    echo "check-apex-offline: no compile-level errors found (known apex-ls stdlib gaps ignored)."
    exit 0
  fi
  echo "$REMAINING"
else
  cat "$OUTPUT_FILE"
fi

case "$STATUS" in
  0)
    echo "check-apex-offline: no compile-level errors found."
    exit 0
    ;;
  4)
    echo "check-apex-offline: FAILED, apex-ls reported compile-level errors above." >&2
    exit 1
    ;;
  *)
    echo "check-apex-offline: apex-ls exited with unexpected status $STATUS." >&2
    exit 1
    ;;
esac
