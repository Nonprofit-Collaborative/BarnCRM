# ADR-NEXT: Event Management: paid registration through Payments, session proposal scoring, badge overrides and per-session ratings

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.5 (EV-20, EV-21, EV-26, EV-27), D-190 (payments through the
org's own Stripe and PayPal for events; session proposal management with multi-user matrix
scoring; the Midwest Dreamin' and Whova comparison), Section 5.12. Builds on ADR-0177 (events
module), ADR-0180 (call for speakers), ADR-0182 (registrations), ADR-0184 (a guest only stores, a
staff job processes), ADR-0185 (portal actions), ADR-0188 (post-event survey), ADR-0190 (public
event pages), ADR-0017 (cross-package mechanisms by name) and ADR-NEXT
`NEXT-payments-module.md` (the payment seam).

## Context

Events has priced tickets and promo codes and records an Amount Owed, but takes no payment: the
public page shows a "pay at the door" note. Payments (PAY-01) now offers a hosted checkout and a
listener seam by name, so Events can charge without depending on it. A public registration is
stored by the Site guest and processed later by a staff job (ADR-0184), and a checkout is a
callout, which Salesforce allows only before any write in a transaction.

The call for speakers (EV-06) takes one 1 to 5 score per reviewer and one applicant per proposal.
A community conference needs co-presenters, assigned reviewers, weighted criteria, an optional
blind review and a side-by-side view. Badges print the person's own name and account, which is
not always what an attendee wants on a badge. Sessions have no feedback of their own.

## Decision

### Paid registration (EV-20)

1. **Optional and off.** The Events setting Take payment online (`Online_Payments__c`, default
   false) turns it on. It does anything only when Payments is installed: Events builds
   `PaymentsApi` by name (`NamespaceUtil.build`), so Events never depends on Payments.
2. **A form registration with something to pay waits for payment.** When the setting is on and a
   form (public page) registration owes more than zero, it is saved with Status Pending Payment
   and Payment Status Unpaid. Its attendees are Registered, so they hold their seats while the
   payer pays (R-EAT1); nobody else can take them.
3. **The checkout starts in a job of its own.** The form registration is written in the
   processing job's transaction, where no callout may follow, so it enqueues
   `EventCheckoutJob` (a Queueable allowing callouts) once per transaction. The job takes one
   registration that is Pending Payment and Unpaid, asks Payments for a checkout (amount owed,
   the registrant as payer, the registration as source, listener `EventPaymentListener`), saves
   the payment's identifier and checkout address on the registration (Payment Status Link Sent)
   and emails the registrant the template named in Events settings (`Payment_Link_Template__c`,
   shipped `BarnCRM_Event_Payment_Link`). Payments allows one checkout per transaction (callout,
   then write), so the job chains itself while more wait. The return addresses are the event's
   public page on the Site the registration form uses (`FormsPublic?record=<event>`), else the
   org's own address.
4. **Staff and the portal send the same link.** Send Payment Link on the Registrations tab starts a
   checkout for any registration that owes money and is not paid (a staff registration stays
   Registered; it does not wait for payment). The portal action `Events.SendPaymentLink` emails the
   person's own current link again; the portal's integration user starts no checkout and queues
   no job. Payment links are never shown on a public page.
5. **Confirmed on payment, recorded on every change.** `EventPaymentListener` (Callable, built by
   name by Payments) hears `paymentChanged` for the registration's current payment only (the
   registration's Payment Key):
   - Paid: Payment Status Paid, Amount Paid set, a Pending Payment registration becomes
     Registered.
   - Failed: Payment Status Failed; the registration keeps waiting (the payer may retry).
   - Cancelled (the checkout expired or was abandoned): Payment Status Cancelled; a registration
     that was waiting for payment is cancelled and its seats freed.
   - Refunded in part: Payment Status Partly Refunded and Amount Paid lowered.
   - Refunded in full: Payment Status Refunded, Amount Paid zero, and the registration cancelled.
   The listener is safe to call twice with the same status. A payment that arrives after its
   registration was cancelled is recorded and the registration stays cancelled, for staff to
   refund or register again. A checkout the job cannot start marks the payment Failed and is
   logged, so one registration never stops the queue.
