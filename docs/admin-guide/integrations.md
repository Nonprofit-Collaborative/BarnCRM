# Integrations

## What It Does

The Integrations page in BarnCRM Settings is a roadmap of other products BarnCRM plans to work
with. It lists each one with what it does, who maintains it, what it costs, a link to it, and a
note on what BarnCRM knows about using the two together. It also tells you whether a product is
installed in your org.

Every integration is **In Progress**. That means planned and not built: nothing on the page is
integrated with BarnCRM yet, and BarnCRM has not tested these products with itself unless a
product's note says so. BarnCRM does not depend on any of them, and installing or removing one
changes nothing in BarnCRM. The page exists to show the direction and to collect interest.

## How to Turn It On

There is nothing to turn on.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM**.
2. Click **BarnCRM Settings**, then **Integrations** in the left navigation.

Everyone who can open BarnCRM Settings sees the page. It has no settings to change, so it shows no save bar.

## What the Page Shows

Products are grouped:

- **Complementary Apps**: free community apps that add something BarnCRM does not do.
- **In Development**: projects that are not finished themselves.
- **Alternatives to BarnCRM Modules**: apps that overlap a BarnCRM module. They appear here only
  when installed in your org. If you have none, the heading does not appear at all. For each,
  use one or the other for the same records, not both. BarnCRM may offer a migration path to the
  matching module in a future release, with no date promised.

Each product shows:

- Its name, an **In Progress** status, and **Installed in this org** or **Not installed**. The
  installed check looks for one of the product's own objects in your org, so it also works for a
  product installed any way. **Check again** reads your org again.
- A one-line description, who maintains it, and its cost and license.
- **Compatibility with BarnCRM**: what is known about using the two together, written
  honestly. Where it says "not yet tested", it means exactly that.
- **Learn More**, which opens the product's own page in a new tab. The page has no install
  links: find and install a product from its own page.

Some notes carry details to read before you try a product. For example, an event registration
app that publishes public pages needs a Salesforce Site, which runs as a guest user: set that
up with care, and review what a guest user can see.

## Request an Integration

At the bottom of the page:

- **Request an Integration** opens a form on GitHub where you name a product you use and what
  you would want it to do with BarnCRM. Do not post personal or donor data: the form is public.
- **Propose an Integration for Your Product** is for people who build or maintain a product. It
  opens a second form. **How an Integration Is Built** explains the rules a provider follows.

BarnCRM is self-service. A request is a public suggestion that helps shape the roadmap. It is
not a support ticket, and nothing on the page promises a reply, support or a date.

## Add or Change a Listing

The list is custom metadata, so a new product needs only a new record of the type **Integration
App**, with no code. Open Setup, **Custom Metadata Types**, **Integration App**, **Manage
Integration App**. Fields:

- **Category** is `Complement`, `InDevelopment` or `Alternative`.
- **Status** is `InProgress` (planned, not built) or `Available`.
- **Detection Objects** lists the product's own objects, separated by semicolons: write a
  packaged object as `namespace.Object__c`, with a dot where the platform has two underscores.
- **Show Only When Installed** hides the product from an org that does not have it.
- **Migration Path** is a short line, shown under the note, for a future migration.

See [BarnCRM Settings](barncrm-settings.md) for the rest of the console.
