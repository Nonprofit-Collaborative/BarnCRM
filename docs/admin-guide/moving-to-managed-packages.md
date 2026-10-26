# Moving a pilot to the managed packages

## 1. What it does

Organizations that piloted BarnCRM before its AppExchange listing run an early edition of
the packages (unlocked packages). Salesforce has no way to switch an installed package to the
listed edition (managed packages), so the move is: copy your BarnCRM records off the org,
remove the early packages, install the listed ones, and load your records back. This page is
that procedure, step by step, and the migration kit in the BarnCRM repository does the copying
and the loading for you.

You do this once. It takes an afternoon on a test copy of your org, then the same afternoon on
the real one. People, households and organizations themselves are never removed: only what
BarnCRM added to them, and BarnCRM's own records, are copied off and put back.

## 2. How to turn it on

This is the one BarnCRM task done from a computer's command line rather than inside the app,
because removing and installing packages happens outside any package. Most organizations have
their implementation partner run it, with the administrator alongside to do the in-app steps.
Whoever runs it needs:

1. A Mac, Windows or Linux computer with the Salesforce CLI (`sf`, version 2) and Python 3.9 or
   later installed.
2. A copy of the BarnCRM repository at the release you are moving to (`git clone`, then
   `git checkout` the release tag your BarnCRM contact gives you).
3. A Salesforce user in your org with the System Administrator profile and the **BarnCRM Admin**
   role (from the **Access** page).
4. From your BarnCRM contact: the installation identifiers (they start `04t`) of the managed
   packages, and the namespace they use. If your pilot packages also used a namespace, its name
   too; you can read it in Setup, **Installed Packages**.
5. A full copy sandbox of your org (or a partial copy holding every BarnCRM record) for the
   rehearsal. Do every step below there first. Do not run it on your real org until the
   rehearsal's check step (step 12) reports no differences.

## 3. A five-minute walkthrough

The steps below are the whole move. On a sandbox with the sample data, steps 6 to 12 take
about five minutes; on a real org, the export and the reload take longer, a few minutes for
every 10,000 records. The rehearsal tells you the real time.

In the commands, `pilot` is the name you give your org when you log in, `<ns>` is the managed
packages' namespace, and `<old-ns>` is the pilot packages' namespace (leave the flag out if they
had none).

1. **Tell everyone.** Pick a quiet day. From step 8 until step 15, nobody should create or
   change BarnCRM records: anything they do in between is lost.
2. **Log the computer into the org.** Run `sf org login web --alias pilot` and sign in as the
   administrator. For the rehearsal, add `--instance-url https://test.salesforce.com`.
3. **Build the mapping.** From the repository folder, run
   `python3 scripts/migration/build_mapping.py --packages core,rollups,giving,mirror --output mapping.json`,
   listing the BarnCRM packages you have installed. It prints how many kinds of record it will
   copy and which it leaves out, and why.
4. **Write down your settings.** Open **BarnCRM Settings** and go through every section. Step 7
   saves a list of them for you too, but Salesforce may not let the kit read every one, so a
   screenshot of each section is your backup.
5. **Stop the scheduled jobs.** A package cannot be removed while one of its jobs is scheduled.
   With Rollup Builder, in the **BarnCRM Rollup Builder** app, click **Stop the nightly
   recalculation**. In BarnCRM Settings: on **Error Log**, click **Stop**; on **Addresses**, under **Seasonal Address Swap**, stop the nightly
   swap. With Giving, on **Commitments**, click **Stop the nightly jobs**. With Mirror, on
   **Opportunity mirror**, click **Stop nightly run**. If automation is paused, click **Resume
   automation**.
6. **Check the kit can read everything.** Run
   `python3 scripts/migration/migrate.py check --org pilot --mapping mapping.json --namespace <old-ns>`.
   It names any field your user cannot read. Fix access before going on: a field the kit cannot
   read is a field that is not copied.
7. **Export.** Run
   `python3 scripts/migration/migrate.py export --org pilot --mapping mapping.json --namespace <old-ns> --out pilot-export`.
   It writes one file per kind of record into the `pilot-export` folder and prints a count for
   each. The folder holds every person's details: keep it on an encrypted disk, never email it,
   and delete it at step 16.
