function runCacheTests(source) {
  function check(ok, message) { if (!ok) throw new Error(message); }
  const entries = new Map();
  let held = false;
  let reads = 0;
  let fail = false;
  const sheets = {
    Riders_Master_40: [['rider_id', 'name'], ['1', 'First']],
    Riders_Master_100: [['rider_id', 'name'], ['2', 'Second']],
    Volunteers: [['phone', 'name'], ['123', 'Volunteer']],
    Checkpoints_Master: [['checkpoint_id', 'checkpoint_name', 'category', 'is_active'], ['CP1', 'Start', '40&100', true]],
  };
  const cache = {
    get: key => { if (fail) throw Error('cache unavailable'); return entries.get(key) || null; },
    remove: key => entries.delete(key),
    put: (key, value, ttl) => { check(ttl === 300, 'TTL'); entries.set(key, value); },
  };
  const api = new Function('CacheService', 'LockService', 'SpreadsheetApp', 'ContentService', source + '\nreturn {getRider, getRiders, getVolunteerName, isValidCheckpoint, getCheckpoints, masterData};')(
    {getScriptCache: () => cache},
    {getScriptLock: () => ({waitLock() { check(!held, 'nested lock'); held = true; }, releaseLock() { held = false; }})},
    {getActiveSpreadsheet: () => ({getSheetByName: name => ({getDataRange: () => ({getValues: () => { reads++; return sheets[name]; }})})})},
    {MimeType: {JSON: 'json'}, createTextOutput: text => ({setMimeType: () => JSON.parse(text)})},
  );
  check(api.getRider('1').name === 'First', 'cold rider');
  check(api.getRider('2').category === '100', 'warm rider');
  check(reads === 2, 'warm rider must not read sheets');
  sheets.Riders_Master_40.push(['3', 'Added']);
  api.getRiders();
  const afterRefresh = reads;
  check(api.getRider('3').name === 'Added', 'refresh must replace cache');
  check(reads === afterRefresh, 'refreshed lookup must hit cache');
  api.getVolunteerName('123'); api.getVolunteerName('123');
  check(reads === afterRefresh + 1, 'volunteer cache');
  check(api.isValidCheckpoint('40', 'Start'), 'common checkpoint');
  check(api.isValidCheckpoint('100', 'Start'), 'common checkpoint cached');
  check(reads === afterRefresh + 2, 'checkpoint cache');
  sheets.Checkpoints_Master[1][3] = false;
  api.getCheckpoints();
  check(!api.isValidCheckpoint('40', 'Start'), 'checkpoint refresh');
  entries.clear();
  check(api.getRider('1').name === 'First', 'eviction fallback');
  entries.set('master-v1:riders', '{broken');
  check(api.getRider('1').name === 'First', 'corrupt cache fallback');
  fail = true;
  check(api.getRider('1').name === 'First', 'cache failure fallback');
  fail = false;
  try { api.masterData('failure', () => { throw Error('sheet failed'); }); } catch (_) {}
  check(!held, 'lock released on error');
  api.masterData('large', () => 'x'.repeat(40000));
  check(!entries.has('master-v1:large'), 'oversize fallback');
  return 'Master cache hit, refresh, eviction, corruption, outage, size, and lock cleanup checks passed.';
}
if (typeof module !== 'undefined') {
  console.log(runCacheTests(require('node:fs').readFileSync(__dirname + '/Code.gs', 'utf8')));
}
