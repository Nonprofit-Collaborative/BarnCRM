# Addresses

Scripts for address records, the primary address, the Address Updates setting, the two household moves and the seasonal address swap. Setup detail: [Addresses](../admin-guide/addresses.md).

Before you start: an org from [Before you test](before-you-test.md), with Core deployed and sample data loaded unless a script says otherwise. In a [Core-only real-org sandbox](before-you-test.md#core-only-real-org-sandbox) there is no sample data: create the Zztest fixture first and read Garcia as Zztest. The **Addresses** feature must be on (BarnCRM Settings, **General**). The Garcia Family's sample address is 6830 Sunset Ln, Springfield, IL 62756.

## T-ADDR-01: Addresses card and adding a seasonal address

**Purpose:** the card shows the primary address and adds a new one.
**Prerequisites:** staff user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **The Garcia Family**. | The **Addresses** card shows one **Home** address, 6830 Sunset Ln, Springfield IL 62756, with a **Primary** badge and no **Set as Primary** button. |
| 2 | Select **Add address** on the card. | A **New address** form opens with Type, Street, City, State, Postal Code, Country and the four seasonal boxes. |
| 3 | Enter Type **Seasonal**, Street `4120 East Camelback Road`, City `Phoenix`, State `AZ`, Postal Code `85018`, Country `United States`, Seasonal Start Month `1`, Start Day `1`, End Month `3`, End Day `31`. Select **Add address** in the form. | Toast **Address saved.** A second card reads **Used from January 1 to March 31**, with a **Set as Primary** button and no badge. |
| 4 | Open the **Addresses** tab. | Both Garcia addresses are listed. |

**Cleanup:** keep the Phoenix address for T-ADDR-02 to T-ADDR-07.

## T-ADDR-02: Set as Primary, and Back

**Purpose:** Set as Primary copies the address to the household and its members, and can be moved back.
**Prerequisites:** staff user, T-ADDR-01 done, **Address Updates** set to **Everyone in the household moves together** (ships that way).

| Step | Action | Expected result |
|---|---|---|
| 1 | Select **Set as Primary** on the Phoenix card. | Toast **This is now the primary address, and it has been copied to the standard address fields.** The **Primary** badge moves to Phoenix. |
| 2 | Look at the household's **Details**. | Billing Address reads Phoenix, AZ 85018, without a reload. |
| 3 | Open Harper Garcia. | Her mailing address is Phoenix. |
| 4 | Undo: back on the household, select **Set as Primary** on the Home card. | The badge returns to Home; Billing Address reads Springfield again. Both addresses are still on the card. |

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
| 5 | Open the primary Home address from the **Addresses** tab, untick **Primary**, and save. | Refused: **This is the address in use. To change that, make another address the primary, or delete this one.** |
| 6 | On the **Addresses** tab select **New**, fill **Household or Organization** with The Garcia Family and **Person** with Harper Garcia, add a street, and save. | Refused: **An address belongs to one household, one organization, or one person. Choose only one.** |

**Cleanup:** delete the November to March address.

## T-ADDR-04: A person's address edit moves the household

**Purpose:** with the default setting, editing a member's mailing address moves everyone and keeps history.
**Prerequisites:** admin, setting **Everyone in the household moves together**. Mailing Address is in the person page's **Reaching This Person** section.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Harper Garcia, change Mailing Street to `12 New Test Rd` and save. | Saved. |
| 2 | Open The Garcia Family. | A new **Home** card, 12 New Test Rd, carries **Primary**. The old Sunset Ln card is still there without the badge. Billing Address shows the new street. |
| 3 | Open Luis Garcia. | His mailing street is **12 New Test Rd**. |
| 4 | Undo: on the household, **Set as Primary** on the Sunset Ln card. | Household and members are back on Sunset Ln. |

**Cleanup:** delete the 12 New Test Rd address.

## T-ADDR-05: A person's address edit gives a personal address

**Purpose:** with **Only that person moves**, the edit stays with one person.
**Prerequisites:** admin.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Addresses**, set **Address Updates** to **Only that person moves** and save. | Saved. |
| 2 | On Diego Garcia, change Mailing Street to `9 Dorm Test Hall` and save. | Saved. |
| 3 | Look at Diego's **Addresses** card. | A card for 9 Dorm Test Hall with **Primary**. |
| 4 | Open The Garcia Family and Luis. | Both still show Sunset Ln. |
| 5 | Set the setting back to **Everyone in the household moves together** and save. | Saved. |

**Cleanup:** delete Diego's personal address and set his Mailing Street back to 6830 Sunset Ln.

## T-ADDR-06: Turn on Seasonal Addresses and run the seasonal swap

**Purpose:** turning on Seasonal Addresses schedules the nightly swap with no other step, and the swap runs and swaps a seasonal address in.
**Prerequisites:** admin, T-ADDR-01 done, **Seasonal Addresses** not ticked and the swap not scheduled.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Addresses**. | **Seasonal Addresses** is not ticked. The **Seasonal Address Swap** section reads **Seasonal Addresses is off, so seasonal addresses will not move on their own. Turn it on above and choose Save to schedule the nightly swap.** It has **Run the swap now** and no **Schedule nightly run** or **Stop nightly run** button. |
| 2 | Tick **Seasonal Addresses** and choose **Save**. Do not refresh the page. | **Your settings are saved.** The section now reads **The swap runs every night at 12:30 AM, in your organization's time zone.** with the next run date below. |
| 2a | Untick **Seasonal Addresses** and choose **Save**, then tick it and **Save** again. | After the untick the section reads **Seasonal Addresses is off...** with no next run date. After the second save it reads **The swap runs every night...** again, and **Health Check** does not list the swap as unscheduled. |
| 3 | Edit the Phoenix address so its season runs from yesterday to a date next month. | Saved. |
| 4 | Select **Run the swap now**. | **The swap has started. Refresh this page in a minute to see what it did.** |
| 5 | Wait a minute and refresh. | **Seasonal addresses last swapped** shows a time a minute ago and **1 moved to a seasonal address, 0 moved back, 0 could not be changed.** |
| 6 | Open The Garcia Family. | **Primary** is on Phoenix; Billing Address reads Phoenix; the Home address record has **Replaced By Seasonal** ticked. |
| 7 | Open **Home**. | The **Seasonal addresses last swapped** tile shows the same time and sentence. |

**Cleanup:** keep **Seasonal Addresses** on for T-ADDR-07.

## T-ADDR-07: The season ends and the address moves back

**Purpose:** the swap puts the replaced address back when a season ends.
**Prerequisites:** admin, T-ADDR-06 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set the Phoenix address's end month and day to yesterday and save. | Saved. |
| 2 | **BarnCRM Settings**, **Addresses**, **Run the swap now**, wait a minute, refresh. | **0 moved to a seasonal address, 1 moved back, 0 could not be changed.** |
| 3 | Open The Garcia Family. | **Primary** is back on the Home address; Billing Address reads Springfield. |
| 4 | Untick **Seasonal Addresses** and choose **Save**. | The **Seasonal Address Swap** section reads **Seasonal Addresses is off, so seasonal addresses will not move on their own. Turn it on above and choose Save to schedule the nightly swap.** |

**Cleanup:** delete the Phoenix address.

## T-ADDR-08: Overlapping Seasons and Deleting the Primary

**Purpose:** overlapping seasons are reported, and a deleted primary is replaced by a non-seasonal address.
**Prerequisites:** admin, a test household: create contact `Ada` `Testaddr` with no account (a household is created).

| Step | Action | Expected result |
|---|---|---|
| 1 | On the household, add a **Home** address `1 Year Round Test St`. | It is the first address, so it gets **Primary** at once. |
| 2 | Add a **Work** address `2 Work Test St`, then two **Seasonal** addresses whose seasons both cover today. | Both save. |
| 3 | **Run the swap now** and refresh after a minute. | The summary counts one move. The **Error Log** has a warning: **Two seasonal addresses for the same household or person cover today, so BarnCRM used the one that was added first.** The first seasonal address is the primary. |
| 4 | Delete both seasonal addresses. | **Primary** goes to a non-seasonal address (the most recently created: 2 Work Test St), never a seasonal one. |

**Cleanup:** delete Ada Testaddr, the household and its addresses.

## T-ADDR-09: Read-only user

**Purpose:** a read-only user sees addresses and the swap status but changes nothing.
**Prerequisites:** read-only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open The Garcia Family. | The **Addresses** card lists the addresses. |
| 2 | Look at a non-primary address. | It shows no **Set as Primary** button. The **Primary** badge still shows on the primary one. |
| 3 | Look at the card header. | There is no **Add address** button. |
| 4 | Open **BarnCRM Settings**, **Addresses**. | The last run shows; **Seasonal Addresses** and **Run the swap now** are disabled, with **You can see when the swap last ran. Running it needs the Manage BarnCRM Settings permission.** |

**Cleanup:** None.

## T-ADDR-10: State and country codes with State and Country Picklists on

**Purpose:** an address typed with codes reaches the standard address fields in an org with State and Country Picklists.
**Prerequisites:** staff user, in an org where Setup, **State and Country/Territory Picklists** are turned on. The Garcia Family with Harper Garcia as a member.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Garcia Family, select **Add address**. Enter Type **Home**, Street `55 Lake Street`, City `Chicago`, State `IL`, Postal Code `60601`, Country `US`. Select **Add address** in the form, then **Set as Primary** on the new card. | Toast **This is now the primary address, and it has been copied to the standard address fields.** |
| 2 | Look at the household's **Details**. | Billing Address reads Chicago, Illinois 60601, United States. |
| 3 | Open Harper Garcia. | Her mailing address reads Chicago, Illinois, United States. |

**Cleanup:** set the previous address as the primary again and delete the Chicago address.

## T-ADDR-11: Editing a household's billing address moves the household

**Purpose:** a billing address typed on the household after it was created becomes its primary address and reaches its members.
**Prerequisites:** staff user, The Garcia Family on its Sunset Ln Home address.

| Step | Action | Expected result |
|---|---|---|
| 1 | On The Garcia Family, **Details**, change Billing Street to `27 Billing Test Ave` and save. | Saved. |
| 2 | Look at the **Addresses** card. | A new **Home** card, 27 Billing Test Ave, carries **Primary**. The Sunset Ln card is still there without the badge. |
| 3 | Open Luis Garcia. | His mailing street is **27 Billing Test Ave**. |
| 4 | Back on the household, save the record again without changing the address. | No third card is added. |
| 5 | Undo: **Set as Primary** on the Sunset Ln card. | Billing Address and members are back on Sunset Ln. |

**Cleanup:** delete the 27 Billing Test Ave address.

## T-ADDR-12: A person with an address of their own stays put when the household moves

**Purpose:** a household's address change, by any route, leaves a member who has their own primary address where they are, and still moves everyone else.
**Prerequisites:** admin, T-ADDR-01 done (the Phoenix seasonal address exists).

| Step | Action | Expected result |
|---|---|---|
| 1 | On Diego Garcia, select **Add address** on his **Addresses** card: Type **Home**, Street `9 Dorm Test Hall`, City `Urbana`. Select **Add address** in the form. | It is his first address, so it carries **Primary**. His mailing street reads 9 Dorm Test Hall. |
| 2 | On The Garcia Family, **Set as Primary** on the Phoenix card. | Harper and Luis read Phoenix. Diego still reads **9 Dorm Test Hall**. |
| 3 | **Set as Primary** on the Sunset Ln card. | Harper and Luis read Sunset Ln. Diego still reads 9 Dorm Test Hall. |
| 4 | On the household's **Details**, change Billing Street to `27 Billing Test Ave` and save. | Harper and Luis read 27 Billing Test Ave. Diego still reads 9 Dorm Test Hall. |
| 5 | Delete Diego's 9 Dorm Test Hall address, then on the household **Set as Primary** on the Sunset Ln card. | Everyone, Diego included, reads Sunset Ln. |
| 6 | Flexible way of belonging only (junction mode): add Luis to a second household as a member who is not primary there, and on that household **Set as Primary** on any other address. | Luis still reads Sunset Ln: that household is not his household. |

**Cleanup:** delete the 27 Billing Test Ave address, and Luis's second membership if you added one.

## T-ADDR-13: Nobody Moves Until You Choose

**Purpose:** with **Address Updates** set to **Nobody moves until you choose**, a person's edit stays theirs, a household change moves the household only, and the seasonal swap still moves everyone without an address of their own.
**Prerequisites:** admin, T-ADDR-01 done (the Phoenix seasonal address exists), the Garcia household on Sunset Ln and no member with an address of their own.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Addresses**, look at **Address Updates**. | It shows **Everyone in the household moves together**, never an empty box. |
| 2 | Set **Address Updates** to **Nobody moves until you choose** and save. | Saved. |
| 3 | On Harper Garcia, change Mailing Street to `14 Manual Test Ct` and save. | Harper's **Addresses** card has a 14 Manual Test Ct card with **Primary**. The Garcia Family's primary is still Sunset Ln, and Luis still reads Sunset Ln. |
| 4 | On The Garcia Family's **Details**, change Billing Street to `27 Manual Billing Ave` and save. | A new **Home** card, 27 Manual Billing Ave, carries **Primary**, and Billing Address shows it. Luis still reads **Sunset Ln**. |
| 5 | Set the Phoenix address's dates so today falls inside them (as in T-ADDR-06 step 3), then in **BarnCRM Settings**, **Addresses**, choose **Run the swap now** and refresh after a minute. | **Primary** is on Phoenix, and Luis reads Phoenix: the swap still moves him. Harper still reads 14 Manual Test Ct. |

**Cleanup:** set **Address Updates** back to **Everyone in the household moves together** and save. Put the Phoenix dates back to January 1 to March 31 and run the swap again. On the household, **Set as Primary** on the Sunset Ln card, then delete the 27 Manual Billing Ave address. Delete Harper's 14 Manual Test Ct address and set her Mailing Street back to 6830 Sunset Ln.

## T-ADDR-14: Use for Whole Household

**Purpose:** **Use for Whole Household** on a person's own address makes it the household's primary address, moves everyone without an address of their own, and returns the person to the household's address from then on. With several households, the card asks which.
**Prerequisites:** staff user, the Garcia household on Sunset Ln, **Address Updates** set to **Everyone in the household moves together**, no member with an address of their own.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Diego Garcia, select **Add address** on his **Addresses** card: Type **Home**, Street `9 Dorm Test Hall`, City `Urbana`. Select **Add address** in the form. | His card carries **Primary** and a **Use for Whole Household** button. A seasonal address of his own would show no such button. |
| 2 | Select **Use for Whole Household**. | A confirmation opens: **Make this the household's primary address?**, with **Cancel** and **Use for Whole Household**. With one household there is no **Which household?** choice. |
| 3 | Select **Cancel**. | The confirmation closes; nothing changed. |
| 4 | Select **Use for Whole Household** again, then **Use for Whole Household** in the confirmation. | Toast **The household now uses this address.** |
| 5 | Open The Garcia Family. | A new **Home** card, 9 Dorm Test Hall, carries **Primary**; Sunset Ln is still on the card. Billing Address reads 9 Dorm Test Hall. Harper and Luis read 9 Dorm Test Hall. |
| 6 | Open Diego Garcia. | His own 9 Dorm Test Hall card is still there, without **Primary**. On the household, **Set as Primary** on the Sunset Ln card: Diego moves back to Sunset Ln with everyone. |
| 7 | Flexible way of belonging only (junction mode): add Diego as a member (not primary) of another household, add him an address of his own again, and select **Use for Whole Household**. | The confirmation shows **Which household?** with The Garcia Family first. Pick the other household and confirm: that household moves to his address, and Diego keeps his own address. |

**Cleanup:** on The Garcia Family, **Set as Primary** on Sunset Ln if it is not already, then delete the 9 Dorm Test Hall addresses (household and Diego's). Remove Diego's second membership and that household's new address if you made them.

## T-ADDR-15: Update Everyone's Address

**Purpose:** **Update Everyone's Address** on a household's primary address lists who will move and who has an address of their own, and moves only the people ticked among the latter.
**Prerequisites:** staff user, the Garcia household on Sunset Ln, **Address Updates** set to **Nobody moves until you choose**.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Diego Garcia, add a **Home** address `9 Dorm Test Hall`, City `Urbana`. On Harper Garcia, add a **Home** address `14 Manual Test Ct`. | Each carries **Primary** on their own card. |
| 2 | On The Garcia Family's **Details**, change Billing Street to `27 Manual Billing Ave` and save. | The new card carries **Primary**. Luis still reads Sunset Ln: nobody moved. |
| 3 | On the household's 27 Manual Billing Ave card, look at the buttons. | It shows **Update Everyone's Address**. The other household cards do not. |
| 4 | Select **Update Everyone's Address**. | The confirmation lists **These people will get this address:** Luis Garcia, and under **These people have an address of their own and stay where they are unless you tick them:** a tick box for Diego Garcia and one for Harper Garcia, both unticked. |
| 5 | Tick Harper only, then select **Update Everyone's Address** in the confirmation. | Toast **Everyone's address has been updated.** |
| 6 | Open Luis, Harper and Diego. | Luis and Harper read 27 Manual Billing Ave; Harper's own card is still there without **Primary**. Diego still reads 9 Dorm Test Hall. |
| 7 | On the household, select **Update Everyone's Address** again. | Luis and Harper are listed as getting the address, and only Diego has a tick box. Select **Cancel**: nothing changes. |
| 8 | As a read-only user, open The Garcia Family and Diego Garcia. | Neither **Update Everyone's Address** nor **Use for Whole Household** shows. |

**Cleanup:** set **Address Updates** back to **Everyone in the household moves together** and save. On the household, **Set as Primary** on the Sunset Ln card and delete the 27 Manual Billing Ave address. Delete Diego's 9 Dorm Test Hall and Harper's 14 Manual Test Ct addresses, then **Set as Primary** on Sunset Ln once more so everyone reads it.
