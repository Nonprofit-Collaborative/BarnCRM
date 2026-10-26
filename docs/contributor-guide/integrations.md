# Proposing and building an integration

This page is for people who build or maintain a product and want it to work with BarnCRM. The
Settings, Integrations page (see the [admin guide](../admin-guide/integrations.md)) lists the
products BarnCRM plans to work with. Every listing is In Progress today: nothing is built, and
building integrations waits until Core is finished.

BarnCRM is open source and self-service. A proposal is a public suggestion. It does not promise
a reply, support or a date.

## Propose one

Open the [integration proposal form](https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new?template=integration-partner.yml).
It asks for the product name and link, what the product does, your role (a role only, never
personal details), the integration points, whether the product is open source or paid, and
whether you would maintain the integration. The issue is public: post no personal or donor data.

An organization that uses a product and wants it supported uses the
[request form](https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new?template=integration-request.yml).

## The rules an integration follows

- **Core depends on nothing.** Core never references another product's objects, classes or
  namespace in a way that needs the product to be installed (plan Section 4.1, ADR-0009,
  ADR-0013). Core only detects a product, by describe, with names held as data in the
  `Integration_App__mdt` catalog. A listing needs only a record there.
- **An integration is a separate package.** Any behavior that touches a product lives in its own
  package that depends on Core, installed only by an org that wants it, like a module (ADR-0003,
  ADR-0059). It must also run on an org with the product absent.
- **No namespace is hard-coded** in Core. The package keeps its own names as strings used for
  lookups.
- **Decide it in an ADR.** A new integration needs an Architecture Decision Record in
  `docs/architecture/decisions/` (an ADR-NEXT file on a branch) that says what is read and
  written, who owns the data, and what happens when the product is removed.
- **Update the canonical model first** for any object or field, then the four guides and the
  feature catalog.
- **Test it.** Apex tests run as a created user, and cover the product absent and present
  (inject the describe result, as `IntegrationAppService` does). Do not call another product's
  code in a test that must run on a Platform-only org.
- **Settings stay in the console.** Any admin setting lives in BarnCRM Settings, not only in
  Setup.

Read [CONTRIBUTING.md](../../CONTRIBUTING.md) for the pull request rules and the DCO sign-off.
