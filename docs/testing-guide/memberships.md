# Memberships

Scripts for the optional BarnCRM Memberships module: levels and access, dates filled on save, renewals by hand, from Fundraising gifts and recurring gifts, and online through Payments, lapse handling and reminders, the member directory portal, the Memberships Essentials kit and erasure. Setup detail: [Memberships](../admin-guide/memberships.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Memberships deployed and the module turned on in Module Manager. Fundraising (T-MEM-04), Payments in test mode (T-MEM-06) and Portal Builder (T-MEM-07) are needed only for their scripts. To run the morning step at once: **Nightly Jobs**, **Memberships**, **Run Now**.

## T-MEM-01: Levels, Benefits and Access

**Purpose:** confirm levels and benefits are set up by admins and read by staff.
**Prerequisites:** an admin, a Team Member and a Read Only user.
**Steps:** 1. As admin, add a level Family Gold, Dues 120, Term Months 12, Grace Days 30, with two benefits. 2. As Team Member, open it. 3. As Read Only, open the Memberships tab.
**Expected:** 1. Saved; benefits listed on the level in sort order. 2. Read only; no New on levels. 3. Memberships readable, no New.

## T-MEM-02: Dates Filled on Save

**Purpose:** confirm a new membership fills its dues and dates (R-MEM1, R-MEM2).
**Prerequisites:** the level from T-MEM-01, a contact.
**Steps:** 1. As Team Member, add a membership with only the level and the contact. 2. Add one with neither contact nor household. 3. Add a level with Term Months 0 and a membership at it.
**Expected:** 1. Status Current, Dues 120, Start today, End a year later less a day, Member Since today, Origin New, Source Staff. 2. Refused: choose the member. 3. No End Date.

## T-MEM-03: Renewing by Hand

**Purpose:** confirm Renew adds the next term (R-MEM3).
**Prerequisites:** the membership from T-MEM-02 step 1.
**Steps:** 1. Click Renew, keep the level, confirm. 2. On a Lapsed membership, click Renew.
**Expected:** 1. A new Current term starting the day after the old end, Origin Renewal, same Member Since; the old one Renewed. 2. The new term starts today, Origin Rejoin.

## T-MEM-04: Renewals From Gifts and Recurring Gifts

**Purpose:** confirm gifts to a level's fund pay memberships (R-MEM6, R-MEM4).
**Prerequisites:** Fundraising installed; a fund Memberships; the level's Fund ID set to it; a second level Family Silver at 60 on the same fund.
**Steps:** 1. Enter a received gift of 100 from a contact with no membership, allocated to the fund, and run the step. 2. Run the step again. 3. Enter a gift of 30 to the fund and run it. 4. Add an Active monthly recurring gift of 10 on the fund for another contact, receive one payment, and run the step. 5. Set that membership's End Date to yesterday and run the step.
**Expected:** 1. A New Family Silver membership, Source Gift, Gift ID set, starting on the gift date. 2. Nothing new: a gift is used once. 3. Nothing: it meets no level. 4. A Family Gold membership (10 a month is 120 a year), Source Recurring Gift, Recurring Gift ID set. 5. It is Renewed and a new Current term follows, instead of Grace.

## T-MEM-05: Lapse Handling and Reminders

**Purpose:** confirm Grace, Lapsed and one reminder per term (R-MEM4, R-MEM5).
**Prerequisites:** two Current memberships: one with End Date 10 days ago, one 40 days ago; a third ending in 20 days whose contact has an email address. Reminders on in BarnCRM Settings, Memberships.
**Steps:** 1. Run the step. 2. Run it again.
**Expected:** 1. The first is Grace, the second Lapsed; the third's contact gets one reminder and Reminded For is its end date. 2. No second reminder.

## T-MEM-06: Dues Paid Online

**Purpose:** confirm a payment link and a membership dated on payment (R-MEM7, PAY-02).
**Prerequisites:** Payments in Stripe test mode with processing scheduled; a Pending membership whose contact has your email address.
**Steps:** 1. Click Email Payment Link. 2. Open the email's link and pay with Stripe's test card 4242 4242 4242 4242. 3. Wait for processing (up to 15 minutes). 4. Email a link for the now Current membership and pay it. 5. Refund the second payment in Stripe and wait for processing.
**Expected:** 1. Email received; Payment Link set on the membership. 3. The membership is Current from the payment date, Payment ID set, Amount Paid 120. 4. A Renewal term carrying the new payment. 5. That term is Cancelled.

## T-MEM-07: Member Directory Portal

**Purpose:** confirm the member template and its opt-in directory (R-MEM9, PB-09).
**Prerequisites:** Portal Builder set up; a portal with the member template; two members with Current memberships and email addresses.
**Steps:** 1. Sign in as the first member, open My Directory Listing, opt in with a location and bio, save. 2. Sign in as the second member and open Member Directory; type part of the first member's name in the search box. 3. The first member opts out again.
**Expected:** 1. Saved. 2. Only opted-in current members show, with name, level, location and bio, and no email, phone or address; the search narrows the list. 3. The first member no longer shows.

## T-MEM-08: Memberships Essentials Kit

**Purpose:** confirm the kit copies Essentials levels and memberships (G-22d).
**Prerequisites:** a test org with Memberships Essentials deployed and a few products with a tier and memberships, one ended.
**Steps:** 1. Open the Migration Assistant and run the Memberships Essentials kit. 2. Open the copied levels and memberships.
**Expected:** 2. One level per product with a tier; each membership linked to its level, account and primary contact, with its dates, Source Import; the ended one Lapsed. Essentials records unchanged.

## T-MEM-09: Erasure

**Purpose:** confirm erasing a person clears their listing (R-MEM8).
**Prerequisites:** a member listed in the directory with notes on the membership.
**Steps:** 1. Erase the person.
**Expected:** 1. The membership stays; Listed in Directory off, Directory Location, Directory Bio and Notes blank. A member certification of the person stays, with Notes blank and each continuing credit's Activity blank (R-MEM13).

## T-MEM-10: Certifications and Continuing Credits

**Purpose:** confirm granting, credits and renewing a certification (G-22e, R-MEM10, R-MEM11).
**Prerequisites:** a Memberships Admin and a Memberships Staff user; a contact.
**Steps:** 1. As the admin, create a Certification with Credits Required 10 and Valid Months 24. 2. As staff, create a Member Certification for the contact. 3. Press Grant. 4. Add a Continuing Credit of 6. 5. Add another of 4, then press Renew. 6. Press Revoke, then Grant.
**Expected:** 2. Status Pending; the panel shows Grant only. 3. Active, Earned On today, Expires On 24 months on. 4. Credits toward renewal 6 of 10; no Renew, the panel says 6 earned, 10 needed. 5. Expires On moves 24 months past the old date; both credits Used; credits toward renewal 0 of 10. 6. Revoked, then Active again. A Memberships Read Only user sees the panel with no buttons.

## T-MEM-12: Sample Data

**Purpose:** confirm the Memberships sample data loads for the sample people and takes away only itself.
**Prerequisites:** an admin; Core's sample data not yet loaded; one level and one membership of your own.
**Steps:** 1. **BarnCRM Settings**, **Load Sample Data**, wait for it to finish. 2. Open **Memberships**, list the memberships and the levels. 3. Open Harper Garcia's membership. 4. **Remove Sample Data**.
**Expected:** 1. The Sample Data card shows a **Memberships** count of `14`. 2. Five sample levels with benefits; memberships Current, Grace (one), Lapsed (two), Pending, Cancelled and Renewed, three of them due within a month, and one Lifetime with no end date. 3. A Current Family Member term that points to a Renewed earlier term. 4. Every sample level and membership is gone; your own level and membership stay.
**Cleanup:** None.

## T-MEM-11: Certification Expiry

**Purpose:** confirm the nightly run expires certifications (R-MEM12).
**Prerequisites:** an Active member certification with Expires On set to yesterday (as an admin).
**Steps:** 1. Wait for the next nightly run. 2. Open the member certification.
**Expected:** 2. Status Expired. Renew is offered again once the credits are in.

## T-MEM-13: Memberships Home

**Purpose:** confirm Memberships Home shows the figures and lists, the first-run steps and New Membership only for creators (Module Home pattern).
**Prerequisites:** a Memberships Admin and a Memberships Read Only user; an org with no levels or memberships for step 1.
**Steps:** 1. As the admin, open **BarnCRM Members and Partners**. 2. Click **New Membership Level**, save a level `Home Test` (12 months), reload. 3. Add three memberships at that level: one Current ending in 10 days, one Current ending in 90 days, one Grace. Reload. 4. Renew the one ending in 10 days, reload. 5. Click **Active Members**. 6. Narrow the window to phone width. 7. As the Read Only user, open **Memberships Home**.
**Expected:** 1. **Memberships Home** is the first tab and shows **Set Up a Membership Level** with **New Membership Level**; no figures. 2. **Add Your First Member** with **New Membership**. 3. **Active Members** 3, **Expiring in 30 Days** 1 (listed under **Expiring Soon** with its End Date and a green **Current** badge), **In Grace Period** 1, **Renewals, Last 30 Days** 0 with **No renewals in the last 30 days** and its next step. 4. **Renewals, Last 30 Days** 1, and the new term is listed under **Recent Renewals** with its Start Date; the renewed membership has left **Expiring Soon**. 5. The Memberships list opens. 6. Two figures per row; table rows stack with their column names. 7. The same figures and lists, no **New Membership**.
**Cleanup:** delete the `Home Test` memberships and level.

## T-MEM-14: The Org's Date for Every User

**Purpose:** confirm renewal and expiry use the organization's date, not the running user's (D-219, OD-15).
**Prerequisites:** a Team Member whose time zone (Settings, Personal Information) is at least 11 hours from the org's (**Setup**, **Company Information**), for example Pacific/Kiritimati when the org is in America; run it when that user's date differs from the org's (the org's late evening for a zone ahead). Two Current memberships: one ending on the org's today, one ending the org's yesterday; one Lapsed membership.
**Steps:** 1. Run the Memberships step as that user (**Nightly Jobs**, **Memberships**, **Run Now**). 2. As that user, renew the Lapsed membership. 3. As that user, add a membership with only the level and a contact.
**Expected:** 1. The one ending the org's today stays Current; the one ending the org's yesterday moves to Grace. 2. The new term starts on the org's today. 3. Start Date is the org's today and End Date is a year later less a day.
**Cleanup:** Put the user's time zone back.
