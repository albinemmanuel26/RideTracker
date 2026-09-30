const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/Code.gs', 'utf8');
for (const scenario of ['success', 'missingSheet', 'missingHeader', 'incomplete', 'duplicate']) {
  const sheets = {
    Riders_Master_40: [['rider_id', 'name'], [123, 'First'], ['', '']],
    Riders_Master_100: [['rider_id', 'name'], [456, 'Second']],
  };
  if (scenario === 'missingSheet') delete sheets.Riders_Master_100;
  if (scenario === 'missingHeader') sheets.Riders_Master_100[0] = ['id', 'name'];
  if (scenario === 'incomplete') sheets.Riders_Master_100[1][1] = '';
  if (scenario === 'duplicate') sheets.Riders_Master_100[1][0] = 123;
  const spreadsheet = {getActiveSpreadsheet: () => ({getSheetByName: name => sheets[name] ? {getDataRange: () => ({getValues: () => sheets[name]})} : null})};
  const content = {MimeType: {JSON: 'json'}, createTextOutput: text => ({setMimeType: () => JSON.parse(text)})};
  const post = new Function('SpreadsheetApp', 'ContentService', source + '\nreturn data => doPost({postData: {contents: JSON.stringify({...data, key: API_KEY})}});')(spreadsheet, content);
  const result = post({action: 'getRiders'});
  assert.equal(result.status, scenario === 'success' ? 'success' : 'error');
  if (scenario === 'success') {
    assert.deepEqual(result.riders, {
      '40': [{rider_id: '123', rider_name: 'First', category: '40'}],
      '100': [{rider_id: '456', rider_name: 'Second', category: '100'}],
    });
  } else assert.equal(result.riders, undefined);
}
console.log('Five rider download scenarios passed.');
