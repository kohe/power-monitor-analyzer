#!/bin/bash

#############################################
# Power Monitor Data Sender
# Sends power consumption data to Google Sheets via GAS Web App
#
# Usage:
#   send_power_data.sh              # Send last 7 days (default)
#   send_power_data.sh --all        # Send all available data
#   send_power_data.sh --start 2025-04-01 --end 2025-10-16  # Specify date range
#############################################

set -euo pipefail

# Configuration file path
CONFIG_FILE="${HOME}/.power-monitor-config"

# Power Monitor binary path
POWER_MONITOR="/Applications/Power Monitor.app/Contents/MacOS/Power Monitor"

# Log file path
LOG_FILE="${HOME}/Library/Logs/power-monitor-sender.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Function to log errors
error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Check if Power Monitor is installed
if [[ ! -x "${POWER_MONITOR}" ]]; then
    error "Power Monitor application not found at ${POWER_MONITOR}"
    exit 1
fi

# Load configuration
if [[ ! -f "${CONFIG_FILE}" ]]; then
    error "Configuration file not found: ${CONFIG_FILE}"
    error "Please create ${CONFIG_FILE} with the following content:"
    error "GAS_WEBAPP_URL=your_google_apps_script_webapp_url_here"
    error "DEVICE_NAME=\$(hostname -s)"
    error "COST_PER_KWH=30"
    exit 1
fi

# Source configuration
source "${CONFIG_FILE}"

# Validate configuration
if [[ -z "${GAS_WEBAPP_URL:-}" ]]; then
    error "GAS_WEBAPP_URL not set in ${CONFIG_FILE}"
    exit 1
fi

# Get device name (use hostname if not specified in config)
DEVICE_NAME="${DEVICE_NAME:-$(hostname -s)}"

# Get cost per kWh (use default 30 if not specified in config)
COST_PER_KWH="${COST_PER_KWH:-30}"

log "Starting power data collection for device: ${DEVICE_NAME}"
log "Cost per kWh: ${COST_PER_KWH} JPY"

# Parse command line arguments
MODE="weekly"  # default: weekly (past 7 days)
CUSTOM_START=""
CUSTOM_END=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            MODE="all"
            shift
            ;;
        --start)
            CUSTOM_START="$2"
            MODE="custom"
            shift 2
            ;;
        --end)
            CUSTOM_END="$2"
            MODE="custom"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            error "Usage: $0 [--all] [--start YYYY-MM-DD --end YYYY-MM-DD]"
            exit 1
            ;;
    esac
done

# Calculate date range based on mode
if [[ "${MODE}" == "all" ]]; then
    # Get all available data (no date filter)
    log "Collecting all available data"
    DATE_ARGS=""
elif [[ "${MODE}" == "custom" ]]; then
    if [[ -z "${CUSTOM_START}" ]] || [[ -z "${CUSTOM_END}" ]]; then
        error "Both --start and --end must be specified for custom date range"
        exit 1
    fi
    START_DATE="${CUSTOM_START}"
    END_DATE="${CUSTOM_END}"
    log "Collecting data from ${START_DATE} to ${END_DATE}"
    DATE_ARGS="--start ${START_DATE} --end ${END_DATE}"
else
    # Default: past 7 days
    END_DATE=$(date -v-1d '+%Y-%m-%d')
    START_DATE=$(date -v-7d '+%Y-%m-%d')
    log "Collecting data from ${START_DATE} to ${END_DATE} (past 7 days)"
    DATE_ARGS="--start ${START_DATE} --end ${END_DATE}"
fi

# Get power data
if [[ -z "${DATE_ARGS}" ]]; then
    # All data (no date filter)
    POWER_DATA=$("${POWER_MONITOR}" --noGUI --journal 2>&1)
else
    # Specific date range
    POWER_DATA=$("${POWER_MONITOR}" --noGUI --journal ${DATE_ARGS} 2>&1)
fi

if [[ $? -ne 0 ]]; then
    error "Failed to get power data from Power Monitor"
    error "Output: ${POWER_DATA}"
    exit 1
fi

log "Raw data received from Power Monitor"

# Parse JSON data - convert to entries array
ENTRIES=$(echo "${POWER_DATA}" | jq '[.[] | {
    date: .Date,
    consumption_total: ."Consumption Total (kWh)",
    consumption_power_nap: ."Consumption Power Nap (kWh)",
    duration_awake: ."Duration Awake",
    duration_power_nap: ."Duration Power Nap"
}]')

if [[ -z "${ENTRIES}" ]] || [[ "${ENTRIES}" == "null" ]] || [[ "${ENTRIES}" == "[]" ]]; then
    error "No valid power data found for the specified period"
    exit 1
fi

ENTRY_COUNT=$(echo "${ENTRIES}" | jq 'length')
log "Found ${ENTRY_COUNT} days of data"

# Build final JSON with batch format
FINAL_JSON=$(jq -n \
    --arg device "${DEVICE_NAME}" \
    --argjson cost "${COST_PER_KWH}" \
    --argjson entries "${ENTRIES}" \
    '{device_name: $device, cost_per_kwh: $cost, entries: $entries}')

log "Sending data to Google Sheets..."

# Send data to GAS Web App
HTTP_CODE=$(curl -s -L -w "%{http_code}" -o /tmp/gas_response.txt -X POST \
    -H "Content-Type: application/json" \
    -d "${FINAL_JSON}" \
    "${GAS_WEBAPP_URL}")

if [[ $? -eq 0 ]]; then
    RESPONSE=$(cat /tmp/gas_response.txt)
    
    # Check if response is JSON
    if echo "${RESPONSE}" | jq . > /dev/null 2>&1; then
        # JSON response - check success field
        SUCCESS=$(echo "${RESPONSE}" | jq -r '.success // false')
        if [[ "${SUCCESS}" == "true" ]]; then
            log "Data sent successfully!"
            log "Response: ${RESPONSE}"
        else
            error "Failed to send data. Response: ${RESPONSE}"
            exit 1
        fi
    else
        # Non-JSON response (HTML) - check HTTP status code
        # Google Apps Script sometimes returns HTML even on success due to redirects
        if [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
            log "Data sent successfully! (HTTP ${HTTP_CODE})"
            log "Note: Received non-JSON response, but HTTP status indicates success"
        elif [[ "${HTTP_CODE}" == "405" ]]; then
            # HTTP 405 is a known issue with GAS redirects, but data is usually written successfully
            log "Data sent (HTTP 405 - Method Not Allowed on redirect)"
            log "Note: This is a known GAS behavior. Please verify data in spreadsheet."
        else
            error "Failed to send data. HTTP ${HTTP_CODE}"
            error "Response: ${RESPONSE:0:500}"  # Show first 500 chars
            exit 1
        fi
    fi
    
    # Clean up temp file
    rm -f /tmp/gas_response.txt
else
    error "Failed to send HTTP request to ${GAS_WEBAPP_URL}"
    exit 1
fi

log "Power data collection completed successfully"

