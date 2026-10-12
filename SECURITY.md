# Security Policy

## Supported versions

BarnCRM is at Phase 0 / v0.1. There are no releases: no package versions exist, nothing is installable, and the namespace is not registered.

| Version | Supported |
|---|---|
| `main` | Yes, this is the only supported line |
| Released versions | None yet |

Once versions are published, this table will list which of them receive security fixes.

## Reporting a vulnerability

Please report security issues privately, through GitHub private vulnerability reporting on this repository: go to the Security tab of https://github.com/Nonprofit-Collaborative/BarnCRM and choose "Report a vulnerability".

Do not open a public issue, a pull request, or a discussion post for a suspected vulnerability. Do not post details on social media or a community forum before we have had a chance to respond.

If you cannot use private vulnerability reporting, say so in a GitHub issue that contains no details of the problem, and a maintainer will arrange a private channel with you.

## What to include

The more of this you can give us, the faster we can confirm and fix:

- What the issue is and what an attacker could do with it.
- Which package and which component (Core, Giving, Volunteers, Programs, Funders, Connect; object, Apex class, LWC, permission set, REST endpoint).
- The org shape you saw it on: Platform only, Sales and Service Cloud, NPSP installed, or Person Accounts enabled.
- Steps to reproduce, ideally in a fresh scratch org created with `scripts/org/create-scratch-org.sh`.
- The commit or version you tested.
- Any proof of concept code, logs, or screenshots (with real constituent data removed).
- How you would like to be credited, or that you prefer not to be.

## Response targets

- We acknowledge a report within 5 business days.
- After acknowledgement we confirm or dispute the finding and tell you our assessment and a rough timeline.
- We keep you updated as we work on a fix, and we tell you when it lands.
- We coordinate public disclosure with you, and credit you in the release notes unless you prefer otherwise.

These are targets for a small volunteer project, not a contractual commitment.

## Scope notes

BarnCRM is a Salesforce managed package that runs inside your own Salesforce org, which shapes what a vulnerability here can be:

- **No external callouts by default.** The packages do not call out to third-party services during normal operation.
- **No data leaves the org.** There is no BarnCRM server, no hosted component, and no vendor copy of your constituent data.
- **Telemetry is opt-in and off by default**, and anonymous when it is on.
- **REST endpoints exist only in the Connect package** (the inbound gift API), are authenticated, and are documented. Connect is optional and is not installed unless you install it.
- Issues in Salesforce itself, rather than in this code, belong to Salesforce: report those through https://trust.salesforce.com. We are happy to help you tell the difference.
- Org configuration mistakes made by an administrator (over-broad profiles, sharing settings, guest user access) are not vulnerabilities in this project, but if our defaults or our documentation encouraged the mistake, that is a real issue and we want to hear it.

## Our practices

- Salesforce Code Analyzer (PMD, ESLint, retire-js, Graph Engine for CRUD and FLS) runs on every pull request and must show zero high or critical findings.
- CRUD and field-level security are enforced in user mode (`WITH USER_MODE` or `Security.stripInaccessible`) on queries and DML that touch user-facing data.
- Apex is `with sharing` by default.
- No hard-coded IDs, and no secrets in metadata or source.
- Automated tests run on four org shapes on every pull request.
- Salesforce security review is required before any AppExchange listing, and we design for it from v0.1 rather than remediating at the end.

## Safe harbor

We will not pursue or support legal action against anyone who reports a vulnerability in good faith, follows this policy, tests only against their own org or a scratch org they created, avoids privacy violations and service disruption, and gives us reasonable time to fix the issue before disclosing it publicly.
