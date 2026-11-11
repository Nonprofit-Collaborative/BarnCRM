# Memberships

Scripts for the optional BarnCRM Memberships module: levels and access, dates filled on save, renewals by hand, from Giving gifts and recurring gifts, and online through Payments, lapse handling and reminders, the member directory portal, the Memberships Essentials kit and erasure. Setup detail: [Memberships](../admin-guide/memberships.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Memberships deployed and the module turned on in Module Manager. Giving (T-MEM-04), Payments in test mode (T-MEM-06) and Portal Builder (T-MEM-07) are needed only for their scripts. To run the morning step at once: **Nightly Jobs**, **Memberships**, **Run Now**.

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
**Prerequisites:** Giving installed; a fund Memberships; the level's Giving Fund ID set to it; a second level Family Silver at 60 on the same fund.
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
**Expected:** 1. The membership stays; Listed in Directory off, Directory Location, Directory Bio and Notes blank.
