const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/Code.gs', 'utf8');
for (const scenario of ['success', 'missingSheet', 'missingHeader', 'incomplete', 'noNameHeader', 'noId', 'duplicate']) {
  const sheets = {
    Riders_Master_40: [['rider_id', 'name'], [123, 'First'], ['', '']],
    Riders_Master_100: [['rider_id', 'name'], [456, 'Second']],
  };
  if (scenario === 'missingSheet') delete sheets.Riders_Master_100;
  if (scenario === 'missingHeader') sheets.Riders_Master_100[0] = ['id', 'name'];
  if (scenario === 'incomplete') sheets.Riders_Master_100[1][1] = '';
  if (scenario === 'noNameHeader') sheets.Riders_Master_100 = [['rider_id'], [456]];
  if (scenario === 'noId') sheets.Riders_Master_100[1][0] = '';
  if (scenario === 'duplicate') sheets.Riders_Master_100[1][0] = 123;
  const spreadsheet = {getActiveSpreadsheet: () => ({getSheetByName: name => sheets[name] ? {getDataRange: () => ({getValues: () => sheets[name]})} : null})};
  const content = {MimeType: {JSON: 'json'}, createTextOutput: text => ({setMimeType: () => JSON.parse(text)})};
  const post = new Function('SpreadsheetApp', 'ContentService', 'LockService', source + '\nreturn data => doPost({postData: {contents: JSON.stringify({...data, key: API_KEY})}});')(spreadsheet, content, {getScriptLock: () => ({waitLock() {}, releaseLock() {}})});
  const result = post({action: 'getRiders'});
  const success = ['success', 'incomplete', 'noNameHeader', 'noId'].includes(scenario);
  assert.equal(result.status, success ? 'success' : 'error');
  if (success) {
    assert.deepEqual(result.riders, {
      '40': [{rider_id: '123', rider_name: 'First', category: '40'}],
      '100': scenario === 'noId' ? [] : [{rider_id: '456', rider_name: ['incomplete', 'noNameHeader'].includes(scenario) ? 'NA' : 'Second', category: '100'}],
    });
  } else assert.equal(result.riders, undefined);
}
console.log('Seven rider download scenarios passed.');
