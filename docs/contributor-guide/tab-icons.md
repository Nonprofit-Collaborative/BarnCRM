# Tab Icons

Every BarnCRM tab, Core and module, carries a motif whose number matches the icon Salesforce documents for it (D-144, UX-F3). A tab's icon comes from the `CustomN` number only; the name after the colon is a note, so a guessed name hides a wrong icon (`Custom25` is the alarm clock, never an envelope). Use the Metadata API's documented `CustomTab.motif` list, Custom1 to Custom100.

Rules:

- Write the motif as `CustomN: Name`, with the name the documented list gives for N.
- No two BarnCRM tabs share a number, so each tab is recognizable in the navigation, the page header and a console tab.
- A new tab takes a number no other BarnCRM tab uses. Add it to the table below; `scripts/ci/tests/test_core_navigation.py` fails if it is invalid or reused.

| Package | Tab | Motif |
|---|---|---|
| core | Address__c | Custom78: Map |
| core | Affiliation__c | Custom33: Desk |
| core | BarnCRM_Home | Custom1: Heart |
| core | BarnCRM_Settings | Custom67: Gears |
| core | Bulk_Update | Custom19: Wrench |
| core | Data_Hygiene | Custom94: Stethoscope |
| core | Data_Manager | Custom57: BuildingBlock |
| core | Duplicate_Matching | Custom90: Scales |
| core | Error_Log__c | Custom53: Bell |
| core | Find | Custom39: Telescope |
| core | Household_Member__c | Custom14: Hands |
| core | Households | Custom15: People |
| core | Import | Custom18: Form |
| core | Import_Row__c | Custom83: Pencil |
| core | Organizations | Custom24: Building |
| core | Relationship__c | Custom37: Bridge |
| giving | Acknowledgment_Rule__c | Custom76: Keys |
| giving | Acknowledgment_Run__c | Custom98: Truck |
| giving | Acknowledgment__c | Custom22: Telephone |
| giving | Acknowledgments | Custom71: Headset |
| giving | Appeal__c | Custom11: Star |
| giving | Ask_Pipeline | Custom54: Boat |
| giving | Ask__c | Custom64: Compass |
| giving | Commitment__c | Custom46: Stamp |
| giving | Donor_Level__c | Custom48: Trophy |
| giving | Donor_Levels | Custom65: Cup |
| giving | Donor_Segments | Custom68: Globe |
| giving | Fund__c | Custom42: Treasurechest |
| giving | Gift_Allocation__c | Custom17: Sack |
| giving | Gift_Batch__c | Custom13: Box |
| giving | Gift__c | Custom41: Cash |
| giving | Giving_Accounting_Periods | Custom55: Books |
| giving | Giving_Nightly_Jobs | Custom10: Moon |
| giving | Installment__c | Custom45: Ticket |
| giving | Pledge_Reminder_Step__c | Custom79: MeasuringTape |
| giving | Pledge_Reminder__c | Custom25: Alarmclock |
| giving | Pledge_Reminders | Custom95: Stopwatch |
| giving | Quick_Gift_Entry | Custom40: Creditcard |
| giving | Receipt_Run__c | Custom36: Train |
| giving | Receipt__c | Custom23: Envelope |
| giving | Receipts | Custom27: Laptop |
| giving | Soft_Credit__c | Custom26: Flag |
| giving | Stewardship_Plan_Template__c | Custom7: Square |
| giving | Stewardship_Plan__c | Custom43: Jewel |
| giving | Stewardship_Plans | Custom4: Hexagon |
| giving | Tribute__c | Custom5: Leaf |
| volunteers | Skill__c | Custom69: Guitar |
| volunteers | Volunteer_Approve_Hours | Custom91: Shield |
| volunteers | Volunteer_Hours__c | Custom3: Sun |
| volunteers | Volunteer_Job__c | Custom44: Hammer |
| volunteers | Volunteer_Letter_Template__c | Custom29: PDA |
| volunteers | Volunteer_Requirement__c | Custom86: RedCross |
| volunteers | Volunteer_Shift__c | Custom74: HotAirBalloon |
| volunteers | Volunteer_Signup__c | Custom2: Fan |
| programs | Case_Note__c | Custom12: Circle |
| programs | Enrollment__c | Custom60: Umbrella |
| programs | Program__c | Custom88: Sailboat |
| programs | Programs_Dashboard | Custom9: Lightning |
| programs | Programs_Settings | Custom73: HighwaySign |
| programs | Service_Delivery__c | Custom16: Bank |
| logicmodels | Logic_Model__c | Custom62: Chalkboard |
| mirror | Accounting_Export | Custom21: Computer |
| mirror | Campaign_Sync | Custom35: Microphone |
| mirror | Opportunity_Mirror | Custom30: Radardish |
| rollups | Rollup_Builder | Custom63: Chip |
