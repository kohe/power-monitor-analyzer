# Power Monitor Analyzer

A simple tool to automatically log power consumption data from [Power Monitor for macOS](https://github.com/SAP/power-monitoring-tool-for-macos) to Google Sheets.

## Features

- 📊 **Automatic Weekly Logging**: Automatically sends past 7 days of power consumption data to Google Sheets every Monday
- 📅 **Daily Granularity**: Records daily power consumption data for detailed analysis
- 🚀 **Batch Mode**: Efficiently sends multiple days of data in a single API call
- 🖥️ **Multi-Device Support**: Each device gets its own sheet in the spreadsheet
- 💰 **Cost Calculation**: Automatically calculates electricity cost (configurable ¥/kWh rate per device)
- 🔒 **Simple & Secure**: Uses Google Apps Script as a webhook endpoint
- 🎯 **Minimal Setup**: Just configure once and forget
- 🔄 **Flexible Modes**: Weekly auto-run, manual all-history import, or custom date range

## Overview

This tool consists of three components:

1. **Google Apps Script Web App**: Receives data (single or batch) and writes to Google Sheets
2. **Shell Script**: Extracts daily data from Power Monitor and sends to Google Sheets
3. **launchd Configuration**: Schedules weekly execution on macOS (every Monday at 9:00 AM)

## Quick Start

### Prerequisites

- macOS with [Power Monitor](https://github.com/SAP/power-monitoring-tool-for-macos) installed
- Google account
- `jq` installed (`brew install jq`)

### 1. Set Up Google Sheets

1. Create a new Google Spreadsheet
2. Open Apps Script (Extensions → Apps Script)
3. Copy the content of `gas/Code.gs` into the script editor
4. Save the project
5. Deploy as Web App:
   - Click "Deploy" → "New deployment"
   - Type: Web app
   - Execute as: Me
   - Who has access: Anyone
   - Copy the Web App URL

### 2. Configure macOS

1. Clone this repository or download the scripts
2. Create configuration file:

```bash
cat > ~/.power-monitor-config << 'EOF'
GAS_WEBAPP_URL="your_google_apps_script_webapp_url_here"
DEVICE_NAME=$(hostname -s)
COST_PER_KWH=30
EOF
```

3. Test the script manually:

```bash
# Test with past 7 days (default)
./scripts/send_power_data.sh

# Import all historical data (first time setup)
./scripts/send_power_data.sh --all
```

## Usage

### Manual Execution

```bash
# Default: Send past 7 days
./scripts/send_power_data.sh

# Send all available data (for initial setup)
./scripts/send_power_data.sh --all

# Send specific date range
./scripts/send_power_data.sh --start 2025-09-01 --end 2025-09-30
```

### 3. Set Up Weekly Automation

1. Edit `launchd/com.powermonitor.weekly.plist` and update the script path
2. Copy to LaunchAgents directory:

```bash
cp launchd/com.powermonitor.weekly.plist ~/Library/LaunchAgents/
```

3. Load the launch agent:

```bash
launchctl load ~/Library/LaunchAgents/com.powermonitor.weekly.plist
```

This will run every Monday at 9:00 AM and send the past 7 days of data.

## Data Format

Each day, the following data is logged:

| Column | Description |
|--------|-------------|
| Date | Date (YYYY-MM-DD) |
| Consumption Total (kWh) | Total power consumption |
| Consumption Power Nap (kWh) | Power consumed during Power Nap |
| Duration Awake | Time spent awake (HH:MM:SS) |
| Duration Power Nap | Time spent in Power Nap (HH:MM:SS) |
| Rate (JPY/kWh) | Electricity rate used for calculation |
| Cost (JPY) | Calculated electricity cost |
| Logged At | Timestamp when data was received |

## Configuration

### Customize Cost Per kWh

Edit the `COST_PER_KWH` value in your `~/.power-monitor-config` file:

```bash
COST_PER_KWH=35  # Change to your electricity rate
```

This allows each device to have its own electricity rate, useful if you're tracking devices in different locations.

### Change Execution Schedule

Edit `launchd/com.powermonitor.weekly.plist` to change when the script runs:

```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Weekday</key>
    <integer>1</integer>  <!-- 0=Sunday, 1=Monday, ..., 6=Saturday -->
    <key>Hour</key>
    <integer>9</integer>  <!-- Hour (24h format) -->
    <key>Minute</key>
    <integer>0</integer>  <!-- Minute -->
</dict>
```

To run daily instead of weekly, remove the `Weekday` key (keep only `Hour` and `Minute`).

## Troubleshooting

Check the logs:

```bash
# Script logs
tail -f ~/Library/Logs/power-monitor-sender.log

# launchd logs
tail -f /tmp/powermonitor.stdout.log
tail -f /tmp/powermonitor.stderr.log
```

For more detailed setup instructions, see [SETUP.md](docs/SETUP.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Power Monitor for macOS](https://github.com/SAP/power-monitoring-tool-for-macos) by SAP
- Inspired by the need to track and visualize Mac power consumption over time

## Related Projects

- [Power Monitor for macOS](https://github.com/SAP/power-monitoring-tool-for-macos) - The tool this project integrates with

