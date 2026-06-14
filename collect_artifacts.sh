#!/usr/bin/env bash
set -euo pipefail

PROG_NAME=$(basename "$0")
ARTIFACT_DIR="./artifacts"
ORACLE_SID=""
LISTENER_NAME="LISTENER"

usage() {
  cat <<EOF
Usage: $PROG_NAME -s ORACLE_SID [-l LISTENER_NAME] [-d ARTIFACT_DIR]

Collect OS-level and Oracle database artifacts for troubleshooting.

Options:
  -s ORACLE_SID     Oracle SID to collect database artifacts for.
  -l LISTENER_NAME  Oracle listener name (default: LISTENER).
  -d ARTIFACT_DIR   Directory to write artifact files (default: ./artifacts).
  -h                Show this help message.
EOF
  exit 1
}

while getopts ":s:l:d:h" opt; do
  case "$opt" in
    s) ORACLE_SID="$OPTARG" ;;
    l) LISTENER_NAME="$OPTARG" ;;
    d) ARTIFACT_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ -z "$ORACLE_SID" ]]; then
  echo "ERROR: ORACLE_SID is required." >&2
  usage
fi

mkdir -p "$ARTIFACT_DIR"
ARTIFACT_DIR=$(realpath "$ARTIFACT_DIR")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$ARTIFACT_DIR/artifacts_${ORACLE_SID}_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

echo "Collecting artifacts into: $OUTPUT_DIR"

touch "$OUTPUT_DIR/collection.log"

echo "Start: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$OUTPUT_DIR/collection.log"

capture() {
  local filename="$1"
  shift
  local desc="$1"
  shift
  local outfile="$OUTPUT_DIR/$filename"
  {
    echo "--- $desc ---"
    "$@"
  } > "$outfile" 2>&1 || true
}

capture os_hostname "Hostname" hostname
capture os_date "Date" date
capture os_uname "Kernel and architecture" uname -a
capture os_uptime "Uptime" uptime
capture os_release "OS release" cat /etc/os-release || true
capture os_memory "Memory info" free -m
capture os_disk "Disk usage" df -h
capture os_mounts "Mount points" mount
capture os_network "Network interfaces" ip addr
capture os_routes "IP routing table" ip route
capture os_listening "Listening ports" ss -tulpn || netstat -tulpn
capture os_processes "Top processes" ps -ef | head -50
capture os_environment "Environment variables" env
capture os_oratab "Contents of /etc/oratab" grep -v '^#' /etc/oratab || true

# Oracle environment
ORACLE_HOME=""
if [[ -f /etc/oratab ]]; then
  ORACLE_HOME=$(grep "^${ORACLE_SID}:" /etc/oratab | cut -d: -f2 | tr -d '\r')
fi
if [[ -z "$ORACLE_HOME" ]]; then
  echo "WARNING: ORACLE_HOME not found for SID $ORACLE_SID in /etc/oratab." >> "$OUTPUT_DIR/collection.log"
else
  export ORACLE_HOME
  export ORACLE_SID
  export PATH="$ORACLE_HOME/bin:$PATH"
  capture os_oracle_home "ORACLE_HOME" echo "$ORACLE_HOME"

  if command -v sqlplus >/dev/null 2>&1; then
    capture db_instance "Oracle instance summary" sqlplus -s / as sysdba <<'SQL'
SET PAGESIZE 100 FEEDBACK OFF VERIFY OFF HEADING ON ECHO OFF
SELECT instance_name, status, version, database_role, log_mode FROM v$instance;
SELECT name, open_mode, log_mode FROM v$database;
SELECT tablespace_name, status, contents, block_size FROM dba_tablespaces;
SELECT COUNT(*) AS sessions FROM v$session;
EXIT
SQL

    capture db_alert_log "Last 200 lines of alert log" bash -lc 'if [[ -f "$ORACLE_HOME/diag/rdbms" ]]; then find "$ORACLE_HOME/diag/rdbms" -name "alert*.log" | tail -1 | xargs tail -n 200; fi'
  else
    echo "WARNING: sqlplus not found in PATH." >> "$OUTPUT_DIR/collection.log"
  fi

  capture listener_status "Listener status" lsnrctl status "$LISTENER_NAME" || true
  capture listener_processes "Listener processes" ps -ef | grep -i "${LISTENER_NAME}" | grep -v grep || true
fi

echo "End: $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$OUTPUT_DIR/collection.log"

cd "$ARTIFACT_DIR"
tar -czf "artifact_bundle_${ORACLE_SID}_${TIMESTAMP}.tar.gz" "$(basename "$OUTPUT_DIR")"

echo "Artifact bundle created: $ARTIFACT_DIR/artifact_bundle_${ORACLE_SID}_${TIMESTAMP}.tar.gz"
