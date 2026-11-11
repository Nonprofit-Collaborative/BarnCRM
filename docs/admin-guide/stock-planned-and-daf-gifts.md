# Stock, Planned and Donor-Advised Fund Gifts

## What It Does

Five fields on a gift describe where it came from when it was not a simple gift of money from
the donor (G-21, G-31):

| Field | Shown | What it holds |
|---|---|---|
| **Stock Symbol** | When **Payment Method** is Stock | The ticker symbol |
| **Shares** | When **Payment Method** is Stock | How many shares |
| **Planned Gift Type** | Always | Bequest, Beneficiary Designation, Charitable Gift Annuity, Charitable Remainder Trust, Life Insurance or Other (record a charitable lead trust as Other); empty for any other gift |
| **Gift Source** | Always | Donor-Advised Fund, Family Foundation, IRA Charitable Distribution, Employer Giving Program or Other; empty for a gift straight from the donor |
| **Gift Source Name** | When **Gift Source** is filled in | The fund's sponsor or the foundation, for example the donor-advised fund's sponsor |

The donor stays the person or organization you credit, so the gift counts in their giving totals,
levels and scores as before. The fields describe the gift; nothing reads them for a total, the
accounting export or the posting lock.

They are on the gift page (**Details** tab, **Gift** section), on the standard New and Edit
form, and in the **Gifts** report type. Giving Admin and Giving Staff edit them; Giving Read
Only sees them.

## How to Turn It On

Nothing to turn on: the fields and the report come with the Giving module.

## The DAF and Stock Gifts Report

**DAF and Stock Gifts This Year**, in the **BarnCRM Giving** report folder, lists this year's
gifts that came through a donor-advised fund or were gifts of stock, with the sponsor, the
symbol and shares, and the total. Pending and Cancelled gifts are left out. Change the date
filter or add **Planned Gift Type** to make your own planned giving report.

## Things to Know

- **The amount is yours to enter.** BarnCRM does not price stock. Enter the value you record,
  usually the average of the high and low price on the day the shares arrived.
- **Receipts are unchanged.** A gift through a donor-advised fund is legally the sponsor's gift,
  so many organizations send the donor a thank-you without a tax receipt. BarnCRM does not
  change receipt wording for these fields; use **Do Not Thank** on the gift, or a receipt
  template of your own, as your accountant advises.
- **A planned gift is a gift received.** Record a bequest or an annuity payment when the money
  arrives. An intention that has not paid yet is not a gift; keep it as a note or an ask.
