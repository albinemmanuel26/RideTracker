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
acknowledges the entry ID. Normal uploads still skip scan-history checking.

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

Because normal uploads do not check IDs, a late original upload can append after
sync inserts the same entry. Prefer syncing after scanning settles. Reports can
remove such duplicates by entry_id; unique checkpoint-arrival reports should still
group by rider/category/checkpoint. Guaranteed exactly-once writes would require
ID checks on the normal upload path too.

Verification: submit a test scan offline, restart, then sync online. The entry
should appear with its original scan time. Sync again: it should not add another
row. The backend/sync_test.js regression harness also covers restoring deleted
entries, partial validation failures, and batch limits.
