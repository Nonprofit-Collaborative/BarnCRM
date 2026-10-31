# Donor Segments

## What It Does

A donor segment is a named list of people or organizations chosen by their giving: lapsed
donors, new donors, upgraders, donors who moved between levels, and major gift prospects.
You keep a segment, and next month it gives you the right people again, counted, listed and
ready to export.

The export is a CSV file laid out for **Mailchimp** or **Constant Contact**. BarnCRM never
sends an email and never connects to either tool: you import the file there yourself, the
way you would any list.

Three things to know first:

- **A segment is a saved Find query.** Every saved Find query of people or organizations
  is a segment, and every segment is a saved Find query. Editing its criteria, its columns
  and who can see it all happens in Find, which you may already know. There is nothing else
  to keep in step.
- **Everyone sees only what they may.** A segment runs with the person's own access, so the
  same segment shows a fundraiser only the donors and fields they can see.
- **There are no settings.** Nothing to switch on in BarnCRM Settings. The export row limit
  is Find's own (**BarnCRM Settings**, Find section, **Export Row Limit**).

## Who Can Use It

Donor segments are Find queries, so they need the **BarnCRM Find and Export** permission set
(BarnCRM Admin includes it), plus Giving Staff, Giving Admin or Giving Read Only for the
page itself. Without Find the page says so and shows nothing.

## The Starter Templates

Each template saves a new segment you can change. The amounts and days are starting points.

| Template | Who it finds |
|---|---|
| Lapsed Donors | Gave last year and nothing yet this year. |
| New Donors | Made a first gift in the last 365 days. |
| Upgraders | Gave last year and has already given more this year than all of last year. |
| Level Movers | Moved from one donor level to another in the last 90 days. |
| Major Gift Prospects | A largest gift of 1,000 or more or total giving of 5,000 or more, and a gift in the last two years. |

Every template works for **people** or for **organizations**. People who have died are left
out. For organizations, only accounts that are organizations count, never households.

Upgraders reads a field added for it, **Change From Last Year** on people and
organizations: giving this year less giving last year. You can use it in reports too.

Years are your fiscal years when your giving rollups count fiscal years, because the
templates read the rollup fields **Giving This Year** and **Giving Last Year**.

## A Five-Minute Walkthrough

1. Open the **BarnCRM Fundraising** app and the **Donor Segments** tab.
2. Under **Start From a Template**, choose **Lapsed Donors**, choose **People**, keep or
   change the name, and choose **Save as Segment**.
3. The segment opens with its count. Choose **Show List** to see who is in it.
4. Choose **Export**, pick **Mailchimp**, and save the file.
5. In Mailchimp, import contacts from a CSV file, choose the file, and confirm the columns.
   The **Tags** column carries the segment name, so you can tag everyone in one step.
6. Next month, open the tab, choose the same segment and export again.

To change who a segment finds, choose **Edit in Find**. Find opens the segment's query; change
the conditions and save it there under the same name.

## The Export Layouts

| Layout | For | Columns |
|---|---|---|
| Mailchimp | People | Email Address, First Name, Last Name, Tags |
| Constant Contact | People | Email address, First name, Last name, Street address line 1, City, State/Province, Zip/Postal code, Country |
| All Columns | People or organizations | The segment's own columns, as Find shows them |

The two email layouts leave out anyone who cannot be emailed: no email address, **Email Opt
Out** ticked, or marked deceased. An address that appears twice (two people in one household
who share an email) is written once, because both tools refuse a repeated address in one
import, and the page says how many it left out. The address columns come from the mailing
address.

An organization has no email field, so organization segments export with **All Columns**.

The file is UTF-8 CSV, which both tools read, with the same rules as a Find export: a value
that starts like a spreadsheet formula is written as text.

## Sharing a Segment

A new segment is yours alone. To share it with everyone who uses Find, open it in Find and
tick **Shared**. Shared segments of other people appear in your list after your own; you can
count, list and export them but only their owner can change them.

## Common Mistakes

- **"The export has fewer people than the count."** The email layouts leave out people with
  no email, who opted out, or who share an email already written. The count is everyone in
  the segment.
- **Saving a template under a name you already used** replaces that segment's criteria.
  Choose a new name to keep both.
- **Expecting a segment to be a snapshot.** A segment is criteria, not a stored list. It
  finds whoever matches today.
- **A count that says "More than 10,000".** The page stops counting there. The export still
  reads up to the export row limit.

## What This Does Not Do Yet

- Send email, or sync a list to Mailchimp or Constant Contact. That is out of scope by design
  (plan Section 6.1.3): import the file.
- Mailchimp's combined address field. Export with Constant Contact or All Columns when you
  need addresses.
- Count past 10,000 records.

## Field Reference

| Field | On | What it holds |
|---|---|---|
| Change From Last Year | People and organizations | Giving This Year minus Giving Last Year, a blank read as zero. Read only. |

Technical detail: canonical model Section 25O (rules R-DS1 to R-DS6).
