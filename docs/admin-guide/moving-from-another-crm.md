# Moving From Another CRM

**Package:** Giving | **Release:** 1.9 (MIG-07)

## What It Does

If your donors and gifts are in DonorPerfect, Bloomerang, Little Green Light, Neon CRM, CiviCRM
or Raiser's Edge NXT, BarnCRM Giving ships a ready-made import template for each one's gift
export. You export the gifts with each donor's name, email and address from the other system,
and load the file through the **Import** tab like any other file, with a preview first and an
undo afterwards. Each donor is found by email address, or created when nobody has it; each gift
keeps the other system's gift number, so loading the same file again matches the gifts already
loaded instead of making them twice.

The templates only name columns. BarnCRM never connects to the other system.

| Template | Export from the other system | Fund from | Appeal from |
|---|---|---|---|
| **DonorPerfect: Gifts** | A gift listing export with donor name, email and address fields: `FIRST_NAME`, `LAST_NAME`, `EMAIL`, `ADDRESS`, `CITY`, `STATE`, `ZIP`, `COUNTRY`, `GIFT_ID`, `GIFT_DATE`, `AMOUNT`, `GIFT_TYPE`, `REFERENCE`, `SOLICIT_CODE`, `GL_CODE` | `GL_CODE` | `SOLICIT_CODE` |
| **Bloomerang: Transactions** | A transactions report with the constituent's primary email and address: `First Name`, `Last Name`, `Primary Email Address`, `Primary Street`, `Primary City`, `Primary State`, `Primary ZIP Code`, `Primary Country`, `Transaction Number`, `Date`, `Amount`, `Method`, `Check Number`, `Appeal`, `Fund` | `Fund` | `Appeal` |
| **Little Green Light: Gifts** | A gifts export with constituent fields: `First Name`, `Last Name`, `Email`, `Street`, `City`, `State`, `Postal Code`, `Country`, `Gift ID`, `Gift Date`, `Gift Amount`, `Payment Type`, `Check Number`, `Appeal`, `Fund` | `Fund` | `Appeal` |
| **Neon CRM: Donations** | A donation search export with account fields: `First Name`, `Last Name`, `Email 1`, `Address Line 1`, `City`, `State/Province`, `Zip Code`, `Country`, `Donation ID`, `Donation Date`, `Donation Amount`, `Tender Type`, `Check Number`, `Campaign Name`, `Fund` | `Fund` | `Campaign Name` |
| **CiviCRM: Contributions** | Contributions, Find Contributions, Export, with contact fields: `First Name`, `Last Name`, `Email`, `Street Address`, `City`, `State`, `Postal Code`, `Country`, `Contribution ID`, `Date Received`, `Total Amount`, `Payment Method`, `Check Number`, `Campaign Title`, `Financial Type` | `Financial Type` | `Campaign Title` |
| **Raiser's Edge NXT: Gifts** | A gift list export with constituent fields: `First name`, `Last name`, `Email address`, `Address`, `City`, `State`, `ZIP`, `Country`, `Gift ID`, `Gift date`, `Gift amount`, `Payment method`, `Reference`, `Appeal description`, `Fund description` | `Fund description` | `Appeal description` |

Each system lets you choose and name the columns of an export, and versions differ. If a heading
in your file differs from the list, either rename it in the file or choose the template and map
that column on the column step. Columns the template does not name are ignored.

## How to Turn It On

There is nothing to turn on. Giving adds the six templates when it is installed, and an upgrade
adds any template a later version ships, so the **Import** tab lists them. An upgrade never
changes a template you have edited. If one is missing, open **BarnCRM Settings**, **Health**,
and select **Restore Import Templates**. Switch off a template you do not need on the
**Import** tab's template list.

Before loading gifts, create in BarnCRM every fund and appeal the file names, with the same
names (see [Funds](funds.md) and [Appeals](appeals.md)), and a default fund. A gift naming a fund
or an appeal BarnCRM does not have is rejected in the preview, naming it. If your file has no
appeal for a gift, the gift loads with none.

## A Five-Minute Walkthrough (as Maria)

1. In Little Green Light, Maria exports last year's gifts with the constituent's name, email and
   address, as a CSV file.
2. In BarnCRM she creates the funds **General** and **Building** and the appeal **Spring Appeal**,
   the names the file uses.
3. She opens the **Import** tab, chooses **Little Green Light: Gifts** and the file.
4. The preview shows 212 gifts to create, 140 donors matched by email and 31 new. Two rows are
   rejected: one names a fund **Capital**, which BarnCRM does not have. She creates it and clicks
   **Retry All Fixed Rows**.
5. She clicks **Load**. The gifts appear on each donor and household, with their fund and appeal,
   and the Little Green Light gift number in External ID.

## Common Mistakes

- **A donor with no email address** is created again for each gift. Give such donors an email
  address in the other system before the export, or choose **Name plus postal code** on the
  matching step (two people with one name at one address then become one).
- **Organizations' gifts.** The templates read each gift as a person's. Load organizations'
  gifts with the **Generic Gift List** template, the organization's name mapped to
  **Organization: name**.
- **Payment methods** the other system names differently (for example "Credit Card", "Cheque",
  "EFT") are read as BarnCRM's (Card, Check, ACH). Any other is rejected in the preview, naming
  the methods BarnCRM accepts: change it in the file, or add a **Replace** step to the payment
  method column on the column step ([Importing](importing.md)).
- **Recurring gifts and pledges** load as the gifts paid. Create the commitment by hand
  ([Commitments](commitments.md)) before loading, and the payments match it.

## What Cannot Be Proven Without the Other System

The headings above follow each system's standard export as described in its own help pages; no
system was connected to check them. If your export differs, map the column on the column step.
