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

      case "getRiders":
        return getRiders();

      case "getCheckpoints":
        return getCheckpoints(data);

      case "syncScans":
        return syncScans(data);

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
  const rows = checkpointRows(true);
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
function prepareScan(data) {
  const { rider_id, category, checkpoint, scanned_by } = data;

  // 🔍 Validate rider
  const rider = getRider(rider_id);

  if (!rider) {
    return ({ status: "error", message: "Rider not found" });
  }

  // 🔍 Validate category
  if (rider.category != category) {
    return ({
      status: "error",
      message: "Category mismatch"
    });
  }

  // 🔍 Validate checkpoint
  if (!isValidCheckpoint(category, checkpoint)) {
    return ({
      status: "error",
      message: "Invalid checkpoint"
    });
  }

  if (!scanned_by) {
    return ({
      status: "error",
      message: "Scanner required"
    });
  }

  // 🔍 Get volunteer name
  const volunteerName = getVolunteerName(scanned_by);

  if (!volunteerName) {
    return ({
      status: "error",
      message: "Invalid volunteer"
    });
  }

  return {row: [new Date().getTime(), rider_id, rider.name, category, checkpoint, volunteerName, new Date(), data.entry_id || "", data.scanned_at || ""],
    data: {rider_name: rider.name, category: rider.category, scanned_by: volunteerName}};
}

function scanCheckpoint(data) {
  const entryError = validateEntry(data, false);
  if (entryError) return response({status: "error", message: entryError});
  const prepared = prepareScan(data);
  if (!prepared.row) return response(prepared);
  // Check the ID and append under the same lock used by syncScans.
  // Different entry IDs (and legacy requests without IDs) remain separate scans.
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) {
    return response({
      status: "error",
      message: "Check-in is busy. Please try again."
    });
  }

  try {
    const sheet = getSheet(SHEETS.scans);
    if (data.entry_id) {
      ensureEntryColumns(sheet);
      if (existingEntryIds(sheet).has(data.entry_id)) {
        return response({
          status: "success",
          message: "Scan already saved",
          entry_id: data.entry_id,
          data: prepared.data
        });
      }
    }
    sheet.appendRow(prepared.row);

    SpreadsheetApp.flush();

    return response({
      status: "success",
      message: "Scan successful",
      entry_id: data.entry_id || null,
      data: prepared.data
    });
  } finally {
    lock.releaseLock();
  }
}

// Legacy read-only status endpoint for older app versions.
// New clients do not query scan history after uncertain submissions.
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
  const volunteers = masterData("volunteers", () => {
    const rows = getSheet(SHEETS.volunteers).getDataRange().getValues();
    const phoneIndex = rows[0].indexOf("phone");
    const nameIndex = rows[0].indexOf("name");
    if (phoneIndex < 0 || nameIndex < 0) throw new Error("Missing volunteer headers");
    // Do not cache PINs or authentication decisions. Login always reads live data.
    return rows.slice(1).map(row => [String(row[phoneIndex]).trim(), row[nameIndex]]);
  });
  const volunteer = volunteers.find(row => row[0] === String(phone).trim());
  return volunteer ? volunteer[1] : null;
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
  const groups = masterData("riders", loadRiders);
  for (const category of ["40", "100"]) {
    const rider = groups[category].find(r => r.rider_id === String(rider_id).trim());
    if (rider) return {name: rider.rider_name, category: rider.category};
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
  const data = checkpointRows();

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

// Return both complete master sheets together. Any error fails the whole download.
function getRiders() {
  // Explicit downloads always read the sheets and replace the shared cache.
  return response({status: "success", riders: masterData("riders", loadRiders, true)});
}

function loadRiders() {
  const riders = {};
  const seen = new Set();
  for (const [category, sheetName] of [["40", SHEETS.riders_40], ["100", SHEETS.riders_100]]) {
    const rows = getSheet(sheetName).getDataRange().getValues();
    const headers = rows[0] || [];
    const idIndex = headers.indexOf("rider_id");
    const nameIndex = headers.indexOf("name");
    if (idIndex < 0) throw new Error("Missing rider_id header in " + sheetName);
    riders[category] = [];
    for (const row of rows.slice(1)) {
      if (row.every(value => String(value).trim() === "")) continue;
      const id = String(row[idIndex] == null ? "" : row[idIndex]).trim();
      if (!id) continue;
      const name = String(row[nameIndex] == null ? "" : row[nameIndex]).trim() || "NA";
      if (seen.has(id)) throw new Error("Duplicate rider ID: " + id);
      seen.add(id);
      riders[category].push({rider_id: id, rider_name: name, category: category});
    }
  }
  return riders;
}

// Cache is only an optimization. Entries may disappear before their TTL.
// Serialize fills/refreshes so an older in-flight read cannot overwrite refresh.
function masterData(name, load, refresh = false) {
  const key = "master-v1:" + name;
  let cache;
  try { cache = CacheService.getScriptCache(); } catch (_) {}
  function read() {
    try {
      const value = cache && cache.get(key);
      return value ? JSON.parse(value) : null;
    } catch (_) { return null; }
  }
  if (!refresh) {
    const hit = read();
    if (hit !== null) return hit;
  }
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    if (!refresh) {
      const hit = read();
      if (hit !== null) return hit;
    }
    const value = load();
    try {
      // Remove the previous snapshot even if the new one is too large to cache.
      cache.remove(key);
      const encoded = JSON.stringify(value);
      // Conservative bound: UTF-8 uses at most 3 bytes per UTF-16 code unit.
      // Stay below CacheService's 100 KB per-entry limit, including Unicode.
      if (encoded.length <= 30000) cache.put(key, encoded, 300);
    } catch (_) { /* Cache outages must not prevent sheet-backed operations. */ }
    return value;
  } finally {
    lock.releaseLock();
  }
}

