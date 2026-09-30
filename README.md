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
`rider_id` headers and globally unique rider IDs. Rows without an ID are skipped;
missing names default to NA. Email and phone are not required or downloaded.
The app blocks completion of a new login if the rider download fails; retry login
after resolving the error. No automatic refresh occurs during scanning.

Validation: `flutter test`, `flutter analyze`, and `node backend/riders_test.js`.

Performance: the app restores the rider index once at startup and replaces it
only after a successful saved refresh. Backend rider, volunteer-name, and
checkpoint lookups use a shared five-minute cache. Rider downloads and checkpoint
list requests read live sheets and refresh the corresponding cache. Login checks
remain live; PINs are not cached. Direct sheet edits otherwise become visible
when the cache expires or is evicted. Check-ins append without reading scan history; a short lock protects the append.
Repeated submissions are allowed and each successful request creates a row.

Cache entries above 30,000 JSON characters fall back to sheet reads to stay safely
within the Apps Script per-entry byte limit, including Unicode. Cache failures also
fall back to sheets. Run `node backend/cache_test.js` for cache regression checks.


Check-in behavior: the app does not automatically retry an uncertain write or query
scan history. Unconfirmed uploads remain saved locally for manual sync. Reports must deduplicate by rider ID, category, and
checkpoint if they need unique arrivals (typically keeping the earliest timestamp).
The legacy `checkScanStatus` endpoint remains available for older installations.
See `backend/DEPLOYMENT.md` for the server update.

Local history and sync: new scans are saved in SQLite before upload. Settings →
Scan history & sync retains every entry and reconciles all local entries in batches
of 50, including previously confirmed entries. Use Sync now for an unconfirmed
entry rather than scanning again. See backend/DEPLOYMENT.md for the required H/I columns and deployment order.

Local duplicate prevention: submitting a rider already saved on this device for
that category and checkpoint is blocked, whether confirmed or awaiting sync.
Different checkpoints/categories are allowed. The database upgrade preserves all
older history; existing duplicate rows are not deleted. The rule persists across
logout and restart and does not prevent duplicates from other devices or late
uploads racing with sync. There is no event identifier yet, so retained history
also blocks the same rider/category/checkpoint combination in a future event.

Checkpoint options and riders are downloaded after login or through Settings →
Refresh riders and checkpoints. Each successful list is saved independently.
If riders succeed but checkpoints fail, the app informs the volunteer and retains
previous checkpoint options, without a retry prompt. If riders fail, Retry/Cancel
is shown with the outcome of both downloads. A first login without any saved
checkpoints cannot proceed to scanning until checkpoint options become available.
Changing checkpoints uses only the saved list. No backend changes are required.

After authentication, checkpoint selection opens immediately while rider and
checkpoint downloads run concurrently. The popup shows each download's status and
allows checkpoint selection while loading. Start scanning is enabled after the
downloads settle, riders have saved successfully, and a checkpoint is selected.
Rider failures expose Retry/Cancel in the popup; checkpoint failures retain saved
options and show an inline message. Settings refresh uses the same parallel flow.

Start scanning now opens a download-status popup even while downloads are running.
Already failed downloads are retried on that click; successful lists are retained.
The popup shows live progress and offers Retry failed downloads or Cancel after
failure. Continue is available when riders are ready and saved checkpoint options
exist. If no checkpoint was selected, the app returns to selection before scanning.
