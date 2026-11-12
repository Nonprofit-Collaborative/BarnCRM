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
  A portal's brand is set by hand.
- Receipts print the gift's brand: its name, logo, address and signature, and its legal entity's
  legal name and tax ID. A value the brand leaves blank comes from its legal entity, then from your
  organization settings.
- Thank-you emails for a gift with a brand come from the brand's **Sender Email** (when it is a
  set-up Organization-Wide Address), else from the Acknowledgments from address.
- Volunteer hour letters and certificates print the brand of the jobs the hours were for:
  `{OrganizationName}` and `{OrganizationAddress}` become the brand's legal entity and address,
  and `{BrandName}`, `{BrandLogo}`, `{BrandSignature}`, `{BrandPhone}` and `{BrandWebsite}` can be
  added to a template. A person whose hours span several brands gets your organization's identity.
- Portals show their brand's colors and a footer with its name, address, phone and website, and
  send sign-in codes from its Sender Email when the portal has no Sender Address of its own. A
  portal with no brand uses the default brand. The board portal is a portal, so Corporate Hub
  board members see the brand of their portal; Corporate Hub prints no documents of its own.
- Records with no brand print the **default brand**, without being labelled with it.
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

## Brands on Records: Import and Bulk Update

- **Gift import**: map a column to **Gift: brand** (offered while brands are on). Each value is a
  brand name or record ID; a name two brands share, or one that matches none, rejects the row.
  An empty value lets the gift take its appeal's brand, else the importing user's.
- **Import** of appeals, volunteer jobs, programs or portals: map the **Brand** column to the
  brand's record ID, like any other lookup.
- **Bulk Update**: pick the object (Gifts, Appeals, Volunteer Jobs, Programs or Portals), the
  records, and set **Brand** to the brand's record ID.

## Brand Filters in List Views, Reports and Dashboards

- **List views**: on any Gifts, Appeals, Volunteer Jobs, Programs or Portals list, open the
  filter panel and add **Brand** equals the brand name. Save it as a new view, such as
  "Barn Thrift Gifts", and share it with that brand's staff.
- **Reports**: Gifts, Gifts with Allocations and every standard report type on these objects
  carry **Brand**. Asks carry their appeal's brand (**Appeal: Brand**), and Volunteer Hours,
  Volunteer Shifts and Volunteer Signups their job's brand (**Volunteer Job: Brand**).
- **Dashboards**: open a dashboard, **Edit**, **+ Filter**, choose **Brand** (or **Volunteer
  Job: Brand**) and add a value per brand. Every component's report must include that field.

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
brand is numbered in its own series, using the entity's or brand's **Receipt Number Prefix**.
An entity or brand with no prefix stays on the organization series, so two series never share a
prefix. Year-end statements stay on the organization series. Existing receipts and series are
never renumbered.

Receipt templates can print the brand name with the merge token `{{BrandName}}` (the legal name
when there is no brand).

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
