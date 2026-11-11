# Giving: Donor Scoring

Scripts for the recency, frequency and monetary scores, the cutoff settings, the segment and the two score-based donor segment templates. Setup detail: [Donor scoring](../admin-guide/donor-scoring.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Giving deployed and sample data loaded.

## T-RFM-01: A Donor Is Scored From Their Gifts

**Purpose:** Confirm a donor's scores and segment follow their gifts and update in the save that changes them.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)). A person with no gifts, here called Pat.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open Pat. | In **Giving**, **Giving Pattern** is empty; in **Giving Details**, **Donor Score** and the three scores are empty. |
| 2 | Add one gift of 100 dated today. | Saved. |
| 3 | Refresh Pat. | **Days Since Last Gift** is 0, **Recent Gift Count** 1, **Recent Giving** 100, **Recency Score** 5, **Frequency Score** 2, **Amount Score** 2, **Donor Score** 9 and **Giving Pattern** is Promising. |
| 4 | Add two more gifts of 100 dated today. | Saved. |
| 5 | Refresh Pat. | **Recent Gift Count** 3, **Recent Giving** 300, **Frequency Score** 3, **Amount Score** 3, **Giving Pattern** Loyal. |
| 6 | Add a gift of 5,000 dated three years ago. | Saved. |
| 7 | Refresh Pat. | **Recent Gift Count** and **Recent Giving** are unchanged: a gift older than 730 days is outside the window. |

**Cleanup:** Delete the gifts.

## T-RFM-02: Cutoffs Are Org-Wide Settings With Defaults

**Purpose:** Confirm the three cutoffs show defaults, change the scores, and fall back when mistyped.
**Prerequisites:** admin; Pat from T-RFM-01 with three gifts of 100.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Giving**, open **Donor Levels and Scores**. | Three cutoff settings show `90,180,365,730`, `6,4,2,1` and `5000,1000,250,50`. None is blank. |
| 2 | Set **Donor Score Monetary Amount** to `200,100,50,10` and save. | Saved. |
| 3 | Open **Nightly Jobs** and select **Run now** for the Donor Levels job; refresh Pat after a minute. | Pat's **Amount Score** is 5 (300 reaches 200). **Giving Pattern** is still Loyal (frequency is 3). |
| 4 | Set the same setting to `abc` and save, then run the job again. | Saved. Pat's **Amount Score** is back to 3, as with the default. |

**Cleanup:** Put the default `5000,1000,250,50` back.

## T-RFM-03: Score-Based Donor Segments and Find

**Purpose:** Confirm the Champions and Slipping Donors templates and Find use the scores.
**Prerequisites:** admin or Giving staff with Find; at least one Champion and one At Risk donor.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Donor Segments**. | Seven starter templates, including **Champions** and **Slipping Donors**. |
| 2 | Choose **Champions**, **People**, then **Save as Segment**, and open its list. | Only donors whose segment is Champion, highest **Donor Score** first. |
| 3 | In **Find**, choose **Contacts**, add **Giving Pattern** and **Days Since Last Gift** as columns and filter **Giving Pattern** equals At Risk. | The At Risk donors list with both columns. |
| 4 | Open **Automation** and turn off **Donor score assignment** for contacts. Change a donor's gift and open them. | Their scores do not change. Turn the switch back on. |

**Cleanup:** Delete the saved segment.

## T-RFM-04: Wealth Screening Fields and Import Template

**Purpose:** Confirm the five wealth screening fields, who sees them, and that the Wealth Screening template updates people found by email and adds nobody (G-32).
**Prerequisites:** admin; staff (Giving Staff); a read-only user with Giving Read Only; sample data loaded. A CSV with headings **Email**, **Capacity Rating**, **Affinity Rating**, **Screening Score**, **Screening Date**, **Screening Source** and two rows: Luis Garcia's email with `250,000 to 499,999`, `High`, `87.5`, today, `Example Screening Co`; and `nobody@example.invalid` with any values.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open BarnCRM's import, upload the CSV and choose the **Wealth Screening** template. | The columns map to the five fields by their headings, and Email is the field rows are found by. |
| 2 | Run it. | One row updated (Luis Garcia). The `nobody@example.invalid` row is reported as matching nobody; no person is created. |
| 3 | As staff, open Luis Garcia, **Details** tab. | **Giving Details** shows **Capacity Rating** `250,000 to 499,999`, **Affinity Rating** `High`, **Screening Score** `87.50`, **Screening Date** today and **Screening Source** `Example Screening Co`. **Donor Score** is unchanged. |
| 4 | As staff, edit **Affinity Rating** to `Medium` and save. | Saved. |
| 5 | As the read-only user, open Luis Garcia. | None of the five fields shows. |
| 6 | In **Find**, choose **Contacts** and filter **Screening Score** greater than `50`. | Luis Garcia is listed. |

**Cleanup:** clear the five fields on Luis Garcia.