8. **Remove the pilot packages**, last installed first: Mirror, then any other module, then
   Giving, then Rollup Builder, then Core. In Setup, **Installed Packages**, click **Uninstall** beside each one, or
   run `sf package uninstall --package <04t of that package> --target-org pilot --wait 30`
   (`sf package installed list --target-org pilot` shows the identifiers). If Salesforce refuses
   because one of your own reports, flows or fields uses a BarnCRM component, it lists them:
   note each one, delete it (after saving a copy if you need it), and try again.
9. **Install the managed packages**, Core first, then Rollup Builder, then Giving, then Mirror
   and any other module:
   `sf package install --package <04t> --target-org pilot --security-type AdminsOnly --wait 30`.
10. **Get ready to load.** Give yourself the **BarnCRM Admin** role again on the **Access** page.
    With Giving, also give yourself the Override Receipt Lock and Override Posting Lock
    permissions for the day (see [Gifts](gifts.md) and
    [Posting and closed periods](posting-and-closed-periods.md)): without them, receipted and
    posted gifts are refused on the way back in. In BarnCRM Settings, **Automation**, pause all
    automation for 24 hours, so nothing recalculates while records arrive. Do not re-enter any
    other setting yet.
11. **Reload.** Run
    `python3 scripts/migration/migrate.py reimport --org pilot --mapping mapping.json --namespace <ns> --in pilot-export`.
    It loads every kind of record in order, then fills in the links between them, and prints a
    count of loaded and refused records for each. Refused records, with Salesforce's reason, are
    written to `pilot-export/refused.csv`. If the run stops part way (a lost connection, an API
    limit), run the same command again: it carries on from where it stopped and never loads a
    record twice.
12. **Check.** Run
    `python3 scripts/migration/migrate.py verify --org pilot --mapping mapping.json --namespace <ns> --in pilot-export`.
    It reads everything back and compares it, record by record, with the export. "No
    differences" is the result you want. Each difference is listed with the record and field.
13. **Put your settings back.** Re-enter every value from step 4 in BarnCRM Settings (the kit's
    list is `pilot-export/settings.csv`), then schedule again each job you stopped in step 5.
14. **Finish.** Remove the two override permissions from yourself. Resume automation. In the
    **Rollup Builder**, click **Recalculate all**; on the household naming settings, click **Recompute
    all households**. Then run Health Check: it should find nothing new.
15. **Put back your own customizations** from step 8: reports, flows and fields that used
    BarnCRM. If the namespace changed, their references to BarnCRM fields need the new names.
16. **Delete the export folder** from the computer and from any backup of it.

## 4. Common mistakes

- **Skipping the rehearsal.** The first run always finds something particular to your org: a
  validation rule of your own, a required field you added, a flow that fires on save. Find it on
  the sandbox, where it costs nothing.
- **"Unable to uninstall: scheduled jobs" at step 8.** A job is still scheduled. Go back to step
  5; Setup, **Scheduled Jobs**, shows what is left.
- **Receipted or posted gifts in `refused.csv`** (with Giving). The override permissions from
  step 10 were missing. Grant them and run step 11 again: only the refused records are retried.
- **Record numbers changed.** Records named by a running number (relationships and
  affiliations, for example, and with Giving, gifts) get new numbers when they are loaded back.
  The kit loads them in their original order so the numbers stay close, but numbers skipped by
  records deleted long ago close up. Any number you typed yourself, and with Giving, receipt
  numbers, are kept exactly.
- **History and undo do not come across.** Field history and the 30-day window for undoing an
  import end at the move. Created and last modified dates and names come across only if
  Salesforce Support or your Setup has turned on "Set Audit Fields upon Record Creation" for your
  user before step 11; then add `--keep-audit-fields` to the reimport command.
- **"No such column" errors.** The namespace given to the command is wrong: `<old-ns>` for
  `check` and `export`, `<ns>` for `reimport` and `verify`.
