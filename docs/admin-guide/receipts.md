# Receipts and year-end statements

## What it does

Open Impact produces the numbered PDF a donor needs at tax time: one receipt for one gift,
or one consolidated statement listing everything a donor gave in a year. Each document
carries a number that is used once and never again, and the file is stored on the receipt
record, and on the gift for a single gift receipt, so anyone working with giving can find
the exact copy the donor received.

A receipt never changes after it is issued. If something on it is wrong, you void it and
issue a new one; both stay on the record, so you can always answer the question "which
document does this donor actually hold".

The required tax wording is written by Open Impact, not by you. You write the letter around
it.

## How to turn it on

Everything is on one page: **Open Impact, then Open Impact Settings, then Receipts**.

### 1. Check your organization details

The Organization section of Open Impact Settings holds your legal name, your tax
identification number, your address, your logo, your signature image, and the name and
title of whoever signs your letters. A receipt prints these. If you completed the Setup
Assistant they are already filled in. If your legal name is blank, receipts will not
generate and Open Impact tells you which field is missing.

Your legal name and address print at the top of every document even if your letter does not
ask for them, and your tax identification number prints at the bottom. That is deliberate:
deleting the letterhead out of your template should not produce a receipt with no
organization on it. If your letter does print the name itself, Open Impact does not print it
a second time.

### 2. Set your numbering

In the Receipts section:

- **Receipt number prefix.** Two or three letters, usually your initials. The number is
  built as prefix, year, counter: `HFH-2026-000001`.
- **Next counter.** Leave it at 1 unless you are moving from another system and want to
  carry on from where it stopped. Set it once, before you issue anything. This is the only
  place a receipt number is ever chosen by a person: Open Impact issues every number itself,
  from this counter, when it creates the receipt.
- **Statement year.** The tax year the year-end run covers. Set it in January to last year.
- **Place of issue.** The city and region you issue from. Optional in the United States.

One piece of first-time setup needs Salesforce Setup: the **Receipts** panel, which is where
you issue, void and reissue, lives on a gift's record page, and Open Impact ships a page
called **Gift Record Page** with the panel already on it. Assign it once, as your org default
for Gift, and every gift shows the panel from then on. If your organization has built a gift
record page of its own, add the **Receipts** component to that page instead. This is the same
one-time assignment the soft credits and tributes panels need, so if you have already done it
for those, the Receipts panel is there too.

### 3. Choose how your logo prints

Still in the Receipts section:

- **Print the logo on receipts.** On by default, and only does anything once a logo has been
  uploaded in the Organization section. Turn it off to send plain documents. **A receipt with
  no logo is a valid receipt**, so this costs you nothing legally.
- **Logo width in millimetres.** Forty is about a third of the width of the page, which suits
  a wide wordmark. A tall square logo usually wants twenty five.
- **Logo delivery route.** Leave it empty. It exists because how an image reaches the PDF has
  not been confirmed in a real org yet (see the last section of this page), and it lets you or
  Open Impact support try another route without waiting for a new version. The three values it
  accepts are `File download`, `Embedded image` and `Document server`.

### 4. Write your two letters

Also in the Receipts section, **Receipt letters and year end statements** opens the Receipts
page, which has two tabs. It opens as its own page rather than inside the settings console,
which is how every page the Giving module adds behaves. On the **Receipt templates** tab,
Open Impact ships one letter of each kind:

- **Per gift receipt**, for a single gift.
- **Consolidated statement**, for a donor's whole year.

Both letters are created when the package is installed. If the list is empty, that step did
not finish: click **Restore the shipped letters** and the two come back. Restoring is safe to
run at any time, and it never touches a letter you have already edited.

Pick a letter, edit the wording, keep the tokens (`{{DonorName}}`, `{{Amount}}`,
`{{GiftDate}}` and the rest, listed under the editor), and click **Save**. If the letter you
edited is not the one in use, **Use this letter** switches it on and switches the other one of
its kind off. Only one letter of each kind is in use at a time.

