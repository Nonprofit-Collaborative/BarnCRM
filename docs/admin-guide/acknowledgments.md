# Acknowledgments

## What It Does

Acknowledgments are the thank yous. You write the rules once, in the language you already
use ("gifts over $1,000 get the director's letter, everything else gets the standard email,
gifts to the staff giving campaign get nothing"), and BarnCRM puts every gift that
arrives into the right queue.

Emailed thank yous are sent for you, in a batch you press or overnight if you want it. Letter
thank yous come out as a spreadsheet you merge with your own letter in Word or Google Docs
and print. A donor who has opted out of email is thanked by letter instead (see "A donor
who opted out of email" below). Every thank you that goes out is recorded on its own record: which letter, to
which address, on what date, and whether it failed, so nobody has to guess in January.

An acknowledgment is not a receipt. A receipt is the tax document with a number on it, which
is [receipts.md](receipts.md). A donor usually gets both, and they are separate on purpose:
the thank you is yours to write and rewrite, and the receipt is not.

## How to Turn It On

Everything is in the app, with one exception noted at step 3.

1. Open **BarnCRM Settings**, then **Giving**, then **Acknowledgments**.
2. Turn on **Acknowledge gifts**. Nothing is queued until you do, because a thank you sent
   with the wrong wording cannot be recalled.
3. Decide what your emailed thank you says. The wording lives in a standard Salesforce email
   template, which means you get the normal editor, the preview, and the test send.
   BarnCRM ships one to start from, called **BarnCRM: thank you for your gift**. Writing or
   changing a template is the one place you may find yourself in Setup, under Email
   Templates, and it is where Salesforce keeps template editing for everybody.
4. Create your rules with **New rule** on the Acknowledgments page. The rule form opens on the
   page itself; to change a rule later, click **Edit** beside it. Each rule has:
   - an **order**, lowest first. The first rule that matches a gift wins, so put your most
     specific rule at the top;
   - a **channel**: Email, Letter, or None. None means gifts like this do not get a thank
     you at all;
   - an **email template**, chosen by name from the list of your org's active templates,
     required when the channel is Email;
   - **minimum** and **maximum amount**, either or both, or neither for any amount. Both
     ends are included: a rule from 100 to 1000 matches a gift of exactly 100 and a gift of
     exactly 1000;
   - a **gift type** and an **appeal**, if this rule is only for one of them. Leave them
     empty for any;
   - **first gift only**, for a welcome letter that goes to a donor's very first gift.
5. Set **Acknowledgments from address** if your thank yous should come from
   `giving@yourorg.org` rather than from whoever pressed Send. The address has to be one
   your org has already verified as an organization wide address.
6. If you want emailed thank yous to go out overnight without anybody pressing anything,
   turn on **Send emails nightly** on the same page. It runs at 2:45 in the morning. Leave
   it off if you would rather look at the queue first, which is what most organizations do
   for the first month.

## A Five-Minute Walkthrough

Start with the sample data loaded (see [sample-data.md](sample-data.md)).

1. Open **BarnCRM Settings**, then **Giving**, then **Acknowledgments**. Turn on
   **Acknowledge gifts**.
2. Choose **New rule**. Name it `Everything else`, order `100`, channel `Email`, and choose
   **BarnCRM: thank you for your gift** as the email template. Save.
3. Choose **New rule** again. Name it `Major gifts`, order `10`, channel `Letter`, minimum
   amount `1000`. Save. You now have two rules: gifts of $1,000 and up get a letter,
   everything else gets an email.
4. Enter a gift for $50 from one of the sample households, using **Quick Gift Entry**. Enter
   a second gift for $2,500 from another one.
5. Go back to the Acknowledgments page. The queue now reads **1 email** and **1 letter**,
   plus whatever the sample gifts added.
6. Press **Send emails now**. The page shows the run finishing and the count sent. Open the
   $50 gift: its acknowledgment status is now **Acknowledged**, with today's date, and its
   **Acknowledgments** list shows one row saying which template went to which address.
7. Press **Download letters to merge**. You get a CSV with one row per letter gift: donor
   name, greeting, address, amount, gift date, appeal, fund. Merge it with your own letter,
   print, and then press **Mark as sent** on the run. Until you press it the gifts stay in
   the letter queue, because BarnCRM cannot tell whether you printed anything.

## List Views

**Acknowledgments** has **All Acknowledgments**, **Queued Acknowledgments** and **Failed
Acknowledgments**. **Acknowledgment Rules** has **All Acknowledgment Rules**, **Active
Acknowledgment Rules** and **Inactive Acknowledgment Rules**. **Acknowledgment Runs** has **All
Acknowledgment Runs**.

## Common Mistakes

**Two rules that both match, in the wrong order.** A rule with no minimum and no maximum
matches everything, so if it sits above your major gift rule, your major donors get the
standard email. Fix the order numbers, lowest for the most specific rule. Changing a rule
takes effect for gifts still in the queue: nothing is stored on a gift until it is sent.

**A template that is no longer there.** If the template a rule uses is deleted or switched
off, the page shows **Template not found** beside the rule, and any acknowledgment that
tries to use it is marked Failed with that reason rather than sending an empty message.
Click **Edit** beside the rule and choose another template. The same happens to a rule
created on the standard record page with a template name typed by hand, which is why rules
are best created on the Acknowledgments page.

**An organization gift with nobody to email.** A gift credited to an organization that has no
primary contact has no email address to send to. The run counts it under **could not be
sent**, names it in one Error Log entry, and leaves the gift in the queue, which usually
means it should have been a letter. Either give the organization a primary contact or write a
rule that sends organization gifts by letter.

**A donor who opted out of email.** BarnCRM never emails a thank you to a contact whose
**Email Opt Out** is ticked. For a person's gift that is the donor; for an organization or
household gift it is the account's primary contact, the person the email would have gone to.
The gift is left in the queue with no acknowledgment record and no error, and the
Acknowledgments page counts it on its own line, **Opted out of email, sent by letter**. Those
gifts are also counted in **Letters ready to merge**, and the next **Download letters to
merge** puts them in the file, so the donor is still thanked. If you do not send letters,
they wait in the queue until you do, or until someone sets the gift's acknowledgment status
by hand.

**Thanking somebody twice.** BarnCRM will not do it on its own: a gift that has been
acknowledged is never returned to the queue by a rule, an edit, or a re-run of a failed
batch. If you genuinely want to thank a donor again, set the gift's **acknowledgment status**
back to **To acknowledge**. That is the deliberate act, and afterwards the gift shows two
acknowledgment records rather than one, so the second one is not a mystery.

**Expecting a refund to undo a thank you.** It does not. Refunded gifts, written off gifts,
pending gifts and the negative gifts that record a refund are never acknowledged in the first
place, and refunding a gift that was already thanked leaves the thank you standing, because
it was sent and the donor read it.
