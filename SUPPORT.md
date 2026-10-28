# Report a bug or give feedback

BarnCRM is built in the open, and GitHub is the one place to report a bug, ask whether it fits your organization, point out a documentation problem, or suggest a feature. Issues are read and may shape the roadmap. BarnCRM is a free, self-service project with no support service, so there is no promised response time.

> **Not for production orgs:** BarnCRM is in pilot. We do not recommend installing pilot or testing versions in a production Salesforce org. Use a sandbox, a free Developer Edition org or a scratch org.

## How to report

1. Sign in to GitHub. A free account is enough (create one at https://github.com/signup).
2. Open https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose.
3. Pick the template that fits (see below) and fill it in.
4. Search the [existing issues](https://github.com/Nonprofit-Collaborative/BarnCRM/issues) first. If yours is already there, add a comment or a thumbs-up instead of opening a duplicate.

## Which template to pick

The templates live in `.github/ISSUE_TEMPLATE/`.

- **Bug report:** something does not work as the documentation says it should, or an error appears.
- **Feature request:** a new capability or a change to an existing one.
- **Feedback or question:** general feedback, whether BarnCRM fits how your organization works, or a problem with the documentation.

## What to include in a bug report

- **Steps:** numbered steps that someone else can follow from a fresh org.
- **Expected:** what you thought would happen.
- **Actual:** what happened instead, including any error text word for word. If the Error Log recorded a message, paste it.
- **Version:** the BarnCRM commit or version you are on. Nothing is installable as a package yet, so give the commit of `main` you deployed (`git rev-parse --short HEAD`).
- **Org shape:** Platform only, Sales or Service Cloud, NPSP installed, or Nonprofit Cloud with Person Accounts.
- **Edition:** the Salesforce edition (for example Developer, Enterprise, Nonprofit Power of Us).
- **Screenshots:** helpful, with names, emails, addresses and amounts removed or blurred.

## Never post personal or donor data

Issues on this repository are public. Do not paste names, emails, addresses, gift amounts, or any other record data from your org. Use made-up values, or the sample data from `scripts/org/seed-sample-data.sh`.

## Security problems

Do not open a public issue for a security problem. Report it privately as described in [SECURITY.md](SECURITY.md).

## Related

- [Contributing](CONTRIBUTING.md) if you want to fix something yourself.
- [Overview](docs/overview.md) and the [Admin Guide](docs/admin-guide/README.md) to check how a feature is meant to work.
