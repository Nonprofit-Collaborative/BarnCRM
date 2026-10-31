# Creating a New Field From an Import

## 1. What It Does

When a file has a column your org has no field for, the import's column step can create the field
for you. Choose **Create New Field** in the column's field picker. BarnCRM suggests a label (the
column heading), an API name and a type (from the column's values), creates the field, gives
BarnCRM's permission sets access to it, and maps the column to it. You never leave the import.

Supported types: Text, Long Text Area, Number, Currency, Percent, Date, Date/Time, Checkbox,
Email, Phone, URL and Picklist. A picklist's values are the column's distinct values (at most 200).

The field is created on the object the import loads: the template's object for One Kind of
Record, or a person (Contact) or an organization (Account) for People and Organizations.

## 2. How to Turn It On

1. Give yourself the **BarnCRM Metadata Admin** permission set (it is in no role on purpose).
   You also need Import access and the Salesforce permissions **Customize Application** and
   **Modify Metadata**, which the System Administrator profile has.
2. Open **BarnCRM Settings**, **Import** page, **Create Fields From an Import**, and select
   **Set Up Connection**. This creates a Named Credential called `Barn_Org_Connection` that lets
   BarnCRM call your org's own Metadata API. It is done once for the org and stores no password.
3. Salesforce creates the Named Credential with callouts turned off, and only an administrator
   can turn them on. The status reads **Set up, one step left**, with these steps:
   1. In Setup, enter **Named Credentials** in Quick Find and open **Named Credentials**.
   2. Select **BarnCRM: this org**, then **Edit**.
   3. Turn on **Enabled for Callouts** and select **Save**.
   4. Back on the Import page, select **Check Again**. The status reads **Connected**.

Until the status reads **Connected**, **Create New Field** shows the Setup fallback below.

Without the connection, **Create New Field** still opens. It shows the field's details as text
to copy, with the steps to create the field in Setup, and **Refresh Fields** to pick it up.

## 3. A Five-Minute Walkthrough

1. Import a file of people with a column **T-Shirt Size** holding S, M, L and XL.
2. In the column step, open the field picker for **T-Shirt Size** and choose **Create New Field**.
3. The dialog suggests the label **T-Shirt Size**, the API name `T_Shirt_Size__c`, the type
   **Picklist** with the values S, M, L and XL, and the object **Person (Contact)**.
4. Optionally choose one more permission set to give read and edit access to.
5. Select **Create Field**. In under a minute the dialog says the field was created, and the
   column is mapped to it.
6. Preview and import as usual.

## 4. Who Gets Access

| Permission set | Access |
|---|---|
| BarnCRM Admin | Read and edit |
| BarnCRM Staff | Read and edit |
| BarnCRM Read Only | Read |
| The permission set you choose (optional) | Read and edit |

A permission set that cannot read the object is skipped, and the Error Log says so. Page
layouts are not changed: add the field to a layout in Setup if people should see it on the
record page.

## 5. Common Mistakes

- **"This API name is already used on this object."** Pick another name, or map the column to
  the existing field.
- **"The connection is not set up."** Set it up on BarnCRM Settings, or follow the Setup steps
  the dialog shows.
- **"The connection is set up but not turned on."** Turn on **Enabled for Callouts** on the Named
  Credential **BarnCRM: this org** (section 2, step 3), then select **Check Again**.
- **"You need the Customize Application and Modify Metadata permissions."** BarnCRM creates the
  field as you, so you need the same permissions Setup needs.
- **"Your org did not accept BarnCRM's connection."** The Metadata API refused the call. Create
  the field in Setup from the details the dialog shows, then select **Refresh Fields**.
- **"Salesforce refused the field."** The message names what Salesforce refused (for example,
  the org's custom field limit). The Error Log keeps the full detail.
- **Production first.** A new field is a change to the org. Try it in a sandbox if your org
  manages changes there first.
- **Uninstalling BarnCRM** leaves the fields it created; they are your org's fields. Delete the
  Named Credential `Barn_Org_Connection` in Setup first, since it uses BarnCRM's External
  Credential, and whenever you no longer want the connection.
