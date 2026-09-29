const API_KEY = "Albin KCC ride track";

const SHEETS = {
  riders_40: "Riders_Master_40",
  riders_100: "Riders_Master_100",
  scans: "Riders_Scan",
  volunteers: "Volunteers",
  checkpoints_master: "Checkpoints_Master"
};

// ENTRY POINT
function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return response({
        status: "error",
        message: "Invalid request"
      });
    }

    const data = JSON.parse(e.postData.contents);

    if (data.key !== API_KEY) {
      return response({
        status: "error",
        message: "Unauthorized"
      });
    }

    switch (data.action) {
      case "loginVolunteer":
        return loginVolunteer(data);

      case "getCheckpoints":
        return getCheckpoints(data);

      case "scanCheckpoint":
        return scanCheckpoint(data);

      case "checkScanStatus":
        return checkScanStatus(data);

      case "verifyRider":
        return verifyRider(data);

      default:
        return response({
          status: "error",
          message: "Invalid action"
        });
    }

  } catch (error) {
    return response({
      status: "error",
      message: error.message || error.toString()
    });
  }
}

//
// 🔐 LOGIN VOLUNTEER
//
function loginVolunteer(data) {
  const { phone, pin } = data;

  const sheet = getSheet(SHEETS.volunteers);
  const rows = sheet.getDataRange().getValues();
  const headers = rows[0];

  const phoneIndex = headers.indexOf("phone");
  const pinIndex = headers.indexOf("pin");
  const activeIndex = headers.indexOf("is_active");
  const nameIndex = headers.indexOf("name");
  const roleIndex = headers.indexOf("role");
  const loginIndex = headers.indexOf("last_login");

  for (let i = 1; i < rows.length; i++) {
    const sheetPhone = rows[i][phoneIndex].toString().trim();

    if (sheetPhone === phone.toString().trim()) {

      // ❌ Inactive
      if (rows[i][activeIndex].toString().toUpperCase() !== "TRUE") {
        return response({ status: "error", message: "User inactive" });
      }

      // ❌ Wrong PIN
      if (rows[i][pinIndex].toString() !== pin.toString()) {
        return response({ status: "error", message: "Invalid PIN" });
      }

      // ✅ Update last login
      sheet.getRange(i + 1, loginIndex + 1).setValue(new Date());

      // ✅ Return full volunteer details
      return response({
        status: "success",
        message: "Login successful",
        volunteer: {
          name: rows[i][nameIndex],
          phone: sheetPhone,
          role: rows[i][roleIndex]
        }
      });
    }
  }

  return response({ status: "error", message: "User not found" });
}

//
// 📥 GET CHECKPOINTS (FOR POPUP)
//
function getCheckpoints(data) {
  const sheet = getSheet(SHEETS.checkpoints_master);
  const rows = sheet.getDataRange().getValues();
  const headers = rows[0];

  const idIndex = headers.indexOf("checkpoint_id");
  const nameIndex = headers.indexOf("checkpoint_name");
  const categoryIndex = headers.indexOf("category");
  const activeIndex = headers.indexOf("is_active");

  const list = [];

  for (let i = 1; i < rows.length; i++) {
    if (rows[i][activeIndex].toString().toUpperCase() === "TRUE") {
      list.push({
        checkpoint_id: rows[i][idIndex],
        checkpoint_name: rows[i][nameIndex],
        category: normalizeCheckpointCategory(rows[i][categoryIndex]),
        is_active: true
      });
    }
  }

  return response({
    status: "success",
    checkpoints: list
  });
}

//
// 🚴 SCAN CHECKPOINT (CATEGORY + CHECKPOINT SAFE)
//
function scanCheckpoint(data) {
  const { rider_id, category, checkpoint, scanned_by } = data;

  // 🔍 Validate rider
  const rider = getRider(rider_id);

  if (!rider) {
    return response({ status: "error", message: "Rider not found" });
  }

  // 🔍 Validate category
  if (rider.category != category) {
    return response({
      status: "error",
      message: "Category mismatch"
    });
  }

  // 🔍 Validate checkpoint
  if (!isValidCheckpoint(category, checkpoint)) {
    return response({
      status: "error",
      message: "Invalid checkpoint"
    });
  }

  if (!scanned_by) {
    return response({
      status: "error",
      message: "Scanner required"
    });
  }

  // 🔍 Get volunteer name
  const volunteerName = getVolunteerName(scanned_by);

  if (!volunteerName) {
    return response({
      status: "error",
      message: "Invalid volunteer"
    });
  }

  // Serialize scan-history reads and writes across requests to this script.
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) {
    return response({
      status: "error",
      message: "Check-in is busy. Please try again."
    });
  }

  try {
    const sheet = getSheet(SHEETS.scans);
    const rows = sheet.getDataRange().getValues();
    const headers = rows[0];

    const riderIndex = headers.indexOf("rider_id");
    const checkpointIndex = headers.indexOf("checkpoint");
    const categoryIndex = headers.indexOf("category");

    // 🚫 Prevent duplicate
    for (let i = 1; i < rows.length; i++) {
      if (
        rows[i][riderIndex] == rider_id &&
        rows[i][checkpointIndex] == checkpoint &&
        rows[i][categoryIndex] == category
      ) {
        return response({
          status: "duplicate",
          message: "Already scanned"
        });
      }
    }

    // ✅ Insert with volunteer_name
    sheet.appendRow([
      new Date().getTime(),
      rider_id,
      rider.name,
      category,
      checkpoint,
      volunteerName, // ✅ NOW NAME
      new Date()
    ]);

    SpreadsheetApp.flush();

    return response({
      status: "success",
      message: "Scan successful",
      data: {
        rider_name: rider.name,
        category: rider.category,
        scanned_by: volunteerName
      }
    });
  } finally {
    lock.releaseLock();
  }
}

