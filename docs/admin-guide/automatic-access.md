# Automatic access: give people their BarnCRM role without assigning it by hand

## What it does

On the [Access](access.md) page you give a colleague a role by name. That works well for a
handful of people. If your organization adds staff often, or you have many users already, you
can let Salesforce do it for you with a **user access policy**: a rule in Salesforce Setup that
says "every user who matches these criteria gets these permissions".

BarnCRM does not ship these policies inside its packages. Salesforce can package them only in
managed packages, BarnCRM installs as unlocked packages today, and an org's own policies can
be silently displaced by a shipped one (see "Things to know" below). So this page gives you
the exact definitions instead: you create each one in Setup in a few minutes, and you choose
when it runs.

There are two kinds of policy on this page:

| Policy | What it does | When it runs |
|---|---|---|
| New staff get a role | A new user with your staff profile gets a BarnCRM role (for example Team Member) the moment the user is created | Automatically, when a user is created |
| Module access follows the role (with Giving) | Anyone who holds a BarnCRM role also gets the matching Giving permission set: BarnCRM Admin gets Giving Admin, Fundraising Staff gets Giving Staff, Read Only gets Giving Read Only | Once, when you click **Apply Policy**, and again whenever a matching user record is edited |

The second kind fills the gap described on the Access page: a role carries what Core
provides, and nothing a module adds.

## How to turn it on

User access policies are a Salesforce feature, available in Enterprise and Unlimited
editions. They are off until you turn them on, and you need the **Manage User Access
Policies** permission (System Administrators have it).

1. In Setup, in the Quick Find box, type `User Management Settings` and open it.
2. Turn on **User Access Policies**, and also **Enhanced Interface for User Access
   Policies** if it is offered.
3. In the Quick Find box, type `User Access Policies` and open it. This is where you create
   the policies below.

The **Set up automatic access** link on the Access page in BarnCRM Settings, and on the
access step of the Setup Assistant, opens this page.

## A five-minute walkthrough

Maria's organization takes on new staff every few months. Every new hire gets the
"Team User" profile. She wants each one to have the Team Member role on their first day.

1. In Setup, open **User Access Policies** and click **New**.
2. Fill in the policy as in "Policy 1" below, choosing her own profile, **Team User**, in
   the profile filter.
3. Save. The policy is in **Design** status: it does nothing yet.
4. Click **Automate Policy** (or set the status to Active), choose **when a user is created**,
   and give it an Order (Maria uses 10).
5. The next time someone in Setup creates a user with the Team User profile, that user
   holds the Team Member role straight away. Maria checks on the Access page: the new name
   is on the Team Member card.

If your org has Giving, Maria also creates Policy 2, then clicks **Apply Policy** once and
applies it to every user it lists. Everyone who already holds BarnCRM Admin now also holds
Giving Admin.

## The policy definitions

Create each policy with **New** on the User Access Policies page, using exactly these values.
The names in the Action and Filter columns are what you pick in the lists; the API names
are in brackets.

### Policy 1: new staff get a role

| Field | Value |
|---|---|
| Label | BarnCRM: new staff get Team Member |
| Description | Gives every new active user with our staff profile the BarnCRM Team Member role. |
| Filter 1 | Profile, equals, **your own staff profile** (it differs in every org) |
| User field filter | Active (`IsActive`) equals `true` |
| Action | Grant, Permission Set Group, **Team Member** (`Program_Staff`) |
| Trigger | When a user is created |
| Order | 10 |

The API names in brackets are the roles' original names and never change, so a policy keeps
working across upgrades. Change the role to suit: **Coordinator** (`Volunteer_Coordinator`), **Read Only**
(`Read_Only`), **BarnCRM Admin** (`BarnCRM_Admin_Group`) or, with Giving, **Fundraising
Staff** (`Fundraising_Staff`). With Giving, add a second action to the same policy so the new
user gets the module's permission set at the same time, for example Grant, Permission Set,
**Giving Staff** (`Giving_Staff`) alongside Fundraising Staff. One policy per staff profile.

### Policies 2 to 4: module access follows the role (with Giving)

These apply only when the Giving module is installed.

| Policy | Filter 1 | Action | Order |
|---|---|---|---|
| 2. BarnCRM: admins also get Giving Admin | Permission Set Group equals **BarnCRM Admin Group** (`BarnCRM_Admin_Group`) | Grant, Permission Set, **Giving Admin** (`Giving_Admin`) | 20 |
| 3. BarnCRM: fundraising staff also get Giving Staff | Permission Set Group equals **Fundraising Staff** (`Fundraising_Staff`) | Grant, Permission Set, **Giving Staff** (`Giving_Staff`) | 30 |
| 4. BarnCRM: read only also get Giving Read Only | Permission Set Group equals **Read Only** (`Read_Only`) | Grant, Permission Set, **Giving Read Only** (`Giving_Read_Only`) | 40 |

For each one, also add the user field filter Active (`IsActive`) equals `true`, and set the
trigger to **when a user is created or updated**.

Then, on each policy, click **Apply Policy** once and apply it to all the users it lists.
That is the step that reaches the people who already hold a role.

### For admins who deploy with the CLI: the same policies as metadata

The folder
[`docs/admin-guide/samples/user-access-policies`](samples/user-access-policies) holds
Policies 2 to 4 as Metadata API files, with a `package.xml`. Policy 1 is not there, because
its profile is different in every org. Deploy them to an org that has user access policies
turned on with:

`sf project deploy start --metadata-dir docs/admin-guide/samples/user-access-policies --target-org <your org>`

They arrive in Design status whatever the file says (Salesforce never deploys a policy as
active), so nothing changes until an administrator automates or applies them. If your
BarnCRM packages were installed with a namespace, put the namespace prefix in front of each
permission set and group name in the files first.

## Things to know

- **A policy runs when a user record is created or updated, not when a role is given.**
  Giving someone BarnCRM Admin on the Access page does not edit their user record, so
  Policy 2 does not run for them on its own. Click **Apply Policy** again after a round of
  role changes, or edit and save the person's user record.
- **Only one policy applies to a user at a time.** When a user matches several active
  policies, Salesforce applies only the one with the lowest Order. Someone who holds both
  BarnCRM Admin and Read Only gets Policy 2 and not Policy 4. This is also why BarnCRM does
  not ship policies: a shipped policy with a low Order would quietly stop one of your own
  policies from applying.
- **A policy never takes access away unless it says Revoke.** When someone stops matching a
  policy (they change profile, or lose a role), what the policy gave them stays. Remove it on
  the Access page or in Setup.
- **The license still has to fit.** A role needs a Salesforce or Salesforce Platform license.
  If a policy grants a role to a user whose license cannot hold it, the grant fails and the
  failure is listed under **Recent User Access Changes** on the policy.
- **Limits.** An org can have up to 200 active policies. Each policy can filter on up to three
  of profile, role, permission set or group, package license, public group or queue, plus up
  to ten user fields.

## Common mistakes

**The new user did not get the role.** Check that the policy is automated (not still in
Design), that its trigger includes "created", that the user's profile is the one in Filter 1,
and that no other active policy with a lower Order also matches the user. Open the policy and
look at **Recent User Access Changes** for the reason.

**You cannot find User Access Policies in Setup.** The feature is off until you turn it on in
User Management Settings, and it is not available in Professional Edition. The Access page
works in every edition: give roles there by hand.

**Applying Policy 2 changed nothing.** The people you expected may not hold the BarnCRM Admin
role itself but only the BarnCRM Admin permission set (the person who installed BarnCRM can be
in that position). Give them the role on the Access page, then apply the policy again.
