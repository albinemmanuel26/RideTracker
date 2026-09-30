function runSyncTests(source) {
  function check(ok, message) { if (!ok) throw Error(message); }
  const rows = [Array(9).fill('')];
  let held = false;
  let historyReads = 0;
  const sheet = {
    getLastRow: () => rows.length,
    getRange: (row, col, count, width) => ({
      getValues: () => { if (row > 1) historyReads++; return rows.slice(row - 1, row - 1 + count).map(r => r.slice(col - 1, col - 1 + width)); },
      setValues: values => values.forEach((r, i) => r.forEach((v, j) => rows[row - 1 + i][col - 1 + j] = v)),
    }),
    appendRow: row => { check(held, 'append must hold lock'); rows.push(row); },
  };
  const locks = {getScriptLock: () => ({waitLock() { check(!held, 'nested lock'); held = true; }, tryLock() { held = true; return true; }, releaseLock() { held = false; }})};
  const api = new Function('SpreadsheetApp', 'LockService', 'ContentService', source + '\ngetRider = id => id === "bad" ? null : ({name:"Rider",category:"40"}); isValidCheckpoint = () => true; getVolunteerName = () => "Volunteer"; return {scanCheckpoint,syncScans};')(
    {getActiveSpreadsheet: () => ({getSheetByName: () => sheet}), flush() {}}, locks,
    {MimeType: {JSON:'json'}, createTextOutput: text => ({setMimeType: () => JSON.parse(text)})});
  const entry = {entry_id: 'a'.repeat(32), rider_id: '1', category: '40', checkpoint: 'Start', scanned_by: '123', scanned_at: '2026-09-30T10:00:00Z'};
  check(api.scanCheckpoint(entry).entry_id === entry.entry_id, 'ack ID');
  check(historyReads === 0, 'normal scan must not read history');
  const missing = {...entry, entry_id: 'b'.repeat(32)};
  const bad = {...entry, entry_id: 'c'.repeat(32), rider_id: 'bad'};
  let result = api.syncScans({entries: [entry, missing, missing, bad]});
  check(rows.length === 3, 'only missing entry appended');
  check(result.confirmed_ids.includes(missing.entry_id), 'missing confirmed');
  check(result.errors[bad.entry_id] === 'Rider not found', 'rejection returned');
  check(rows[2][8] === entry.scanned_at, 'original timestamp preserved');
  api.syncScans({entries: [entry, missing]});
  check(rows.length === 3, 'repeat sync idempotent');
  rows.splice(1, 1);
  api.syncScans({entries: [entry, missing]});
  check(rows.length === 3, 'deleted confirmed entry restored');
  check(!held, 'lock released');
  check(api.syncScans({entries: Array(51).fill(entry)}).status === 'error', 'batch limit');
  return 'Sync reconciliation tests passed.';
}
if (typeof module !== 'undefined') console.log(runSyncTests(require('node:fs').readFileSync(__dirname + '/Code.gs', 'utf8')));