// Read-only lookup of the same key used by duplicate detection.
// A missing row is only a snapshot: a timed-out scan may still be running.
function checkScanStatus(data) {
  const { rider_id, category, checkpoint } = data;
  if (rider_id == null || String(rider_id).trim() === "" ||
      !["40", "100"].includes(String(category)) ||
      checkpoint == null || String(checkpoint).trim() === "") {
    return response({ status: "error", message: "Invalid status request" });
  }
  const rows = getSheet(SHEETS.scans).getDataRange().getValues();
  const headers = rows[0];
  const riderIndex = headers.indexOf("rider_id");
  const checkpointIndex = headers.indexOf("checkpoint");
  const categoryIndex = headers.indexOf("category");
  if ([riderIndex, checkpointIndex, categoryIndex].includes(-1)) {
    throw new Error("Scan sheet headers are missing");
  }
  const recorded = rows.slice(1).some(row =>
    row[riderIndex] == rider_id && row[checkpointIndex] == checkpoint &&
    row[categoryIndex] == category);
  return response({ status: "success", recorded: recorded });
}

function getVolunteerName(phone) {
  const sheet = getSheet(SHEETS.volunteers);
  const data = sheet.getDataRange().getValues();

  const headers = data[0];
  const phoneIndex = headers.indexOf("phone");
  const nameIndex = headers.indexOf("name");

  for (let i = 1; i < data.length; i++) {
    const sheetPhone = data[i][phoneIndex].toString().trim();

    if (sheetPhone === phone.toString().trim()) {
      return data[i][nameIndex];
    }
  }

  return null;
}

function verifyRider(data) {
  const { rider_id } = data;

  if (!rider_id || rider_id.toString().trim() === "") {
    return response({
      status: "error",
      message: "Rider ID required"
    });
  }

  const rider = getRider(rider_id.toString().trim());

  if (!rider) {
    return response({
      status: "error",
      message: "Rider not found"
    });
  }

  return response({
    status: "success",
    message: "Rider verified",
    data: {
      rider_id: rider_id.toString().trim(),
      rider_name: rider.name,
      category: rider.category
    }
  });
}

//
// 🔍 GET RIDER (now split across two category-specific tabs)
//
function getRider(rider_id) {
  const tabs = [
    { name: SHEETS.riders_40, category: "40" },
    { name: SHEETS.riders_100, category: "100" }
  ];

  for (const tab of tabs) {
    const sheet = getSheet(tab.name);
    const data = sheet.getDataRange().getValues();
    const headers = data[0];

    const riderIndex = headers.indexOf("rider_id");
    const nameIndex = headers.indexOf("name");

    for (let i = 1; i < data.length; i++) {
      if (data[i][riderIndex] == rider_id) {
        return {
          name: data[i][nameIndex],
          category: tab.category
        };
      }
    }
  }

  return null;
}

//
// 🔍 VALIDATE CHECKPOINT (NAME + RIDER CATEGORY OR COMMON CATEGORY)
//
function normalizeCheckpointCategory(value) {
  return String(value == null ? "" : value).trim();
}

function isValidCheckpoint(category, checkpoint) {
  const riderCategory = String(category).trim();
  if (riderCategory !== "40" && riderCategory !== "100") return false;
  const checkpointName = String(checkpoint).trim();
  const sheet = getSheet(SHEETS.checkpoints_master);
  const data = sheet.getDataRange().getValues();

  const headers = data[0];
  const nameIndex = headers.indexOf("checkpoint_name");
  const categoryIndex = headers.indexOf("category");
  const activeIndex = headers.indexOf("is_active");

  for (let i = 1; i < data.length; i++) {
    if (
      String(data[i][nameIndex]).trim() === checkpointName &&
      (normalizeCheckpointCategory(data[i][categoryIndex]) === riderCategory ||
        normalizeCheckpointCategory(data[i][categoryIndex]) === "40&100") &&
      String(data[i][activeIndex]).trim().toUpperCase() === "TRUE"
    ) {
      return true;
    }
  }

  return false;
}

//
// 🔧 HELPERS
//
function getSheet(name) {
  return SpreadsheetApp.getActiveSpreadsheet().getSheetByName(name);
}

function response(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}
