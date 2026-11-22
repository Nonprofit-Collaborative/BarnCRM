# ADR-0239: Backup Sets run on a schedule and send their files off platform through the Connector

**Status:** Proposed (build agent, 2026-11-21; for the integrator and Brandon)
**Date:** 2026-11-21
**Source:** Plan BK-10 (release 1.36, D-221: "Scheduled runs can be built now. Automatic backup is
also the goal, not manual downloads which are already available today (export)", and an
off-platform destination for archive runs). Amends ADR-0213 (Backup Sets) decisions 1 and 6 and
its consequence "BarnCRM never deletes them", and ADR-0235 (BarnCRM Connector) decision 3. Builds
on ADR-0166 (nightly job dispatcher), ADR-0017 and D-200 S1 (module extension seams), R-BD9
(Archive by Query) and CN-08 (importable templates).

## Context

ADR-0213 shipped Backup Sets as saved Find queries run on demand to the admin's Files, with
scheduled runs waiting for C-38, and kept backup outside the org out of scope (D-13 as amended).
D-221 asks for automatic backups: runs on a schedule, a copy kept in the organization's own
storage outside Salesforce, and the same destination for Archive by Query, whose originals must
not be deleted until the copy is safe. ADR-0166 gives one nightly run with per-step switches;
ADR-0235 gives connections whose secrets live only in Named and External Credentials. Core must
still not depend on the Connector module (ADR-0013, ADR-0017).

## Decision

1. **A schedule on the set, no new object.** The `backup` key of the query document gains an
   optional `schedule`: `{ "frequency": "daily" }`, `{ "frequency": "weekly", "weekday": 1-7 }`
   (Monday is 1) or `{ "frequency": "monthly", "day": 1-28 }` (days 29 to 31 are left out so a
   monthly set runs every month). Only the query's owner sets it, as for the key itself. Find
   keeps the whole key when the query is saved again.
2. **The nightly run starts it.** Core's new nightly step **Backup Sets** (`BackupSetSchedule`, key
   `BarnCRM Backup Sets`, 2:00 AM, its own switch shipped on: a set without a schedule never runs)
   starts each set whose schedule falls today, as the user the nightly run runs as, who needs
   Manage BarnCRM Settings and Find and Export Records; without them nothing starts and the Error
   Log says why. The step reads every saved query without sharing (sets are private to their
   owners), but the run reads records in user mode as before, so it saves what that user may
   read. The step's switch, not an Automation Registry row, is the automation's on/off: the
   registry lists trigger handlers, and ADR-0166 decision 4 made the per-step switch the control
   for nightly work.
3. **Runs kept (amends ADR-0213's "BarnCRM never deletes them").** A new Core setting **Backup Runs
   Kept** (`Backup_Runs_Kept__c`, default 7, 1 to 365) is how many runs of each scheduled set keep
   their files. When a run of a scheduled set completes, the files of that set's older complete
   runs are deleted and each such run says so in its log. A set run only with Run Now keeps every
   file, as before. A run's parts are now kept on its definition (`documents`) so all of them,
   not only the first, are found again.
4. **Destinations behind a Core seam (amends ADR-0213 decision 1 and D-13 as amended there).** A
   copy may leave the org, to storage the organization owns and names: Core defines the interface
   `OffPlatformDestination` (send one file), found through the module catalog's `Extensions__c`
   like every other seam, so Core names no module class. A Backup Set gains a destination
   (`files`, the default, or `offPlatform`), and Archive by Query gains the same choice. The
   option is shown only when an installed module provides a destination; otherwise a short note
   says the BarnCRM Connector adds it. AR-10's `ArchiveDestination` (an archive rule's Files,
   BigObject or OffPlatform choice, which starts a whole run and is found by the class name
   `OffPlatformArchiveDestination`) is a separate, coarser seam; its OffPlatform choice is a
   Core class that writes the parts to Files and sends them through `OffPlatformDestination`,
   added once both branches are on main.
5. **Files first, then sent, one part per transaction.** A run still writes its parts to Files;
   a Core batch (`OffPlatformSendBatch`, scope 1, callouts allowed) then reads one part per
   execute and hands it to the destination, so a part of at most about 3 MB is the most any
   transaction holds (archive and backup parts are written at 3,000,000 characters at most, under
   both the 12 MB asynchronous heap and the callout size limit). Which parts were sent is kept on
   the job. A part that fails is written to the Error Log and to the run's log; the next
   scheduled run of any set first sends every part still waiting, for runs whose files are still
   kept. When every part is sent, and the new setting **Remove Files Copy After Sending**
   (`Backup_Remove_Sent_Files__c`, default off) is on, the parts are deleted from Files, so
   storage is not doubled.
6. **An archive deletes only after the copy is safe.** With destination Off Platform, Archive by
   Query's delete starts only when every part was sent with a success answer. A failed send ends
   the job Failed with nothing deleted and the Files copy kept.