6. **BarnCRM issues no refund.** Refunds are made in the Stripe or PayPal dashboard; the
   processor's event records them here. Cancelling a paid registration says so.
7. **Health Check** warns when Take payment online is on and Payments is not installed or its
   keys are not entered.

### Session proposals and matrix scoring (EV-21)

8. **Co-presenters.** `Proposal_Presenter__c` (detail of the proposal) names up to 5 more Core
   people with a role (Speaker, Moderator or Panelist). Accepting a proposal makes the applicant
   and every presenter a speaker at the event.
9. **Assigned reviewers.** An assignment is a Speaker Review with a reviewer and no score yet;
   only scored reviews count in Reviews, Total Score and the averages. The tab assigns chosen
   users to chosen proposals, never twice, and shows each reviewer their own assignments.
10. **Weighted criteria per event.** `Event__c.Review_Criteria__c` holds a JSON list of up to 10
    criteria (`{ "label": "Relevance", "weight": 2 }`, weight 1 to 10). With criteria, a reviewer
    scores each from 1 to 5; the review keeps them as JSON (`Criteria_Scores__c`), its Weighted
    Score is the weight-averaged score to two decimals and its Score the nearest whole number.
    Without criteria a review is one 1 to 5 score, as before, and its Weighted Score equals it.
    The rule lives in the framework-free `eventApplicationsModel` and is repeated in Apex, tested
    against the same cases (the `EventPricing` pattern).
11. **Matrix and compare.** The proposal's Weighted Average (roll-up and formula) ranks the list;
    the Scoring Matrix shows each proposal's average per criterion, total, average and reviews,
    and Compare puts up to 4 proposals side by side, all built in the browser.
12. **Blind review** (`Event__c.Blind_Review__c`, default false) hides applicants', presenters' and
    reviewers' names on the Applications tab until a proposal is decided. It is a working aid,
    not a security boundary: the records stay readable to those with access.

### Badge overrides (EV-26)

13. `Event_Attendee__c` gains Badge Name, Badge Title and Badge Company. Badges, sign-in sheets and
    Check-In use them when set and fall back to the attendee's name and the person's account.

### Per-session ratings (EV-27)

14. **One rating form per event.** `Event__c.Session_Rating_Form_Key__c` names a published public
    Forms form (by record identifier, as text) whose `rating` answer (1 to 5) and optional
    `comment` answer are kept per session. Each session's QR code opens that form tied to the
    session (`FormCatalogExtensions.publicLink(form, session)`), printed from the Agenda tab in
    the browser. Without Forms there is no code.
15. **Ratings are anonymous** `Session_Rating__c` records (detail of the session, no person), one
    per submission; roll-ups give the session's Ratings and Average Rating, and the Speakers tab
    shows each speaker's average over the sessions they speak in, computed on read.

## Alternatives considered

- **Starting the checkout on the public page right after submit.** Rejected: the guest only
  stores (ADR-0184), and the page would wait on a callout before the registration exists.
- **A per-registration Queueable.** Rejected: a processing run of many submissions would exceed
  the one-enqueue limit of an asynchronous transaction.
- **Holding no seats while unpaid.** Rejected: a paying registrant could lose their seat between
  registering and paying; an abandoned checkout frees them after Payments' 2 days.
- **A separate reviewer assignment object.** Rejected: an unscored review is the assignment, and
  the existing roll-ups only gain a filter.
- **Criteria as records.** Rejected for now: JSON on the event is portable (Section 9.9) and needs
  no object; criteria are few and edited together.
- **Session ratings in the post-event survey.** Rejected: ratings are taken during the event,
  at the session's door, by anyone in the room.

## Consequences

- An org taking payment online needs Payments set up (keys, Site, processing scheduled) and a
  public registration form; up to 15 minutes pass between paying and the registration reading
  Registered.
- `EventPaymentListener` is a permanent name once released: Payments stores it on each payment.
- Changing an event's criteria after reviews exist leaves those reviews' scores as they were.
