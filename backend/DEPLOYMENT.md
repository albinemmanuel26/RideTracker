# Deploy local scan history and manual sync

1. Back up the Riders_Scan sheet.
2. Keep the existing seven columns A–G in their current order. Reserve H for
   `entry_id` and I for `scanned_at`. Leave H/I blank or set those exact headers.
   If H/I contain other data, move those columns first. The server creates the
   headers automatically, and rejects uploads if conflicting headers exist.
3. Replace the Apps Script project's Code.gs with backend/Code.gs from this repo.
4. Update the existing web app deployment to a new version, keeping its URL and
   working access/execution settings.
5. Rebuild/install the Flutter app (a SQLite native dependency was added).

Each new app check-in is committed to the device database before sending. Normal
uploads include a random 128-bit entry ID and the original device scan time in UTC.
The server appends these in H/I, retains upload time in the existing columns, and
acknowledges the entry ID. Normal uploads check column H under the same script
lock as sync before appending. Retrying a saved entry returns success and its ID
without adding a row. Requests from older clients without IDs retain their
existing append behavior.

The updated Flutter app confirms the local save immediately and uploads pending
entries through `syncScans` while foregrounded. It retries failed requests with
increasing delays (5–60 seconds), checks for pending work every 30 seconds when
idle, and resumes on reopening the app. The scanner displays pending and
needs-attention counts with a link to history. Server-rejected entries remain
saved and can be retried using manual sync after their cause is resolved.
Install a new app build to enable this behavior. Uploads are not guaranteed while
the app is backgrounded or closed; saved pending entries survive restarts.

Settings → Scan history & sync → Sync now reconciles all entries on this device,
including previously confirmed ones, in batches of 50. The new syncScans action
reads column H once per batch under the append lock and adds missing IDs only.
It returns confirmed_ids and per-entry errors. Master-data validation still applies.
An invalid rider/checkpoint/volunteer remains local with an error for the organizer
to resolve; it is never silently discarded. Sync can be safely run again after a
partial failure. Different scans of the same rider have different entry IDs.

Original device timestamps depend on the phone's clock. Use scanned_at for arrival
time of delayed uploads, and retain server upload times for auditing.

History survives logout and app restarts and is shared by sessions on this device.
It is not backed up remotely until uploaded; clearing app storage or uninstalling
can delete unuploaded history. Entries recorded before this app update are not
reconstructed. Existing server rows without IDs remain untouched.

Normal uploads and sync can safely submit the same entry in either order: the
ID check and append are serialized under one lock. Existing duplicate rows are
not removed. Different entry IDs remain separate scans, even for the same rider
and checkpoint. This backend-only retry-safety update requires deploying a new
Apps Script version; it does not require rebuilding an already compatible app.

Verification: submit a test scan offline, restart, then sync online. The entry
should appear with its original scan time. Sync again: it should not add another
row. The backend/sync_test.js regression harness also covers restoring deleted
entries, partial validation failures, and batch limits.
