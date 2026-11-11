# Brands and Legal Entities

## What It Does

**Brands** let one organization work under several names in one org: programs, chapters,
affiliates, a thrift store or a DBA. Each brand has its own name, logo, address, phone, website,
colors, email sender and letter signature, and belongs to a **Legal Entity**: the organization
itself, or a separately incorporated affiliate with its own legal name and tax ID.

With brands on:

- People, households and organizations can belong to several brands, and staff can work for
  several brands, through **Brand Assignments**.
- Gifts, appeals, volunteer jobs, programs and portals carry a **Brand** field. A new record takes
  its parent's brand (a gift takes its appeal's), else the brand of the person creating it.
- Receipts print the gift's brand: its name, logo, address and signature, and its legal entity's
  legal name and tax ID. A value the brand leaves blank comes from its legal entity, then from your
  organization settings.
- Receipts can be numbered per brand or per legal entity (optional).
- Every Brand field can be filtered on in list views, reports and dashboards, and the report type
  **Brands with Brand Assignments** lists who belongs to each brand.
- Optionally, staff see only the households, people and organizations of their own brands.

With brands off (the default), nothing changes: records and documents print your organization
details as before, and no app shows a Brands tab.

## How to Set It Up

1. In **BarnCRM Settings**, open **Organization** and turn on **Use brands**. Save.
2. Click **Open Legal Entities** and add your organization as a legal entity: legal name, tax ID,
   registered address, fiscal year start month. Check **Default**. Add any affiliate that is a
   separate legal body as its own entity.
3. Click **Open Brands** and add each brand. Pick its legal entity, fill in what it prints, and
   check **Default** on the brand used when a record has none.
   - **Logo File ID**: upload the logo to the brand's **Files**, open the file and copy the ID
     that starts with `069` into this field.
   - **Sender Email**: must be a verified Organization-Wide Email Address (Setup, Organization-Wide
     Addresses).
   - **Letter Signature**: the closing printed under letters and receipts, one line per line.
     Blank uses the signer in the module's own settings.
   - **Primary Color** and **Secondary Color**: hex codes such as `#1B5E20`.
4. On each brand, add **Brand Assignments**: one per person (Contact or person Account),
   household or organization (Account) and staff member (User). Check **Primary** on a staff
   member's main brand: their new records take it.

Brand assignments can also be loaded with **Import** (map the Brand column to the brand's record
ID) and changed in bulk with **Bulk Update**.

## Brand-Restricted Visibility (Optional)

Some organizations need staff of one brand not to see another brand's people.

1. Turn on **Share records by brand** in **BarnCRM Settings**, **Organization** (it needs **Use
   brands** on). BarnCRM creates a public group per active brand, named `BarnCRM_Brand_` and the
   brand ID, adds the brand's assigned staff, and shares each household or organization assigned
   to the brand (directly or through one of its people) with that group, Read/Write.
2. In Setup, **Sharing Settings**, set the default for **Account** to **Private**. BarnCRM never
   changes your sharing defaults; **Health Check** reminds you while visibility is on and
   Accounts are not Private.

Staff then see their own records, the records of their brands, and whatever your roles and
sharing rules already give them. A record with no brand is visible as your sharing settings
decide. Changes to brand assignments are applied within a minute or two. Turning the setting off
removes every share and group BarnCRM added.

Gifts and other module records follow their own sharing; brand visibility covers households,
people and organizations.

## Receipt Numbering per Brand (Optional)

In **BarnCRM Settings**, **Receipts**, **Number receipts by**: **Organization** (the default),
**Legal Entity** or **Brand**. With **Legal Entity** or **Brand**, a receipt for a gift with a
brand is numbered in its own series, using the entity's or brand's **Receipt Number Prefix**
(blank uses your organization prefix). Year-end statements stay on the organization series.
Existing receipts and series are never renumbered.

## Settings

All in **BarnCRM Settings**, **Organization**, org-wide:

- **Use brands** (default off).
- **Share records by brand** (default off).
- **Brands** and **Legal Entities**: open the records.

And in **Receipts**: **Number receipts by** (default Organization).

## Permissions

- **BarnCRM Admin**: creates and edits brands, legal entities and brand assignments; the Brands
  and Legal Entities tabs are available in the App Launcher.
- **BarnCRM Staff**: reads brands and legal entities, and adds or removes brand assignments.
- **BarnCRM Read Only**: reads all three.
