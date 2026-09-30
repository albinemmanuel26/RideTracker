# Ride Track

Cycling checkpoint check-in app for Android and iOS.

The Google Apps Script backend is in `backend/Code.gs`.

Rider details from both master sheets are downloaded after each successful login
and saved on the device. QR and manual rider lookups use this list; submitting a
check-in still requires internet and backend validation. Settings contains manual
rider refresh, counts, the last successful download time, and checkpoint changes.
Failed refreshes keep the previous list. Existing signed-in installations without
a list can download it from Settings.

Before using this version, update the Apps Script web app deployment with
`backend/Code.gs`, which adds the `getRiders` action. Both master sheets must have
`rider_id` and `name` headers, complete rider details, and globally unique rider IDs.
The app blocks completion of a new login if the rider download fails; retry login
after resolving the error. No automatic refresh occurs during scanning.

Validation: `flutter test`, `flutter analyze`, and `node backend/riders_test.js`.
