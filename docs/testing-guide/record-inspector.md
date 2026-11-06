# Record Inspector

Scripts for the Record Inspector page and its **Inspect This Record** button (C-55). Setup detail: [Record Inspector](../admin-guide/record-inspector.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded.

## T-RI-01: Inspect a Record and Search Its Fields

**Purpose:** Confirm an admin opens the Record Inspector page from a record, sees every readable field, including ones off the layout, searches them and copies an API name.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); Core's Contact record page active (it carries the **Inspect This Record** button).
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open a sample Contact. | The sidebar shows an **Inspect This Record** button, and no Record Inspector card. |
| 2 | Click **Inspect This Record**. | The **Record Inspector** page opens and reads the record at once: the Contact's name (a link) and **Contact** above a table of fields sorted by **Field**, with **API Name**, **Type** and **Value**, and a count such as "120 fields". It includes a field that is not on the Contact page layout. |
| 3 | Type `email` in **Search Fields**. | Only fields with email in the label, API name, type or value remain, and the count updates. |
| 4 | Clear the search, then click **Copy** beside the **Last Name** row. | A short confirmation shows. Pasting elsewhere gives `LastName`. |
| 5 | Click **Open in Setup** beside **Last Name**. | A new tab opens on the Last Name field of Contact in Object Manager. |
| 6 | Go back, then click **Open in Find**. | The Find tab opens with **Contact** already chosen as the kind of record. |
| 7 | Go back, change the Contact's phone number on its record page, return to the Record Inspector page and click **Refresh**. | The **Phone** value shows the new number. |
| 8 | Click the Contact's name above the table. | The Contact's record page opens. |

**Cleanup:** none.

## T-RI-02: Open the Record Inspector Page by Hand

**Purpose:** Confirm the page works with no record, with a pasted ID and with a pasted link.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Admin** app. | **Record Inspector** is in the navigation, just before **Error Log**, which is last. |
| 2 | Click **Record Inspector**. | The page shows a **Record ID or Link** box, an **Inspect** button and a short note on what to paste. No table. |
| 3 | Type `not a record` and click **Inspect**. | An error says it is not a record ID or a link to a record. |
| 4 | Copy the address of an Organization's record page, paste it in the box and press Enter. | The page reads the Organization: its name and **Account** above the table. The address bar now names the record, so the link can be shared with another admin. |
| 5 | Paste the 18 character ID of a Contact and click **Inspect**. | The page reads the Contact. |

**Cleanup:** none.

## T-RI-03: The Inspector Shows Only What the Person May Read

**Purpose:** Confirm field security and permissions are respected.
**Prerequisites:** admin and staff (see [Test users](before-you-test.md#test-users)); Core's Contact record page active.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Setup**, as the admin, remove read access to a Contact field such as **Birthdate** for the admin's profile or permission set, then inspect a Contact. | **Birthdate** is not in the table. |
| 2 | Restore the access and click **Refresh**. | **Birthdate** is back. |
| 3 | As staff (no Manage BarnCRM Settings), open the same Contact. | No **Inspect This Record** button is shown. |
| 4 | As staff, open the App Launcher and search for `Record Inspector`. | Nothing is found: the tab is for BarnCRM Admins only. |

**Cleanup:** Restore any field access you changed.
