# ADR-0053: Posted gifts and closed periods are locked by a rule that always runs

**Status:** Accepted (builder decision)
**Date:** 2026-09-24
**Source:** plan Section 5.2 feature G-20 ("Accounting posting flag and period lock; prevents
edits to posted gifts") and Section 4.12 ("the posting flag per gift and the period lock belong
to Giving"); builder decision under plan Section 9.3, following ADR-0024 and ADR-0051

## Context

Jen, the bookkeeper, exports the month's gifts (X-04, ADR-0051) and imports them into the
accounting system. From then on the books hold those rows. If a gift in them is edited,
deleted, or a new gift is dated into that month, BarnCRM and the books disagree and nothing
says so. The plan names two controls: a flag on each gift that is in the books, and a date up to
which the books are closed.

ADR-0051 decided that the export writes nothing and that marking gifts posted is "a Giving
service the export calls": Connect depends on Giving (`sfdx-project.json`), so it calls Giving
directly and needs no string seam. ADR-0024 settled how a rule that protects a record is
enforced: from an automation marked Always Runs, past which the only way is a custom permission
granted to nobody, each use written to the Error Log.

The plan does not say which fields a lock covers, what a refund of a locked gift does, what
happens to a Pending gift in a closed month, who may unpost, or how the lock meets imports, the
inbound API, gift batches and import undo.

## Decision

**In the books** means what the accounting export reads: Status Received, Refunded or Written
off (ADR-0022), and Type not In-kind. A Pending gift and an in-kind gift are in no file, so no
lock protects them.

**A gift is locked** when it is in the books and either posted (Posted to Accounting is set) or
dated on or before the Books Closed Through date. A locked gift:

- keeps every value the export writes for it: Gift Date, Amount, Donor Contact, Donor Account,
  Type (the payment method), Payment Reference, Original Gift, and its allocations (none added,
  changed or deleted, so each fund's share stays);
- stays in the books: its Status may move between Received, Refunded and Written off, which is
  what a refund does to the original (R-G3), but not to Pending;
- is not deleted;
- keeps what it names: the person or organization it names as donor, and the gift it names as
  its original, are not deleted either, because the platform clears those lookups on delete
  without running any gift trigger. A merge still works: before delete records who names the
  record, and the refusal is made after delete only when the record was not merged
  (MasterRecordId empty), because a merge moves the gifts to the surviving record. A person's
  household Account is guarded the same way: deleting it deletes the person with it, and a
  cascade delete fires no Contact trigger, so the Account guard also refuses when a locked
  gift's Donor Contact belongs to the Account being deleted. The guard on
  Contact and Account runs from Core's triggers through two Always Runs registry rows in Giving;
  the guard on an original is part of the gift lock's delete rule. Original Gift is not made
  Restrict: that would refuse deleting any refunded gift, locked or not, with the platform's
  words instead of the lock's, and could not be overridden.

Everything else stays editable: appeal, acknowledgment, receipt, soft credits, tribute, matching
link, commitment and installment, the in-kind and benefit fields. None of them is in the file.

**Nothing enters the books in a closed period.** A new gift, a restored one, or an edit that
leaves a gift in the books and dated on or before the close date when it was not locked before
(its date moved back, its status moved from Pending, its type moved from In-kind) is refused.

**Refunds and write-offs still work, as new records in the open period.** `GiftService.refund`
and `writeOff` insert a negative gift dated today and move the original's status within the
books. The close date must be at least two days before today, the day before yesterday at the latest,
so today is open wherever the closer and the person refunding are: a close through yesterday,
set early in the morning east of the date line, would refuse a refund dated today in the
Pacific. Only the date line extremes (UTC+13 and UTC+14 against UTC-10 and beyond) are further
apart than that. A Pending gift is never reversed (ADR-0054): one that will never
be paid is cancelled, which keeps it out of the books, so a closed month does not refuse it.

**Enforcement follows ADR-0024.** Two automations, `Gift_Posting_Lock` on Gift and
`Gift_Allocation_Posting_Lock` on Gift Allocation, carry Always Runs, so the switch and the
pause do not reach them. The one way past is `Override_Posting_Lock`, a custom permission on no
permission set: it lets a locked gift or allocation be saved or deleted, a gift be created or
restored in a closed period, and the close date be moved back. Every use is written to the Error
Log at Warning, naming the gift and what changed. It is not `Override_Receipt_Lock`: ADR-0024
says that override reaches receipt immutability and nothing else.

**Posting.** `Accounting_Posted_At__c` and `Accounting_Posted_By__c` on Gift, read only in every
permission set and written only by `GiftPostingService` through `GiftPostingWriter` (system
mode, ADR-0021); any other write to them is refused by the lock. `markPosted` needs the
`Post_Gifts` custom permission, marks the gifts given that are in the books and not yet posted,
and leaves the others as they are, so running it twice changes nothing. `unpost` needs
`Post_Gifts` and a reason, clears the two fields, and writes one Warning line per gift naming who
posted it and when. An unposted gift dated in a closed period stays locked by the period.
`Post_Gifts` is on Giving Admin and on Connect's Accounting Export permission set, because
marking the export posted is the bookkeeper's step.

The export page offers **Mark these gifts posted** after a download, and an **Only gifts not yet
posted** choice, so a gift entered late into a month already posted is found by the next export.
The page sends back a digest of the file it downloaded (SHA-256 over every row's gift Id, date,
fund Id and amount, sorted); the server builds the same export again and marks nothing unless the
digest matches. A count and a total were not enough: a gift moved out of the range and another of
the same amount added, or an allocation moved to another fund, keep both and change the books. Posting writes
only the two package fields, so the switchable Gift automations are bypassed for that save; the
Always Runs locks still run. One call marks at most 5,000 gifts. An export narrowed to one fund
is not marked: posting is per gift, so a gift split across two funds would be locked when only
one fund's share of it was in the file. A payment method narrows by whole gifts, so it may be
marked.

**Closing a period.** `Books_Closed_Through__c` on `Giving_Settings__c`, set on the Accounting
Periods page, reached from the Giving section of Nonprofit Settings (ADR-0020) and gated by
`Manage_Nonprofit_Settings`. It must be at least two days before today and may only move forward; moving it
back or clearing it needs `Override_Posting_Lock` and is logged. Every change is a Setting
Change like any other setting. There is no Setting Definition row naming the key, so the
console's generic save cannot write it past these checks.

**The other ways in.** They all insert or delete gifts through the ordinary triggers, so the
lock holds for each. Gift import checks the close date in the dry run too, where no trigger runs,
so the preview reports the row the commit would refuse; a row matched to an existing gift by
external ID is not refused, because it creates nothing. Import undo keeps a posted gift and a
gift in a closed period, with the reason, the way it keeps a receipted one (ADR-0052). A gift
batch line dated in a closed period fails the post with the lock's message, and the whole batch
rolls back (R-GB5). The inbound gift API answers `gift_not_saved` with the lock's message, an
existing error code, so no caller has to learn a new one.

## Alternatives considered

- **Reuse the gift batch's Posted status.** Rejected: a batch posts when its lines become gifts
  (R-GB4), which is data entry, not the books. A gift from a posted batch has not been exported.
  The words are kept apart on purpose: the gift field is "Posted to Accounting".
- **Lock every field of a posted gift.** Rejected: the acknowledgment, the receipt and the soft
  credits must go on after the books close, and receipting writes a number on the gift.
- **Lock Pending and in-kind gifts in a closed period too.** Rejected: they are in no file, so a
  lock protects nothing the books hold, and it would take away the one clean way to drop an
  unpaid pledge payment from a closed month, deleting it.
- **A checkbox as the flag.** Rejected as a third field: Posted to Accounting is a date and time,
  empty when the gift is not posted, and reports filter on it being empty.
- **The close date as a plain console setting, or a Date row in Core's console.** Rejected: the
  generic save cannot refuse a move backwards without Core knowing a Giving rule, and ADR-0024
  rejected a console switch for lifting a lock.
- **A new error code for the inbound API.** Rejected for now: `gift_not_saved` already means "a
  rule of the organization refused it; resending gives the same answer", which is true here.
- **Mark posted in a background job.** Rejected for now: a cap of 5,000 gifts covers a month for
  the organizations this serves, and a synchronous answer says at once what was marked.
- **A Health Check finding for unposted gifts in a closed period and for holders of the
  override.** Not built: the plan does not ask for either, and a new Core finding naming a Giving
  rule runs against C-29. Recorded as follow-up work.

## Consequences

- **A Pending gift in a closed month that will never be paid is cancelled.** The owner settled
  the open question this ADR raised (ADR-0054): Cancelled is a status, not money,
  so it moves nothing into a closed month, and a Pending gift is no longer written off.
- A contact merge moves gifts to the surviving person without running gift triggers (C-20), so
  a locked gift's donor can change by merge. The person is the same; the books name them by the
  surviving record. Deleting a donor of a locked gift is refused; merge the record instead.
- Import undo leaves a person, household or organization that a locked gift names: the kept
  gift keeps its donor (ADR-0052), and a record named by a locked gift from outside the import
  is refused by the delete guard and journaled as not removed.
- **Known namespace gaps.** Two things assume the deferred namespace stays empty and must change
  when it is set: Connect's `accountingExport` LWC imports the Giving custom permission
  `Post_Gifts` without a prefix, and Connect's `InboundGiftServiceTest` writes Giving's
  protected `Giving_Settings__c` directly to close a period (following `InboundGiftAccessTest`).
- Sample data dated in a closed period cannot be loaded or removed without the override. Load
  and remove it before closing the first period.
- Unposting is one gift at a time on the gift page. A range posted by mistake is left posted or
  unposted gift by gift; a bulk unpost is follow-up work if it is asked for.
- Marking posted on the export page needs Connect. An organization without Connect still has the
  period lock.
