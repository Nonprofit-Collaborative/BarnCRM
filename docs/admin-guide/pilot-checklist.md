# Pilot Checklist

## What It Does

This page is the checklist for an organization trying BarnCRM during its pilot. It lists what
to set up, what to try in the first weeks, and how to report what you find, so your trial
tells you whether BarnCRM fits and tells the project what to fix. BarnCRM is free and
self-service: this checklist is everything you need, and there is no support service or
promised response time.

> **Not for production orgs:** BarnCRM is in pilot. Install it in a sandbox, a free Developer
> Edition org or a scratch org, never in a production Salesforce org.

## How to Turn It On

Before you start:

1. Pick an org that matches how your organization uses Salesforce, so the trial tests your
   shape: Platform only, Sales or Service Cloud, NPSP installed, or Nonprofit Cloud.
2. Check the edition and room needed in [Installing BarnCRM](installing.md), then install.
3. Run the **Setup Assistant** to the end ([Setup Assistant](setup-assistant.md)).
4. Run **Health Check** in Org Optimizer and fix anything it marks as needing attention
   ([Health Check](health-check.md)).
5. Load the sample data, or a small copy of your own data with names changed
   ([Sample Data](sample-data.md)).
6. Switch on the error digest, so a failure reaches you without looking
   ([Error Log](error-log.md)).
7. Give each colleague who will try BarnCRM a role (BarnCRM Staff or BarnCRM Read Only) and
   have them sign in once ([Access](access.md)).

## A Five-Minute Walkthrough

The first week, one task a day:

1. Add a household with two people, and an organization with an affiliation.
2. Import a small spreadsheet with Super Importer, then undo it from Data Jobs.
3. Find a group of people with Find and export them.
4. If you use Giving, enter a gift, a soft credit and a gift batch.
5. Open Org Optimizer, Errors. If an entry is there, read its message and do what it says.

Every week after that:

1. Do your real work in BarnCRM for at least one task you would normally do elsewhere.
2. Look at the Error Log card. For anything that looks like a BarnCRM bug, click
   **Copy for Bug Report**, read the copied text, and paste it into a new issue on GitHub with
   what you were doing ([SUPPORT.md](../../SUPPORT.md)).
3. Note anything that took more than a few minutes to work out, and open a **Feedback or
   question** issue for it. A step that needed Salesforce Setup is worth reporting too.

At the end of the trial, open one **Feedback or question** issue saying your org shape, which
modules you tried, what worked and what stopped you.

## Common Mistakes

- **Trying it in production.** Pilot versions change often and are not ready for live data.
- **Pasting record data into an issue.** GitHub issues are public. Use **Copy for Bug Report**,
  which leaves out names, emails and values, and blur any screenshot.
- **Testing only with the administrator.** Sign in as a BarnCRM Staff user too: most problems
  people meet are about what their role lets them see.
- **Waiting for someone to reply before going on.** Issues are read and may shape the roadmap,
  but nobody is on call. Keep trying the rest of the checklist.
