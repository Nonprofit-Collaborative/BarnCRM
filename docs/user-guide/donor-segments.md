# Donor Segments

A donor segment is a named list of donors chosen by their giving, such as everyone who gave
last year but not yet this year. You keep it, and each time you open it, it finds whoever
matches today. You can count it, see who is in it, and export a file to import into Mailchimp
or Constant Contact.

**Before you start:** you need the **BarnCRM Find and Export** permission set and a Giving
permission set. If the page says you need Find, ask your admin (see
[Donor segments](../admin-guide/donor-segments.md)).

BarnCRM never sends email. You download a file and import it into your email tool yourself.

## To Make a Segment From a Template

1. In the **Fundraising** app, open **Donor Segments**.
2. Under **Start From a Template**, choose a **Template**: Lapsed Donors, New Donors,
   Upgraders, Level Movers or Major Gift Prospects. The line below it says who it finds.
3. Choose **People** or **Organizations**.
4. Keep the suggested **Segment Name** or type your own, then choose **Save as Segment**.

The new segment opens with its count. Saving under a name you already used replaces that
segment.

## To Count and List a Segment

1. Under **Your Segments**, choose the **Segment**. Its count shows below.
2. Choose **Show List** to see who is in it, in the segment's own columns and order.

Segments other people shared with you are listed after your own, with their name.

## To Export for Mailchimp or Constant Contact

1. Choose the segment.
2. Choose the **Export Layout**: **Mailchimp**, **Constant Contact** or **All Columns**.
3. Choose **Export**. The file downloads when every page is read; the page says how many rows
   it wrote.
4. In your email tool, import contacts from a CSV file and choose the file. Check the column
   matches it suggests, then finish the import.

The Mailchimp file has a **Tags** column holding the segment name, so you can tag everyone you
import in one step.

People with no email, people who opted out of email, and people marked deceased are never in
the Mailchimp or Constant Contact file. When two people share one email, it is written once.

Organization segments export with **All Columns** only, because an organization has no email
field.

## To Change Who a Segment Finds

Choose **Edit in Find**. Find opens the segment's query: change the conditions or columns and
save it under the same name. To share a segment with your team, tick **Shared** in Find.

## Common Problems

- **The file has fewer people than the count.** The count is everyone in the segment; the
  email files leave out who cannot be emailed and repeated addresses.
- **The count says "More than 10,000".** The page stops counting there. The export still reads
  up to your organization's export row limit.
- **A total looks out of date.** Segments read the giving totals on each donor, which update a
  few seconds after a gift is saved and again overnight.

## Related

- [Finding people and records](find.md)
- [Reports and dashboards](reports-and-dashboards.md)
