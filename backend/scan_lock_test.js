// Pure JavaScript test harness; pass the contents of Code.gs to this function.
function runScanLockTests(source) {
  function check(value, message) {
    if (!value) throw new Error(message);
  }
  for (const scenario of ['success', 'busy', 'writeError', 'flushError']) {
    let held = false;
    const events = [];
    const rows = [['id', 'rider_id', 'name', 'category', 'checkpoint']];
    if (scenario === 'duplicate') rows.push([1, '123', 'Rider', '40', 'Start']);
    const sheet = {
      getDataRange: () => { throw new Error('Scan must not read history'); },
      appendRow: row => {
        check(held, 'Write without lock');
        events.push('write');
        if (scenario === 'writeError') throw new Error('writeError');
        rows.push(row);
      }
    };
    const spreadsheet = {
      getActiveSpreadsheet: () => ({getSheetByName: () => sheet}),
      flush: () => {
        check(held, 'Flush without lock');
        events.push('flush');
        if (scenario === 'flushError') throw new Error('flushError');
      }
    };
    const locks = {getScriptLock: () => ({
      tryLock: timeout => {
        check(timeout === 10000, 'Unexpected wait limit');
        events.push('lock');
        held = scenario !== 'busy';
        return held;
      },
      releaseLock: () => {
        check(held, 'Released unowned lock');
        events.push('release');
        held = false;
      }
    })};
    const content = {
      MimeType: {JSON: 'json'},
      createTextOutput: text => ({setMimeType: () => JSON.parse(text)})
    };
    const scan = new Function('SpreadsheetApp', 'LockService', 'ContentService', 'console',
      source + '\ngetRider = () => ({name: "Rider", category: "40"});' +
      '\nisValidCheckpoint = () => true; getVolunteerName = () => "Volunteer";' +
      '\nreturn scanCheckpoint;')(spreadsheet, locks, content, {log: () => {}});
    const request = {rider_id: '123', category: '40', checkpoint: 'Start', scanned_by: '456'};
    let result;
    let error;
    try { result = scan(request); } catch (e) { error = e; }
    check(!held, 'Lock leaked: ' + scenario);
    if (scenario.endsWith('Error')) {
      check(error && error.message === scenario, 'Expected failure: ' + scenario);
      check(events.at(-1) === 'release', 'Failure did not release lock');
    } else {
      check(!error, 'Unexpected failure');
      const expected = scenario === 'busy' ? 'error' : scenario;
      check(result.status === expected, 'Wrong result: ' + scenario);
      if (scenario === 'success') {
        check(events.join(',') === 'lock,write,flush,release', 'Incorrect ordering');
        check(scan(request).status === 'success', 'Repeated scan should succeed');
        check(rows.length === 3, 'Repeated scan must append another row');
      } else {
        check(!events.includes('write'), 'Unexpected write');
        if (scenario === 'busy') check(events.join(',') === 'lock', 'Busy request accessed history');
      }
    }
  }
  return 'Four append-lock scenarios passed, including allowed repeats and failure cleanup.';
}