7. **The Off Platform destination lives in the Connector (amends ADR-0235 decision 3).** `ConnectorBackupDestination`
   implements the seam and is registered in the Connector catalog row. The admin makes one
   connection the **Backup Destination** on the Connections tab, with a method (PUT or POST), a
   path with the `{file}` slot (part titles already carry the date), and up to five fixed request
   headers that hold no secret (F1 rules: no `{!`, no sign-in header), kept in the new Connector
   Connection field `Backup_JSON__c`. One connection at most is the backup destination. The
   request is `callout:<connection>` plus the checked path, the part's CSV as the body,
   `Content-Type: text/csv`; any 2xx answer is success. The key stays in the Named and External
   Credential; the user who sends (the runner, or the nightly run's user) needs the connection's
   principal access (BarnCRM Connections), which the creator of a connection already has; the
   nightly run's user is given it by the admin, and until then the destination says so. Saving
   writes only the row: giving the set is a setup write that may not share the transaction.
   CN-08 templates gain an optional `backup` part (method, path, headers) so templates for
   common storage services (an HTTPS endpoint that accepts PUT with a header key, or a WebDAV
   folder such as Nextcloud, ownCloud or a NAS) prefill it, and such a template may leave its
   base URL for the person to type (storage has no fixed host to lock, unlike an app); none is
   preloaded or shipped as metadata, and the example files live in the repository as
   documentation (`docs/connector-templates/`). A path holds no query string (F1 path rules), so
   storage that needs a secret in the URL's query (a SAS token) is not supported.
8. **Common storage services, with Salesforce signing (BK-10b; amends decision 7 and ADR-0235
   decision 3; canonical model R-CN12).** Two connection kinds join the four, and neither lets
   Apex read a secret (ADR-0229):
   - **AWS Signature Version 4** (`AwsSigV4`), made on New Connection: the External Credential
     uses Salesforce's `AwsSv4` protocol with the authentication parameters `AwsService` and
     `AwsRegion` read from the base URL's host (`<bucket>.s3.<region>.amazonaws.com`; any other
     host is refused before anything is made), a named principal `AwsSigV4` holding
     `awsAccessKeyId` (plain) and `awsSecretAccessKey` (encrypted), and a Named Credential with
     **Generate Authorization Header** on and no formula header. Salesforce signs each callout.
     This is how Amazon S3 works.
   - **OAuth 2.0 made in Setup** (`OAuth`): the browser sign-in and the Auth Provider (which holds
     the client secret) can only be set up in Setup, so BarnCRM does not create these. An admin
     makes an External Credential and Named Credential of one name starting `BarnConn_`, with a
     named principal `OAuth` and Generate Authorization Header on; BarnCRM lists it, adds its
     principal to the Connections set on Check Connection, and uses it, but never writes its
     credential (Replace Key and the first key are refused). This is how Google Drive, OneDrive
     and SharePoint (Microsoft Graph), Dropbox and Azure Blob Storage (Microsoft Entra ID, browser
     or client credentials flow) work.
   Backup Settings gain what these services need, still holding nothing secret: `{file}` may
   appear in a header value (written JSON-escaped and ASCII, for Dropbox's `Dropbox-API-Arg`) or
   in optional `metadata`, one JSON object sent first in a `multipart/related` body (Google
   Drive); `{file}` must appear at least once in the path, a header or the metadata, and at most
   once in the path. A `Content-Type` header replaces `text/csv` (Dropbox wants
   `application/octet-stream`). A path may end with a query only of names from a fixed list
   (`uploadType`, `supportsAllDrives`) with plain values, so a signature or SAS token still
   cannot be stored. A template whose auth kind is `OAuth` must carry a `backup` part; importing
   it creates nothing and opens the Backup Destination form filled in, offering only OAuth
   connections. Example templates for each service are in `docs/connector-templates/`.

## Alternatives considered

- **A Backup Set object with schedule fields.** Rejected: one more object at the 200-object
  budget, for three values that fit the existing key.
- **A Connector recipe step that reads Files.** Rejected: a recipe cannot see Core's run, the
  archive's delete must wait on the send, and the admin would build a recipe for what is one
  choice on the set.
- **Stream each part straight to the destination without Files.** Rejected: a failed callout
  would lose the rows (the export cannot be repeated for an archive whose records are deleted),
  and a retry needs the part kept somewhere; the Files copy is removed after sending instead.
- **Signing AWS requests in Apex.** Rejected: Apex would have to read the secret to sign, which
  ADR-0229 forbids. Salesforce's own AWS Signature Version 4 protocol signs instead (decision 8).
- **Creating OAuth External Credentials from Apex.** Rejected: the Auth Provider, which holds the
  client secret, and the browser sign-in are Setup steps in any case, so creating only the
  External and Named Credential from Apex would save two Setup screens for more code and more
  untestable `ConnectApi` surface.
- **Azure shared key or SAS token.** Rejected: a shared key signs in Apex, and a SAS token is a
  secret in the query that would sit in a record. Azure Blob Storage works through Microsoft
  Entra ID OAuth instead.

## Consequences

- Two Core settings, one Core nightly step and one Connector field; no new object.
- OAuth storage needs the admin's Setup work (an Auth Provider, an External and Named Credential,
  Authenticate); the admin guide gives the steps and values per service. An org whose release
  refuses the `AwsSv4` credential from `ConnectApi` can make the same credential in Setup under
  the same naming rules. The S3 request with Salesforce's signing is checked on a real bucket in
  the release gate, since a test cannot reach AWS.
- Files still count against file storage until runs pass Backup Runs Kept, or are sent with
  Remove Files Copy After Sending on.
- A scheduled run's files are owned by the nightly run's user, and what it saves is what that user
  may read.
- Retention at the destination is the storage service's own (its lifecycle rules); BarnCRM never
  deletes anything there.