function checkpointRows(refresh = false) {
  return masterData("checkpoints", () => {
    const rows = getSheet(SHEETS.checkpoints_master).getDataRange().getValues();
    if (["checkpoint_id", "checkpoint_name", "category", "is_active"].some(h => !rows[0].includes(h))) {
      throw new Error("Missing checkpoint headers");
    }
    return rows;
  }, refresh);
}

// Add these columns after the existing seven scan columns; never shift old data.
function ensureEntryColumns(sheet) {
  const range = sheet.getRange(1, 8, 1, 2);
  const headers = range.getValues()[0];
  if ((headers[0] && headers[0] !== "entry_id") || (headers[1] && headers[1] !== "scanned_at")) {
    throw new Error("Columns H/I must be entry_id/scanned_at. See deployment notes.");
  }
  if (!headers[0] || !headers[1]) range.setValues([["entry_id", "scanned_at"]]);
}

function validateEntry(entry, required) {
  if (!entry || typeof entry !== "object") return "Invalid entry";
  if (!required && !entry.entry_id) return null; // Older clients remain supported.
  if (!/^[a-f0-9]{32}$/.test(entry.entry_id || "")) return "Invalid entry ID";
  if (typeof entry.scanned_at !== "string" || !Number.isFinite(Date.parse(entry.scanned_at))) return "Invalid scan time";
  if (!["rider_id", "category", "checkpoint", "scanned_by"].every(k => entry[k] != null && String(entry[k]).trim())) return "Incomplete entry";
  return null;
}

// Call only while holding the script lock so upload and sync see prior writes.
function existingEntryIds(sheet) {
  const lastRow = sheet.getLastRow();
  return new Set(lastRow > 1
    ? sheet.getRange(2, 8, lastRow - 1, 1).getValues().map(row => String(row[0]))
    : []);
}

function syncScans(data) {
  if (!Array.isArray(data.entries) || data.entries.length > 50) return response({status: "error", message: "Sync accepts up to 50 entries"});
  const errors = {};
  // Resolve master data before acquiring the append lock (cache fills use it too).
  const entries = data.entries.map(entry => {
    const error = validateEntry(entry, true);
    if (error) { errors[entry && entry.entry_id || "invalid"] = error; return null; }
    return {entry: entry, prepared: prepareScan(entry)};
  }).filter(Boolean);
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sheet = getSheet(SHEETS.scans);
    ensureEntryColumns(sheet);
    const existing = existingEntryIds(sheet);
    const confirmed = [];
    for (const {entry, prepared} of entries) {
      if (existing.has(entry.entry_id)) { confirmed.push(entry.entry_id); continue; }
      if (!prepared.row) { errors[entry.entry_id] = prepared.message; continue; }
      sheet.appendRow(prepared.row);
      existing.add(entry.entry_id);
      confirmed.push(entry.entry_id);
    }
    SpreadsheetApp.flush();
    return response({status: "success", confirmed_ids: confirmed, errors: errors});
  } finally { lock.releaseLock(); }
}
