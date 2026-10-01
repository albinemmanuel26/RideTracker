function runSyncTests(source) {
  function check(ok, message) { if (!ok) throw Error(message); }
  const rows = [Array(9).fill('')];
  let held = false;
  let historyReads = 0;
  let beforeLock = null;
  let failFlush = false;
  const sheet = {
    getLastRow: () => rows.length,
    getRange: (row, col, count, width) => ({
      getValues: () => { check(held, 'ID reads must hold lock'); if (row > 1) historyReads++; return rows.slice(row - 1, row - 1 + count).map(r => r.slice(col - 1, col - 1 + width)); },
      setValues: values => values.forEach((r, i) => r.forEach((v, j) => rows[row - 1 + i][col - 1 + j] = v)),
    }),
    appendRow: row => { check(held, 'append must hold lock'); rows.push(row); },
  };
  function acquire() {
    if (beforeLock) {
      const competingRequest = beforeLock;
      beforeLock = null;
      competingRequest();
    }
    check(!held, 'nested lock');
    held = true;
  }
  const locks = {getScriptLock: () => ({waitLock: acquire, tryLock() { acquire(); return true; }, releaseLock() { check(held, 'release without lock'); held = false; }})};
  const api = new Function('SpreadsheetApp', 'LockService', 'ContentService', source + '\ngetRider = id => id === "bad" ? null : ({name:"Rider",category:"40"}); isValidCheckpoint = () => true; getVolunteerName = () => "Volunteer"; return {scanCheckpoint,syncScans};')(
    {getActiveSpreadsheet: () => ({getSheetByName: () => sheet}), flush() { if (failFlush) throw Error('Lost confirmation'); }}, locks,
    {MimeType: {JSON:'json'}, createTextOutput: text => ({setMimeType: () => JSON.parse(text)})});
  const entry = {entry_id: 'a'.repeat(32), rider_id: '1', category: '40', checkpoint: 'Start', scanned_by: '123', scanned_at: '2026-09-30T10:00:00Z'};
  check(api.scanCheckpoint(entry).entry_id === entry.entry_id, 'ack ID');
  check(historyReads === 0, 'empty sheet needs no ID rows read');
  check(api.scanCheckpoint(entry).entry_id === entry.entry_id, 'retry acknowledges same ID');
  check(rows.length === 2, 'retry after lost response must not append');
  check(historyReads === 1, 'retry checks persisted IDs');
  check(!held, 'duplicate response releases lock');
  const missing = {...entry, entry_id: 'b'.repeat(32)};
  const bad = {...entry, entry_id: 'c'.repeat(32), rider_id: 'bad'};
  let result = api.syncScans({entries: [entry, missing, missing, bad]});
  check(rows.length === 3, 'only missing entry appended');
  check(result.confirmed_ids.includes(missing.entry_id), 'missing confirmed');
  check(result.errors[bad.entry_id] === 'Rider not found', 'rejection returned');
  check(rows[2][8] === entry.scanned_at, 'original timestamp preserved');
  api.syncScans({entries: [entry, missing]});
  check(rows.length === 3, 'repeat sync idempotent');
  check(api.scanCheckpoint(missing).status === 'success', 'upload after sync confirmed');
  check(rows.length === 3, 'late upload after sync must not append');
  rows.splice(1, 1);
  api.syncScans({entries: [entry, missing]});
  check(rows.length === 3, 'deleted confirmed entry restored');
  check(!held, 'lock released');
  check(api.syncScans({entries: Array(51).fill(entry)}).status === 'error', 'batch limit');
  // Simulate a competing request finishing just before this request acquires
  // the lock. Both endpoint orderings must observe the preceding write.
  const racing = {...entry, entry_id: 'd'.repeat(32)};
  beforeLock = () => api.syncScans({entries: [racing]});
  check(api.scanCheckpoint(racing).status === 'success', 'scan racing sync confirmed');
  check(rows.filter(row => row[7] === racing.entry_id).length === 1, 'sync wins race: one row');
  const racingSync = {...entry, entry_id: 'e'.repeat(32)};
  beforeLock = () => api.scanCheckpoint(racingSync);
  check(api.syncScans({entries: [racingSync]}).confirmed_ids.includes(racingSync.entry_id), 'sync racing scan confirmed');
  check(rows.filter(row => row[7] === racingSync.entry_id).length === 1, 'scan wins race: one row');
  const racingUpload = {...entry, entry_id: 'f'.repeat(32)};
  beforeLock = () => api.scanCheckpoint(racingUpload);
  api.scanCheckpoint(racingUpload);
  check(rows.filter(row => row[7] === racingUpload.entry_id).length === 1, 'two uploads: one row');
  const uncertain = {...entry, entry_id: '1'.repeat(32)};
  failFlush = true;
  let failed = false;
  try { api.scanCheckpoint(uncertain); } catch (_) { failed = true; }
  check(failed && !held, 'failure after append releases lock');
  failFlush = false;
  check(api.scanCheckpoint(uncertain).entry_id === uncertain.entry_id, 'uncertain write retry confirmed');
  check(rows.filter(row => row[7] === uncertain.entry_id).length === 1, 'uncertain write not duplicated');
  const beforeInvalid = rows.length;
  check(api.scanCheckpoint(bad).status === 'error', 'new invalid rider rejected');
  check(api.scanCheckpoint({...entry, entry_id: 'invalid'}).status === 'error', 'invalid ID rejected');
  check(rows.length === beforeInvalid, 'invalid requests do not append');
  return 'Sync reconciliation tests passed.';
}
if (typeof module !== 'undefined') console.log(runSyncTests(require('node:fs').readFileSync(__dirname + '/Code.gs', 'utf8')));
