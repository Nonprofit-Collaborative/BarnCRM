# ADR-0211: Online donation pages: an appeal's public page with a Forms form, handing off to the org's own Stripe or PayPal hosted checkout, with the gift written from the payment's outcome

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.15 (G-34), D-157 (research proposal 3, the online
donation page), D-177 (moved to 1.15), D-190 (payments through the org's own Stripe and PayPal;
payment processing stays out of Core). Builds on ADR-0017 (cross-package mechanisms by name),
ADR-0175 (the Forms seam `FormAttachmentExtension`), ADR-0184 (a guest only stores, a staff job
processes), ADR-0190 (public pages through `PublicPageExtension`) and ADR-0201
`0201-payments-module.md` (the Payments seam).

## Context

G-34 asks for an online donation page per appeal, built on the Forms engine, that hands the
donor to the organization's own Stripe or PayPal checkout and writes the gift back through the
Payments receiver, with BarnCRM holding no money. The pieces exist: Forms serves a module's
public page for a record with its form (ADR-0190), Forms stores a guest's answers and processes
them later as staff (ADR-0184), and Payments starts a hosted checkout and tells a named listener
how the payment ended (`0201-payments-module.md`, decision 8). What is missing is the hand-off:
the checkout must start while the donor is still on the page, and the gift must end up right
whichever comes first, the form's processing or the processor's report.

A Payments callout must come before any write in the same transaction, and a public page's
guest may only store a submission, never a gift.

## Decision

1. **The appeal publishes the page.** Appeal (`Appeal__c`) gains Donation Page
   (`Donation_Page__c`, off) and Donation Form Key (`Donation_Form_Key__c`, Text(18), the Forms
   form by record identifier, as Event's Registration Form Key, ADR-0014). Giving's
   `GivingDonationPage` implements Core's `PublicPageExtension` (kind `appeals`) for an active
   appeal with Donation Page on, and `FormAttachmentExtension` for the form. Core lists it in
   `PublicPageExtensions.EXTENSION_CLASSES` and `FormAttachmentExtensions.EXTENSION_CLASSES`.
   The page shows the appeal's name, description and, when a goal is set, the goal; never a
   donor, a gift or a total. Without Forms, nothing serves it; without Payments, the page says
   giving online is not open.
2. **A new Core seam, `PublicCheckoutExtension`**, which a `PublicPageExtension` may also
   implement: `startCheckout(recordId, answers, returnUrl)` returns `{ paymentId, checkoutUrl }`,
   or null when the record takes no payment. `PublicPageExtensions.startCheckout` finds the
   extension that handles the record's type. Core names no payment: the module that publishes
   the page decides whether it charges and asks Payments by name.
3. **The checkout starts before the submission is stored.** `FormIntakeService.submit` asks
   `PublicPageExtensions.startCheckout` after the answers pass every check and before it inserts
   the Form Submission, so the Payments callout comes before any write. The payment's identifier
   is kept in the stored answers under the reserved key `_payment`, and the receipt carries the
   checkout address; `formPublic` sends the browser there. A failed checkout stores nothing and
   answers Failed, so the donor can try again. The processor returns the donor to
   `<site>/FormsPublic?record=<appeal>&payment=done` (or `cancelled`), which shows a short
   notice above the page.
4. **The amount is the answer `amount`.** A donation form must have a Number question with the
   key `amount` (or a choice question whose values are amounts); the answers `email`, `firstName`
   and `lastName`, when present, prefill the processor's page. Payments refuses an amount of zero
   or less. The currency and processor are the Payments defaults.
5. **The gift is written by whichever side comes second.** Giving's `received()` (staff
   processing, ADR-0184) writes the gift for the person Forms matched: Received when Payments
   already reports Paid, Cancelled when the payment was Cancelled, otherwise Pending, with
   Payment Reference set to the payment's identifier, Appeal set, Type Card (Stripe) or Other
   (PayPal). The listener `GivingDonationPayments` (`paymentChanged`) finds the gift by Payment
   Reference and sets Received on Paid (Gift Date the paid date), Refunded on Refunded, Cancelled
   on Cancelled, and leaves Pending on Failed; when no gift exists yet it does nothing, since
   processing writes it with the status it then reads. Both are idempotent.
6. **Nothing new to switch on.** A donation page exists only when staff tick Donation Page on an
   appeal and name a form, so existing behaviour is unchanged and no setting is added. Payments'
   own keys, mode and Test/Live switch govern the money.

## Alternatives considered

- **A Giving REST endpoint or Site page of its own.** Rejected: Forms already serves public
  pages with spam checks, signed tickets and staff processing (ADR-0184, ADR-0190); a second
  public path would repeat all of it.
- **Starting the checkout after the submission is processed** (an emailed payment link).
  Rejected: the donor would leave the page without paying, and the callout cannot follow the
  insert in the guest's transaction.
- **A Form Submission field for the payment.** Rejected for now: the reserved answer key needs
  no new field on Forms and travels to the module in `FormSubmissionReceipt.answers`. It can
  become a field later without changing the seam.
- **Writing the gift in the listener only.** Rejected: the listener does not know the person,
  who is matched only when Forms processes the submission.

## Consequences

- A donor gives on the organization's own Salesforce Site page and pays on Stripe's or PayPal's
  page; BarnCRM and Salesforce never see card details.
- An abandoned checkout leaves a submission whose gift is Pending until Payments cancels the
  payment, then Cancelled; staff can delete Cancelled gifts or keep them as a record.
- Recurring online gifts are not offered: Payments has no subscriptions yet.
- The stored answers show `_payment` beside the donor's answers on the Form Submission.
