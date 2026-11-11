# Brands

Scripts for multi-brand management (C-47): brands, legal entities, brand assignments, brand
defaulting, brand-aware receipts and numbering, and brand-restricted visibility. Setup detail:
[Brands and Legal Entities](../admin-guide/brands.md).

Before you start: an org from [Before you test](before-you-test.md) with Core and Giving deployed,
an admin user and a staff user (see [Test users](before-you-test.md#test-users)), and the
organization legal name filled in.

## T-BRAND-01: Brands Off Changes Nothing

**Purpose:** confirm a fresh install shows no brand anywhere.
**Prerequisites:** admin user; brands never turned on.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Organization**. | **Use brands** and **Share records by brand** are off; **Brands** and **Legal Entities** rows each have an Open button. |
| 2 | Open the BarnCRM and BarnCRM Admin apps. | Neither app has a Brands or Legal Entities tab. |
| 3 | Issue a receipt for a received gift. | The receipt prints the organization name, address and tax ID from settings, as before. |

**Cleanup:** None.

## T-BRAND-02: Legal Entities and Brands, One Default

**Purpose:** confirm brands and entities save and only one of each is the default.
**Prerequisites:** admin user.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Turn on **Use brands** and save. Click **Open Legal Entities** and add `Friends of the Barn Inc.` with a tax ID, street and **Default** checked. | The entity saves. |
| 2 | Add a second entity `Barn Thrift LLC` with **Default** checked. | It saves; `Friends of the Barn Inc.` is no longer the default. Put the default back on `Friends of the Barn Inc.`. |
| 3 | Click **Open Brands** and add `North Chapter` (no legal entity, **Default** checked) and `Barn Thrift` (legal entity `Barn Thrift LLC`, color `green`). | `Barn Thrift` is refused with "Enter colors as a hex code such as #1B5E20." Change the color to `#1B5E20`: it saves. |
| 4 | Enter `13` in a legal entity's **Fiscal Year Start Month**. | Refused: "Enter a month from 1 to 12, or leave it blank." |

**Cleanup:** keep the records for the next scripts.

## T-BRAND-03: Brand Assignments, One Primary, No Duplicates

**Purpose:** confirm assignments name one record, are unique per brand and keep one primary.
**Prerequisites:** T-BRAND-02.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | On `North Chapter`, add a Brand Assignment for a household and another for a person. | Both save. |
| 2 | Add one naming both a Contact and an Account. | Refused: "Fill in exactly one of Contact, Account or User." |
| 3 | Add the same household to `North Chapter` again. | Refused as a duplicate value on Assignment Key. |
| 4 | Assign the staff user to both brands, **Primary** checked on each in turn. | Only the last saved assignment is Primary. |

**Cleanup:** keep the records.

## T-BRAND-04: Brand on Gifts and Brand-Aware Receipts

**Purpose:** confirm a new gift takes a brand and its receipt prints the brand.
**Prerequisites:** T-BRAND-03; Giving deployed with its brand fields.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user (primary brand `Barn Thrift`), create a received gift with no appeal and no brand. | The gift's **Brand** is `Barn Thrift`. |
| 2 | Set an appeal's **Brand** to `North Chapter`, then create a gift on that appeal with no brand. | The gift's **Brand** is `North Chapter`. |
| 3 | Issue a receipt for the `Barn Thrift` gift. | The letterhead shows `Barn Thrift`, its address, and the legal name `Barn Thrift LLC` and its tax ID. |
| 4 | In **Receipts**, set **Number receipts by** to **Brand**; give `Barn Thrift` the prefix `BT`. Issue a receipt for another `Barn Thrift` gift. | Its number starts `BT-`. A gift with no brand still gets the organization prefix. |
| 5 | In **Reports**, create a Gifts report filtered on **Brand** equals `Barn Thrift`. | Only `Barn Thrift` gifts are listed. |

**Cleanup:** set **Number receipts by** back to **Organization**.

## T-BRAND-05: Brand-Restricted Visibility

**Purpose:** confirm staff of a brand see its households and lose them when visibility is off.
**Prerequisites:** T-BRAND-03; Account default sharing set to Private in Setup; the staff user owns no test household.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Turn on **Share records by brand** and save. Wait a minute. | In Setup, Public Groups, a group `BarnCRM Brand ...` exists per active brand with the staff user as a member. |
| 2 | As the staff user, open the household assigned to `North Chapter`. | It opens and can be edited. A household with no brand that the staff user does not own is not visible. |
| 3 | As admin, delete that household's `North Chapter` assignment. Wait a minute; as the staff user, refresh. | The household is no longer visible. |
| 4 | Set Account default sharing back to Public Read/Write and run **Health Check**. | A warning: "Brand visibility is on, but Accounts are not Private". |
| 5 | Turn **Share records by brand** off. Wait a minute. | The BarnCRM brand groups are gone, and with them the shares. |

**Cleanup:** restore your org's Account sharing default and turn **Use brands** off.
