# Giving: Soft Credits, Tributes and Matching Gifts

Scripts for soft credits (automatic household credits and credits entered by hand), tributes and their notification, and linking an employer's matching gift. Setup detail: [Soft credits](../admin-guide/soft-credits.md), [Tributes](../admin-guide/tributes.md), [Matching gifts](../admin-guide/matching-gifts.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded unless a script says otherwise. Work in the **Fundraising** app, where gifts open on the packaged gift page with the **Soft Credits** and **Tribute** panels. A default fund must be set (script T-GIFT-01 in [Giving: gifts, funds and batches](giving-gifts-funds-batches.md)). **Automatic household soft credits** (BarnCRM Settings, **Giving**) is on, as shipped. The Garcia Family in the sample data is Harper, Luis and Diego Garcia.

## T-CRED-01: Automatic Household Soft Credits

**Purpose:** confirm a gift from one household member credits every other current member for the full amount, and follows an amount change.
**Prerequisites:** staff (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Gifts** tab click **New**: **Donor Contact** `Harper Garcia`, **Amount** `500`, today, `Check`, **Status** Received. Save. | The gift opens. |
| 2 | Look at the **Soft Credits** panel. | Luis Garcia and Diego Garcia, each **Household Member**, 500.00, with an **Automatic** badge and no **Remove** button. Harper is not listed. |
| 3 | Open Luis Garcia and refresh after a few seconds. | **Total Soft Credits** includes 500; **Total Giving** did not change. |
| 4 | Back on the gift, edit **Amount** to `750`, save. | The two automatic credits now read 750.00. |

**Cleanup:** keep the gift for T-CRED-02 and T-CRED-03.

## T-CRED-02: Add and Remove a Credit by Hand

**Purpose:** confirm a staff credit is added, refused when incomplete, left alone by recalculation, and removable.
**Prerequisites:** staff; the gift from T-CRED-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Soft Credits** click **Add credit**. | A form: **Person to recognize**, **Why they are recognized** (Solicitor chosen), **Amount**, **Save** (disabled until a person is chosen) and **Cancel**. |
| 2 | Pick **Maria Whitfield**, leave **Amount** empty, click **Save**. | Refused: "Enter an amount or a percent for this recognition. BarnCRM works out the other one from the gift." |
| 3 | Choose **Why they are recognized** `Other` and enter **Amount** `500`, leave **Your own wording** empty, click **Save**. | Refused: "Type your own wording in Custom Role, or choose one of the roles in the list." |
| 4 | Choose `Solicitor` again, **Amount** `500`, click **Save**. | Maria Whitfield, Solicitor, 500.00, with no **Automatic** badge and a **Remove** button. |
| 5 | Edit the gift **Amount** to `600`, save. | The automatic credits read 600.00; Maria's stays 500.00. |
| 6 | Click **Remove** beside Maria's credit. | It is gone. The automatic credits stay. |

**Cleanup:** none.

## T-CRED-03: A Refund Reverses Credits Without Erasing Them

**Purpose:** confirm a refund keeps the original credits and writes negative automatic credits on the refund.
**Prerequisites:** staff; the gift from T-CRED-01 (now 600).

| Step | Action | Expected result |
|---|---|---|
| 1 | Click **Refund or Write Off**, **Refund part or all of this gift**, **How much is going back** `600`, a reason, **Record it**. | "Recorded..." The gift's **Status** is Refunded and the **Refunds and Write-Offs** list shows the negative gift. |
| 2 | Look at **Soft Credits** on the original gift. | Luis and Diego still show 600.00 each, **Automatic**. |
| 3 | Open the refund gift from **Refunds and Write-Offs**. | Its **Soft Credits** show Luis and Diego at -600.00, **Automatic**. |
| 4 | Open Luis Garcia and refresh after a few seconds. | **Total Soft Credits** is back to what it was before T-CRED-01. |

**Cleanup:** none.

## T-CRED-04: Turning Automatic Household Credits Off

**Purpose:** confirm the setting stops new automatic credits and leaves existing ones until their gift is saved.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, untick **Automatic household soft credits**, **Save**. | Saved. |
| 2 | Enter a gift of `40` from **Luis Garcia** on Quick Gift Entry and open it. | **Soft Credits**: "Nobody else is recognized for this gift yet." |
| 3 | Open the T-CRED-01 gift. | Its automatic credits are still there. |
| 4 | Tick **Automatic household soft credits** again and **Save** (undo). Edit the step 2 gift **Amount** to `45`, save. | Harper and Diego Garcia now appear on it as **Household Member**, 45.00, **Automatic**. |

**Cleanup:** leave the setting on.

## T-CRED-05: Record a Tribute and Mark It Sent

**Purpose:** confirm a tribute is created for a gift, the panel summarizes it without the amount, and the notification is marked sent.
**Prerequisites:** staff; a new Received gift of `100` from any donor (for example Founders Consulting Group on Quick Gift Entry).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the gift. Look at the **Tribute** panel. | "This gift was not given in honor of or in memory of anyone." |
| 2 | On the gift's **Tributes** list, click **New**. **Gift** is the gift above; set **Type** `In memory of`, **Honoree Name** `Rosa Testname`, **Notification Recipient Contact** `Harper Garcia`, **Message** `With love from the Tuesday reading group`. Save. | Saved. |
| 3 | Open the gift again. | The **Tributes** list shows the new tribute. **Tribute** field links to it. Panel: "In memory of Rosa Testname, Notify Harper Garcia", "Not sent yet", the message, and **Mark notification sent**. No amount is shown. |
| 4 | Click **Mark notification sent**. | The panel says "Notification sent" with today's date; the button is gone. |
| 5 | Open the tribute. | **Notification Sent** ticked, **Notification Sent Date** today. |
| 6 | On the **Tributes** tab, open list view **Notifications to Send**. | This tribute is not listed. |

**Cleanup:** none.

## T-CRED-06: Tribute Rules

**Purpose:** confirm the honoree, one-tribute, deceased-recipient and no-recipient rules.
**Prerequisites:** admin; the gift from T-CRED-05 and a second new gift of `50` without a tribute. A sample contact you can mark deceased (for example Diego Garcia).

| Step | Action | Expected result |
|---|---|---|
| 1 | **Tributes**, **New**: **Gift** the second gift, **Type** `In honor of`, no honoree. Save. | Refused: "Say who this gift honors: type the name the donor gave, or choose a person already in your database." |
| 2 | Choose **Honoree Contact** `Luis Garcia` and **Honoree Account** `Bayview Hardware`. Save. | Refused: "Choose one honoree record, not two." Clear **Honoree Account** and **Honoree Contact**, type **Honoree Name** `Rosa Testname`, and save. Saved. |
| 3 | **New** tribute on the T-CRED-05 gift, **Type** `In honor of`, **Honoree Name** `Second Name`. Save. | Refused: "This gift already has a tribute. Edit the one that is there, or split the gift." |
| 4 | Open **Diego Garcia**, tick **Deceased**, save. | Saved. |
| 5 | Edit the second gift's tribute: **Type** `In memory of`, **Honoree Contact** `Diego Garcia`, **Notification Recipient Contact** `Diego Garcia`. Save. | Refused: "This gift is in memory of the person you have chosen to notify. Choose a family member or friend as the notification recipient." |
| 6 | Clear **Notification Recipient Contact** and save. Open the second gift. | Panel shows the tribute and, instead of the button: "Nobody is recorded as the person to notify, so there is no letter to send. Add a notification recipient, or a name and address, on the tribute." |

**Cleanup:** untick **Deceased** on Diego Garcia.

## T-CRED-07: Link a Matching Gift

**Purpose:** confirm linking an organization's gift to an employee's gift fills both sides and soft credits the employee.
**Prerequisites:** staff. Two new Received gifts: one from **Harper Garcia**, `500`, dated last month (the employee's gift), and one from **Founders Consulting Group** (**Donor Account**), `500`, today (the match). Leave **Employer** empty on Harper here.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Harper's gift. | **Matched Gift** is not shown (it shows only once linked, or on an organization's gift). |
| 2 | Open the Founders Consulting Group gift. Edit **Matched Gift** to Harper's gift, save. | Saved. |
| 3 | Look at its **Soft Credits**. | Harper Garcia, **Matched Donor**, 500.00, **Automatic**. |
| 4 | Open Harper's gift. | **Matched Gift** now names the Founders Consulting Group gift. |
| 5 | Open Harper Garcia and refresh after a few seconds. | **Total Giving** counts her 500 once; **Total Soft Credits** includes the 500 match. |

**Cleanup:** keep both gifts for T-CRED-08 and T-CRED-09.

## T-CRED-08: Matching Gift Refusals

**Purpose:** confirm links that cannot be right are refused.
**Prerequisites:** admin; the gifts from T-CRED-07, plus a new gift of `200` from **Luis Garcia** and a new gift of `300` from **The Summit Foundation**.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the Summit Foundation gift, set **Matched Gift** to the Summit Foundation gift itself, save. | Refused: "A gift cannot match itself. Choose the other gift in the pair." |
| 2 | Set **Matched Gift** to the T-CRED-07 Founders Consulting Group gift (an organization's gift), save. | Refused: "The gift being matched has to come from a person. Choose the employee's own gift, not another organization's." |
| 3 | On the Summit Foundation gift, set **Matched Gift** to Harper's gift (already linked). | Refused: "One of these gifts is already linked to a different gift. Unlink it first, then link it here." |
| 4 | Refund Luis's gift in full (**Refund or Write Off**). Then on the Summit Foundation gift set **Matched Gift** to Luis's gift. | Refused: "A gift that has been refunded or written off cannot be part of a matching gift pair..." |
| 5 | In the Fundraising app open Diego Garcia, **Edit**, set **Employer** (in the **Person** section) to **Bayview Hardware** and save. Enter a gift from Diego, then link the Summit Foundation gift to it. | Refused: "That gift is from someone whose employer is a different organization. Check the employer on the person's record, or clear it if you are not sure." |

**Cleanup:** clear **Employer** on Diego Garcia.

## T-CRED-09: Refunding a Match, and Unlinking

**Purpose:** confirm refunding the employer's gift reverses the employee's recognition, and unlinking removes the credits.
**Prerequisites:** staff; the linked pair from T-CRED-07.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the Founders Consulting Group gift, **Refund or Write Off**, refund `200`. | Recorded. The original gift still shows Harper's **Matched Donor** credit at 500.00; both gifts still name each other. |
| 2 | Open the refund gift. | **Soft Credits**: Harper Garcia, **Matched Donor**, -200.00. |
| 3 | Open Harper Garcia and refresh. | **Total Soft Credits** counts 300 for this match. |
| 4 | On the Founders Consulting Group gift, clear **Matched Gift**, save (undo the link). | The **Matched Donor** credit is gone from this gift and the -200.00 credit is gone from the refund. Harper's gift no longer shows **Matched Gift**. |

**Cleanup:** none.

## T-CRED-10: Read-Only Access to Credits and Tributes

**Purpose:** confirm a read-only user sees credits and tributes but cannot change them.
**Prerequisites:** read-only; the gifts from T-CRED-01 and T-CRED-05.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the T-CRED-01 gift. | **Soft Credits** lists the credits; **Add credit** is disabled and no **Remove** buttons show. |
| 2 | Open the second gift from T-CRED-06 (tribute not sent). | The **Tribute** panel shows the summary; no **Mark notification sent** button. |
| 3 | Open the **Tributes** tab in the Fundraising app. | No **New** button. |

**Cleanup:** none.