**You cannot delete the tax sentences by deleting them from the template.** Open Impact adds
them to every document regardless of what the letter says. That is deliberate: those
sentences are what makes the document a valid receipt.

### 5. Give people access

On the Access page, **Giving Staff** and **Giving Admin** can issue, void and reissue
receipts and start a run. Everyone with any Giving permission set can read receipts and open
the stored files. **Nobody can edit or delete an issued receipt or its file**, including
Open Impact Admin. That is not an oversight, and there is no switch for it.

**Who can open a receipt PDF, exactly.** The file is attached to the **Receipt** record, and
for a single gift receipt to the **Gift** as well. It is not attached to the donor's household
or contact record. So a person can open a receipt PDF if, and only if, they hold one of the
three Giving permission sets: Giving Admin, Giving Staff or Giving Read Only. Somebody with
only a Core role, for example Program Staff or Volunteer Coordinator, can open the donor and
cannot open the donor's receipts or year-end statement. That is deliberate: a year-end
statement is a donor's whole giving history plus your tax identification number, and it should
not be in the Files list of a record that everybody reads.

To get to a donor's documents, open the donor, then the **Receipts** related list, then the
receipt, then the file on it.

**Editing the letters needs the Open Impact Admin role.** Writing the letter every donor
receives is configuration, so saving a letter, switching one on, and restoring the shipped
letters all need the Manage Open Impact Settings permission, exactly like every other page in
Open Impact Settings. Issuing receipts does not: that is day to day work and needs only Giving
Staff.

## A five-minute walkthrough

Start from the sample data.

1. Open **Open Impact Settings**, then **Receipts**. Set the prefix to `TEST`, leave the next
   counter at 1, and set the statement year to last year.
2. Open **Receipt letters and year end statements**, and on the **Receipt templates** tab
   check that a letter of each kind is in use. If one is not, pick it and click **Use this
   letter**.
3. Open any gift from the sample data. Click **Issue receipt** on the **Receipts** panel.
   You will see a receipt number appear on the gift, and a PDF in the Files list on the gift
   and on the receipt. Deliberately not on the donor's household: see "Give people access"
   above.
4. Open the PDF. It states your organization's name and address at the top, the amount, the
   date, your tax identification number, and the sentence "No goods or services were provided
   in exchange for this contribution." If you have uploaded a logo, it is above the name; if
   it is missing, read the last section of this page before you go looking for a mistake.
5. Now break it on purpose. Try to change the gift's amount. The save is refused with "This
   gift has a receipt number, so its amount, date, donor and in-kind description cannot
   change. Void the receipt and reissue it, or record a refund."
6. On the gift, click **Void and reissue**. Type a reason, for example "Amount was entered
   wrongly". You get a second receipt with the next number, the first one is marked Void with
   your reason and today's date, and **the original PDF is still there, untouched**. Open
   both files and compare them.
7. Go to the **Receipts** tab and look at the two records. The voided one points at its
   replacement, the replacement points back at what it replaces.
8. Back in Open Impact Settings, under Receipts, choose **Receipt letters and year end
   statements** again, open the **Year end statements** tab, check
   the statement year, and click **Generate**. A run appears in the list below and counts up
   as it goes; **Refresh** updates it. When it finishes, open a household with several gifts
   in that year, open its **Receipts** related list, open the statement, and read the file:
   every gift is a line, each line carries its own status, and the total at the bottom is the
   sum of the lines.

That is the whole feature. Steps 5 and 6 are the ones worth doing twice, because they are
what makes the rest trustworthy.

## Common mistakes

**Changing the prefix or the counter after you have issued receipts.** The numbering
sequence is created the first time a receipt of a given kind is issued in a given year, and
it keeps the prefix and starting counter it was created with. Changing the settings later
affects next year's series, not this one. If you have issued one test receipt with the wrong
prefix, void it and say so in the reason, then fix the setting before you issue anything
real.

**Expecting the numbers to have no gaps.** They will occasionally have gaps, and that is
normal and safe. If a document fails to generate after its number was handed out, Open
Impact does not hand that number to somebody else. It creates a receipt record with status
Void and the reason "Generation failed", so if an auditor asks what happened to number 47,
you can show them. A gap you cannot explain would be the problem; a gap with a Void record
against it is an answer.

