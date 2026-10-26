# Addresses

Scripts for address records, the default address, the person address setting and the seasonal address swap. Setup detail: [Addresses](../admin-guide/addresses.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. The **Addresses** feature must be on (BarnCRM Settings, **General**). The Garcia Family's sample address is 6830 Sunset Ln, Springfield, IL 62756.

## T-ADDR-01: Addresses card and adding a seasonal address

**Purpose:** the card shows the default address and adds a new one.
**Prerequisites:** staff user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **The Garcia Family**. | The **Addresses** card shows one **Home** address, 6830 Sunset Ln, Springfield IL 62756, with a **Default** badge and no **Set as default** button. |
| 2 | Select **Add address** on the card. | A **New address** form opens with Type, Street, City, State, Postal Code, Country and the four seasonal boxes. |
| 3 | Enter Type **Seasonal**, Street `4120 East Camelback Road`, City `Phoenix`, State `AZ`, Postal Code `85018`, Country `United States`, Seasonal Start Month `1`, Start Day `1`, End Month `3`, End Day `31`. Select **Add address** in the form. | Toast **Address saved.** A second card reads **Used from January 1 to March 31**, with a **Set as default** button and no badge. |
| 4 | Open the **Addresses** tab. | Both Garcia addresses are listed. |

**Cleanup:** keep the Phoenix address for T-ADDR-02 to T-ADDR-07.

## T-ADDR-02: Set as default, and back

**Purpose:** Set as default copies the address to the household and its members, and can be moved back.
**Prerequisites:** staff user, T-ADDR-01 done, **When a person's address is edited** set to **Everyone in the household moves together** (ships that way).

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Set as default** on the Phoenix card. | Toast **This is now the default address, and it has been copied to the standard address fields.** The **Default** badge moves to Phoenix. |
| 2 | Look at the household's **Details**. | Billing Address reads Phoenix, AZ 85018, without a reload. |
| 3 | Open Harper Garcia. | Her mailing address is Phoenix. |
| 4 | Undo: back on the household, select **Set as default** on the Home card. | The badge returns to Home; Billing Address reads Springfield again. Both addresses are still on the card. |

**Cleanup:** None.

## T-ADDR-03: Bad input is refused

**Purpose:** address validation messages appear and nothing is saved.
**Prerequisites:** admin, The Garcia Family.

| Step | Action | Expected result |
|---|---|---|
| 1 | **Add address** with Type **Seasonal** and Street `1 Test St`, no seasonal dates. Submit with **Add address** in the form. | Refused: **A seasonal address needs a start month, a start day, an end month, and an end day so we know when to use it.** |
| 2 | Set Start Month `4`, Start Day `31`, End Month `5`, End Day `1`. Submit again. | Refused: **A seasonal day is a day its month has: 1 to 31, or 1 to 30 in April, June, September and November, or 1 to 29 in February.** |
| 3 | Set Start Month `13`, Start Day `1`. Submit again. | Refused: **A seasonal month is a number from 1 (January) to 12 (December).** |
| 4 | Set Start Month `11`, Start Day `1`, End Month `3`, End Day `31`. Submit again. | Saved, shown as **Used from November 1 to March 31** (one range across New Year). |
| 5 | Open the default Home address from the **Addresses** tab, untick **Default**, and save. | Refused: **This is the address in use. To change that, make another address the default, or delete this one.** |
| 6 | On the **Addresses** tab select **New**, fill **Household or Organization** with The Garcia Family and **Person** with Harper Garcia, add a street, and save. | Refused: **An address belongs to one household, one organization, or one person. Choose only one.** |

**Cleanup:** delete the November to March address.

## T-ADDR-04: A person's address edit moves the household

**Purpose:** with the default setting, editing a member's mailing address moves everyone and keeps history.
**Prerequisites:** admin, setting **Everyone in the household moves together**. Mailing Address is in the person page's **Reaching This Person** section.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Harper Garcia, change Mailing Street to `12 New Test Rd` and save. | Saved. |
| 2 | Open The Garcia Family. | A new **Home** card, 12 New Test Rd, carries **Default**. The old Sunset Ln card is still there without the badge. Billing Address shows the new street. |
| 3 | Open Luis Garcia. | His mailing street is **12 New Test Rd**. |
| 4 | Undo: on the household, **Set as default** on the Sunset Ln card. | Household and members are back on Sunset Ln. |

**Cleanup:** delete the 12 New Test Rd address.

## T-ADDR-05: A person's address edit gives a personal address

**Purpose:** with **Only that person moves**, the edit stays with one person.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Addresses**, set **When a person's address is edited** to **Only that person moves** and save. | Saved. |
| 2 | On Diego Garcia, change Mailing Street to `9 Dorm Test Hall` and save. | Saved. |
| 3 | Look at Diego's **Addresses** card. | A card for 9 Dorm Test Hall with **Default**. |
| 4 | Open The Garcia Family and Luis. | Both still show Sunset Ln. |
| 5 | Set the setting back to **Everyone in the household moves together** and save. | Saved. |

**Cleanup:** delete Diego's personal address and set his Mailing Street back to 6830 Sunset Ln.

## T-ADDR-06: Schedule and run the seasonal swap

**Purpose:** the swap can be scheduled and run from settings, and swaps a seasonal address in.
**Prerequisites:** admin, T-ADDR-01 done.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Addresses**. | The **Seasonal address swap** section reads **The nightly swap is not scheduled, so seasonal addresses will not move on their own.** |
| 2 | Select **Schedule nightly run**. | It reads **The swap runs every night at 12:30 AM, in your organization's time zone.** with the next run date below. The button now reads **Stop nightly run**. |
| 3 | Edit the Phoenix address so its season runs from yesterday to a date next month. | Saved. |
| 4 | Select **Run the swap now**. | **The swap has started. Refresh this page in a minute to see what it did.** |
| 5 | Wait a minute and refresh. | **Seasonal addresses last swapped** shows a time a minute ago and **1 moved to a seasonal address, 0 moved back, 0 could not be changed.** |
| 6 | Open The Garcia Family. | **Default** is on Phoenix; Billing Address reads Phoenix; the Home address record has **Replaced By Seasonal** ticked. |
| 7 | Open **Home**. | The **Seasonal addresses last swapped** tile shows the same time and sentence. |

**Cleanup:** keep the schedule for T-ADDR-07.

## T-ADDR-07: The season ends and the address moves back

**Purpose:** the swap puts the replaced address back when a season ends.
**Prerequisites:** admin, T-ADDR-06 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set the Phoenix address's end month and day to yesterday and save. | Saved. |
| 2 | **BarnCRM Settings**, **Addresses**, **Run the swap now**, wait a minute, refresh. | **0 moved to a seasonal address, 1 moved back, 0 could not be changed.** |
| 3 | Open The Garcia Family. | **Default** is back on the Home address; Billing Address reads Springfield. |
| 4 | Select **Stop nightly run**. | The page reads **The nightly swap is not scheduled, so seasonal addresses will not move on their own.** |

**Cleanup:** delete the Phoenix address.

## T-ADDR-08: Overlapping seasons and deleting the default

**Purpose:** overlapping seasons are reported, and a deleted default is replaced by a non-seasonal address.
**Prerequisites:** admin, a test household: create contact `Ada` `Testaddr` with no account (a household is created).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the household, add a **Home** address `1 Year Round Test St`. | It is the first address, so it gets **Default** at once. |
| 2 | Add a **Work** address `2 Work Test St`, then two **Seasonal** addresses whose seasons both cover today. | Both save. |
| 3 | **Run the swap now** and refresh after a minute. | The summary counts one move. The **Error Log** has a warning: **Two seasonal addresses for the same household or person cover today, so BarnCRM used the one that was added first.** The first seasonal address is the default. |
| 4 | Delete both seasonal addresses. | **Default** goes to a non-seasonal address (the most recently created: 2 Work Test St), never a seasonal one. |

**Cleanup:** delete Ada Testaddr, the household and its addresses.

## T-ADDR-09: Read-only user

**Purpose:** a read-only user sees addresses and the swap status but changes nothing.
**Prerequisites:** read-only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open The Garcia Family. | The **Addresses** card lists the addresses. |
| 2 | Look at a non-default address. | It shows no **Set as default** button. The **Default** badge still shows on the default one. |
| 3 | Look at the card header. | There is no **Add address** button. |
| 4 | Open **BarnCRM Settings**, **Addresses**. | The last run shows; **Schedule nightly run** (or **Stop nightly run**) and **Run the swap now** are disabled, with **You can see when the swap last ran. Changing the schedule needs the Manage BarnCRM Settings permission.** |

**Cleanup:** None.

## T-ADDR-10: State and country codes with State and Country Picklists on

**Purpose:** an address typed with codes reaches the standard address fields in an org with State and Country Picklists.
**Prerequisites:** staff user, in an org where Setup, **State and Country/Territory Picklists** are turned on. The Garcia Family with Harper Garcia as a member.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Garcia Family, select **Add address**. Enter Type **Home**, Street `55 Lake Street`, City `Chicago`, State `IL`, Postal Code `60601`, Country `US`. Select **Add address** in the form, then **Set as default** on the new card. | Toast **This is now the default address, and it has been copied to the standard address fields.** |
| 2 | Look at the household's **Details**. | Billing Address reads Chicago, Illinois 60601, United States. |
| 3 | Open Harper Garcia. | Her mailing address reads Chicago, Illinois, United States. |

**Cleanup:** set the previous address as the default again and delete the Chicago address.
