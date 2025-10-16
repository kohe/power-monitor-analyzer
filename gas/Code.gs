/**
 * Power Monitor Data Logger
 * Receives power consumption data from macOS Power Monitor and logs it to Google Sheets
 * 
 * Each device gets its own sheet, and data is appended chronologically
 */

// Configuration
const DEFAULT_COST_PER_KWH = 30; // JPY per kWh (default if not provided)

/**
 * Handle POST requests from Power Monitor devices
 */
function doPost(e) {
  try {
    // Parse incoming JSON data
    const data = JSON.parse(e.postData.contents);
    
    // Check if it's a single data entry or an array (batch)
    const isBatch = Array.isArray(data.entries);
    const deviceName = data.device_name;
    const costPerKwh = data.cost_per_kwh || DEFAULT_COST_PER_KWH;
    
    // Validate required fields
    if (!deviceName) {
      return ContentService.createTextOutput(JSON.stringify({
        success: false,
        error: 'Missing required field: device_name'
      })).setMimeType(ContentService.MimeType.JSON);
    }
    
    // Get or create the spreadsheet
    const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = getOrCreateSheet(spreadsheet, deviceName);
    
    let rowsAdded = 0;
    
    if (isBatch) {
      // Batch mode: process multiple entries
      const entries = data.entries;
      
      if (!entries || entries.length === 0) {
        return ContentService.createTextOutput(JSON.stringify({
          success: false,
          error: 'No entries provided in batch'
        })).setMimeType(ContentService.MimeType.JSON);
      }
      
      // Process each entry and update or append
      entries.forEach(entry => {
        const cost = entry.consumption_total * costPerKwh;
        const newRow = [
          entry.date,
          entry.consumption_total,
          entry.consumption_power_nap || 0,
          entry.duration_awake || '',
          entry.duration_power_nap || '',
          costPerKwh,
          cost.toFixed(2),
          new Date() // Timestamp when data was received
        ];
        
        // Check if date already exists
        const existingRow = findRowByDate(sheet, entry.date);
        
        if (existingRow > 0) {
          // Update existing row
          sheet.getRange(existingRow, 1, 1, 8).setValues([newRow]);
        } else {
          // Append new row
          sheet.appendRow(newRow);
          rowsAdded++;
        }
      });
      
    } else {
      // Single entry mode (backward compatibility)
      if (!data.date || data.consumption_total === undefined) {
        return ContentService.createTextOutput(JSON.stringify({
          success: false,
          error: 'Missing required fields: date, consumption_total'
        })).setMimeType(ContentService.MimeType.JSON);
      }
      
      const cost = data.consumption_total * costPerKwh;
      const newRow = [
        data.date,
        data.consumption_total,
        data.consumption_power_nap || 0,
        data.duration_awake || '',
        data.duration_power_nap || '',
        costPerKwh,
        cost.toFixed(2),
        new Date()
      ];
      
      // Check if date already exists
      const existingRow = findRowByDate(sheet, data.date);
      
      if (existingRow > 0) {
        // Update existing row
        sheet.getRange(existingRow, 1, 1, 8).setValues([newRow]);
      } else {
        // Append new row
        sheet.appendRow(newRow);
        rowsAdded = 1;
      }
    }
    
    return ContentService.createTextOutput(JSON.stringify({
      success: true,
      message: isBatch ? `Batch data logged successfully (${rowsAdded} entries)` : 'Data logged successfully',
      device: deviceName,
      sheet: sheet.getName(),
      rows_added: rowsAdded
    })).setMimeType(ContentService.MimeType.JSON);
    
  } catch (error) {
    Logger.log('Error: ' + error.toString());
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

/**
 * Get existing sheet or create new one for a device
 */
function getOrCreateSheet(spreadsheet, deviceName) {
  let sheet = spreadsheet.getSheetByName(deviceName);
  
  if (!sheet) {
    // Create new sheet
    sheet = spreadsheet.insertSheet(deviceName);
    
    // Set up header row
    const headers = [
      'Date',
      'Consumption Total (kWh)',
      'Consumption Power Nap (kWh)',
      'Duration Awake',
      'Duration Power Nap',
      'Rate (JPY/kWh)',
      'Cost (JPY)',
      'Logged At'
    ];
    
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    
    // Format header row
    const headerRange = sheet.getRange(1, 1, 1, headers.length);
    headerRange.setFontWeight('bold');
    headerRange.setBackground('#4285f4');
    headerRange.setFontColor('#ffffff');
    
    // Auto-resize columns
    for (let i = 1; i <= headers.length; i++) {
      sheet.autoResizeColumn(i);
    }
    
    // Freeze header row
    sheet.setFrozenRows(1);
  }
  
  return sheet;
}

/**
 * Find row by date in the sheet
 * Returns row number if found, 0 if not found
 */
function findRowByDate(sheet, targetDate) {
  const dataRange = sheet.getDataRange();
  const values = dataRange.getValues();
  
  // Skip header row (index 0), start from row 1
  for (let i = 1; i < values.length; i++) {
    const rowDate = values[i][0]; // Date is in column A (index 0)
    
    // Convert to string for comparison (handles both string and Date objects)
    const rowDateStr = rowDate instanceof Date ? 
      Utilities.formatDate(rowDate, Session.getScriptTimeZone(), 'yyyy-MM-dd') : 
      String(rowDate);
    
    if (rowDateStr === targetDate) {
      return i + 1; // Return 1-based row number
    }
  }
  
  return 0; // Not found
}

/**
 * Test function to verify setup (single entry)
 */
function testPostSingle() {
  const testData = {
    device_name: 'test-device',
    date: '2025-10-01',
    consumption_total: 1.5,
    consumption_power_nap: 0.3,
    duration_awake: '100:30:15',
    duration_power_nap: '20:15:00',
    cost_per_kwh: 30
  };
  
  const e = {
    postData: {
      contents: JSON.stringify(testData)
    }
  };
  
  const result = doPost(e);
  Logger.log(result.getContent());
}

/**
 * Test function to verify batch mode
 */
function testPostBatch() {
  const testData = {
    device_name: 'test-device-batch',
    cost_per_kwh: 30,
    entries: [
      {
        date: '2025-10-01',
        consumption_total: 1.5,
        consumption_power_nap: 0.3,
        duration_awake: '100:30:15',
        duration_power_nap: '20:15:00'
      },
      {
        date: '2025-10-02',
        consumption_total: 1.3,
        consumption_power_nap: 0.25,
        duration_awake: '95:20:10',
        duration_power_nap: '18:30:00'
      },
      {
        date: '2025-10-03',
        consumption_total: 1.7,
        consumption_power_nap: 0.4,
        duration_awake: '110:45:30',
        duration_power_nap: '22:15:00'
      }
    ]
  };
  
  const e = {
    postData: {
      contents: JSON.stringify(testData)
    }
  };
  
  const result = doPost(e);
  Logger.log(result.getContent());
}