**Typing a receipt number onto a gift.** You cannot, and there is nothing to fix: the
Receipt Number on a gift is read only for everyone, and a save that tries to fill it in is
refused with "A receipt number is issued by Open Impact when it creates the receipt, and
cannot be filled in by hand." A number typed in belongs to no receipt, so there is no PDF and
nothing to send; it locks the gift's amount, date and donor as if a donor were holding a
document; the same number can still come out of the counter later and land on somebody's
year-end statement; and the gift itself can never be receipted afterwards, because Open Impact
sees a number already there. Use **Issue receipt** on the gift instead. If a gift in your org
already carries a number that no receipt matches, see "Lifting the receipt lock" in
[Gifts](gifts.md): clearing the number there puts the gift back in reach of Issue receipt.
**Looking for a receipt in the Files list on a donor's household.** It is not there, and it
is not missing. A receipt PDF lives on the Receipt record, and on the Gift for a single gift
receipt, so that reading it takes a Giving permission set rather than read access to a contact.
Open the donor, then the **Receipts** related list.

**Deleting a receipt's file to "cancel" it.** Voiding is the way to cancel a receipt, and it
deliberately leaves the file alone: the donor still has their copy, so the org should too.
Nobody has delete access on receipts or their files, so this mostly shows up as a puzzled
"why can't I delete this". Void it instead.

**Running year-end statements before the year's gifts are all entered.** A donor who already
has a statement for the year is skipped when you run again, so late gifts will not appear on
a second run. Fix that donor by voiding their statement and reissuing it, which picks up
everything. Running the batch twice is safe and cheap; it is only the donors already
receipted that are skipped.

**Putting a value on an in-kind gift's receipt.** You cannot, and you should not want to. For
a gift of goods, Open Impact prints the description the donor gave and never a value, because
in the United States valuing a donated item is the donor's responsibility and not yours. Where
your letter asks for an amount, an in-kind receipt says "the goods or services described
below" instead, and the document states in plain words that no value has been stated. On a
year-end statement the gift is a line with no amount, it is left out of the total, and the
statement says why. The fair market value you record stays in Open Impact for your own
reporting. The description on a receipted in-kind gift is locked from then on, exactly as the
amount is on a cash gift, because it is printed on the document the donor holds; the fair
market value stays editable, because it is on no document. See
[In-kind gifts](in-kind-gifts.md).

## Three things to know before you rely on this

Recorded here rather than hidden, because each may change what you see:

1. **Logos and signature images on the PDF may not appear yet.** How an image reaches the PDF
   renderer has not been confirmed in a real org (ADR-0016). A receipt with no logo and no
   signature is a legally valid receipt, so this does not stop you sending them. If your logo
   does not print, that is this, not your setup. Three things are worth trying before you
   conclude anything: check that the logo file is shared with the people who issue receipts,
   because Open Impact will not print a file the running user cannot see and writes an Error
   Log warning saying so; try the other two values of **Logo delivery route**; and if none of
   them works, turn **Print the logo on receipts** off so your documents are deliberately
   plain rather than accidentally so.
2. **Two people cannot issue receipts at the same instant.** Receipt numbers come from one
   counter, and whoever is using it holds it until their receipt or their statement run
   finishes. A second person issuing at that moment waits, and if the wait reaches ten seconds
   they see a "record is currently locked" error. Nothing is lost and no number is duplicated:
   try again. This matters most while a year-end run is going, so issue single receipts before
   or after the run rather than during it.
3. **The speed of a very large year-end run has not been measured.** If you have tens of
   thousands of donors, run your statements early in January rather than the night before you
   want to post them, and watch the Receipt Run record.

## Fields, for a report builder

| What you want to report on | Object |
|---|---|
| Each document issued, its number, status and amount | Receipt |
| Each generation run, its counts and outcome | Receipt Run |
| The number series and where each one has got to | Receipt Number Sequence |
| The letters themselves | Receipt Template |
