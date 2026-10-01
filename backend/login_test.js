// Read-only login must work even when timestamp writes are unavailable.
function runLoginTests(source) {
  function check(ok, message) { if (!ok) throw Error(message); }
  let count = 0;
  for (const withTimestamp of [true, false]) {
    for (const scenario of ['success', 'wrongPin', 'inactive', 'unknownPhone']) {
      const rows = [
        ['phone', 'pin', 'is_active', 'name', 'role'],
        ['1234567890', '012345', scenario !== 'inactive', 'Volunteer', 'scanner'],
      ];
      if (withTimestamp) {
        rows[0].push('last_login');
        rows[1].push('existing timestamp');
      }
      const before = JSON.stringify(rows);
      const sheet = {
        getDataRange: () => ({getValues: () => rows}),
        getRange: () => { throw Error('Login must not attempt a timestamp write'); },
      };
      const post = new Function('SpreadsheetApp', 'ContentService', source +
        '\nreturn data => doPost({postData: {contents: JSON.stringify({...data, key: API_KEY})}});')(
        {getActiveSpreadsheet: () => ({getSheetByName: () => sheet})},
        {MimeType: {JSON: 'json'}, createTextOutput: text => ({setMimeType: () => JSON.parse(text)})},
      );
      const result = post({action: 'loginVolunteer',
        phone: scenario === 'unknownPhone' ? '9999999999' : '1234567890',
        pin: scenario === 'wrongPin' ? '999999' : '012345'});
      if (scenario === 'success') {
        check(result.status === 'success', 'Valid login failed');
        check(JSON.stringify(result.volunteer) === JSON.stringify({
          name: 'Volunteer', phone: '1234567890', role: 'scanner',
        }), 'Volunteer response changed');
      } else {
        const messages = {wrongPin: 'Invalid PIN', inactive: 'User inactive', unknownPhone: 'User not found'};
        check(result.status === 'error' && result.message === messages[scenario], 'Validation changed: ' + scenario);
        check(result.volunteer === undefined, 'Rejected login returned volunteer details');
      }
      check(JSON.stringify(rows) === before, 'Login changed sheet data');
      count++;
    }
  }
  return count + ' read-only login scenarios passed.';
}
if (typeof module !== 'undefined') console.log(runLoginTests(require('node:fs').readFileSync(__dirname + '/Code.gs', 'utf8')));
