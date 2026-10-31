# Record Inspector

Scripts for the Record Inspector component (C-55). Setup detail: [Record Inspector](../admin-guide/record-inspector.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded.

## T-RI-01: Inspect a Record and Search Its Fields

**Purpose:** Confirm an admin can see every readable field of a record, including ones off the layout, search them and copy an API name.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)); Core's Contact record page active (it carries the Record Inspector). Step 1 shows how to add it to another page.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Setup**, open a Contact record, choose **Edit Page** and drag **Record Inspector** onto the page. Save and activate. | The component is in the list. The page saves. |
| 2 | Open a sample Contact. | A **Record Inspector** card shows with an **Inspect This Record** button and no table. |
| 3 | Click **Inspect This Record**. | A table of fields sorted by **Field**, with **API Name**, **Type** and **Value**, and a count such as "120 fields". It includes a field that is not on the Contact page layout. |
| 4 | Type `email` in **Search Fields**. | Only fields with email in the label, API name, type or value remain, and the count updates. |
| 5 | Clear the search, then click **Copy** beside the **Last Name** row. | A short confirmation shows. Pasting elsewhere gives `LastName`. |
| 6 | Click **Open in Setup** beside **Last Name**. | A new tab opens on the Last Name field of Contact in Object Manager. |
| 7 | Click **Open in Find**. | The Find tab opens with **Contact** already chosen as the kind of record. |
| 8 | Click **Refresh** after changing the Contact's phone number on the page. | The **Phone** value shows the new number. |

**Cleanup:** Remove the component from the page if you do not want it kept.

## T-RI-02: The Inspector Shows Only What the Person May Read

**Purpose:** Confirm field security and permissions are respected.
**Prerequisites:** admin and staff (see [Test users](before-you-test.md#test-users)); the Record Inspector on the Contact page.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Setup**, as the admin, remove read access to a Contact field such as **Birthdate** for the admin's profile or permission set, then inspect a Contact. | **Birthdate** is not in the table. |
| 2 | Restore the access and click **Refresh**. | **Birthdate** is back. |
| 3 | As staff (no Manage BarnCRM Settings), open the same Contact. | The Record Inspector card is not shown. |

**Cleanup:** Restore any field access you changed.
