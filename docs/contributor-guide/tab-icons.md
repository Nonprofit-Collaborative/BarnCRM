# Tab Icons

Every BarnCRM tab, Core and module, carries a motif whose number matches the icon Salesforce documents for it (D-144, UX-F3). A tab's icon comes from the `CustomN` number only; the name after the colon is a note, so a guessed name hides a wrong icon (`Custom25` is the alarm clock, never an envelope). Use the Metadata API's documented `CustomTab.motif` list, Custom1 to Custom100.

Rules:

- Write the motif as `CustomN: Name`, with the name the documented list gives for N.
- No two BarnCRM tabs share a number, so each tab is recognizable in the navigation, the page header and a console tab.
- A new tab takes a number no other BarnCRM tab uses. Add it to the table below; `scripts/ci/tests/test_core_navigation.py` fails if it is invalid or reused.
- Add the tab to the icon registry, `packages/core/main/default/lwc/barnIcons/barnIcons.js`, keyed by the tab's API name, in the same PR. The same test fails when a tab is missing from the registry or listed with another number.
- Navigation icon equals tab icon: a link or tile that opens a tab takes its icon from `iconFor('<tab API name>')` (c/barnIcons). See the [Visual Standard](ux-kit.md#visual-standard).
- A card's header icon is its own page's or object's tab icon (`custom:customN` with that tab's number), never another tab's. See Card Icons below.

| Package | Tab | Motif |
|---|---|---|
| core | Address__c | Custom78: Map |
| core | Affiliation__c | Custom33: Desk |
| core | Automation | Custom32: Factory |
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
| core | Record_Inspector | Custom38: Camera |
| core | Relationship__c | Custom37: Bridge |
| events | Event_Speaker__c | Custom75: IPPhone |
| events | Event__c | Custom89: Saxophone |
| events | Events_Calendar | Custom66: Dice |
| events | Events_Home | Custom81: MusicalNote |
| funders | Funder_Report_Template__c | Custom99: TVCRT |
| funders | Funders_Board | Custom100: TVWidescreen |
| funders | Grant_Answer__c | Custom87: Safe |
| funders | Grant_Calendar | Custom82: Whistle |
| funders | Grant_Checklist_Item__c | Custom70: Handsaw |
| funders | Grant_Finder | Custom80: Motorcycle |
| funders | Grant_Pipeline | Custom92: Ship |
| funders | Grant_Requirement__c | Custom84: Presenter |
| funders | Grant__c | Custom8: Diamond |
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
| giving | Fundraising_Home | Custom61: Castle |
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
| contactpoints | Contact_Point_Sync | Custom59: Can |
| forms | Form_Submission__c | Custom51: Apple |
| forms | Form__c | Custom28: Cellphone |
| logicmodels | Logic_Model__c | Custom62: Chalkboard |
| portal | Portal_Access__c | Custom77: Locked |
| portal | Portal__c | Custom47: Knight |
| corporatehub | Agreement__c | Custom93: ShoppingCart |
| corporatehub | Board__c | Custom58: Caduceus |
| corporatehub | Board_Meeting__c | Custom56: Bottle |
| corporatehub | Compliance_Obligation__c | Custom97: Thermometer |
| corporatehub | Corporate_Hub | Custom72: Helicopter |
| corporatehub | Hub_Document__c | Custom49: CD/DVD |
| lwcbuilder | LWC_Builder | Custom34: Insect |
| mirror | Accounting_Export | Custom21: Computer |
| mirror | Campaign_Sync | Custom35: Microphone |
| mirror | Gift_Transaction_Mirror | Custom31: Car |
| mirror | Opportunity_Mirror | Custom30: Radardish |
| programs | Case_Note__c | Custom12: Circle |
| programs | Cohort__c | Custom50: Bigtop |
| programs | Enrollment__c | Custom60: Umbrella |
| programs | Goal__c | Custom96: StreetSign |
| programs | Program__c | Custom88: Sailboat |
| programs | Programs_Dashboard | Custom9: Lightning |
| programs | Programs_Settings | Custom73: HighwaySign |
| programs | Referral__c | Custom85: RealEstateSign |
| programs | Service_Count__c | Custom6: Triangle |
| programs | Service_Delivery__c | Custom16: Bank |
| programs | Session__c | Custom20: Airplane |
| rollups | Rollup_Builder | Custom63: Chip |
| volunteers | Skill__c | Custom69: Guitar |
| volunteers | Volunteer_Approve_Hours | Custom91: Shield |
| volunteers | Volunteer_Hours__c | Custom3: Sun |
| volunteers | Volunteer_Job__c | Custom44: Hammer |
| volunteers | Volunteer_Letter_Template__c | Custom29: PDA |
| volunteers | Volunteer_Requirement__c | Custom86: RedCross |
| volunteers | Volunteer_Shift__c | Custom74: HotAirBalloon |
| volunteers | Volunteer_Signup__c | Custom2: Fan |
| volunteers | Volunteers_Home | Custom52: Balls |

## Card Icons

A `lightning-card` header shows the icon of the page or object the card belongs to, so a card reads as part of its tab (vis-core-4, extends D-144). Rules:

- A card on a tab's own page, or about one object, uses that tab's `custom:customN`, with N the tab's motif number.
- A card never uses another tab's number: a borrowed motif tells people the card is about something else.
- Card headers use `standard:*` or `custom:*` icons only; a `utility:*` glyph renders small and grey beside colored icon tiles.
- A card with no tab of its own keeps a `standard:*` icon. The people panels (Household, Members, Relationships, Affiliations, Addresses) each have a tab, so they use its icon; the rows inside them use `lightning-avatar` with initials or a `standard:*` object icon.

Every card with a `custom:*` icon is listed here. `scripts/ci/tests/test_core_navigation.py` fails when a card uses a `custom:*` icon that is not listed, when the listed tab's motif number differs, when the component names neither the icon nor `iconFor('<Tab>')` (c/barnIcons), or when a card header uses a `utility:*` icon.

| Package | Component | Card icon | Tab |
|---|---|---|---|
| core | addressPanel | custom:custom78 | Address__c |
| core | affiliationPanel | custom:custom33 | Affiliation__c |
| core | automationControl | custom:custom32 | Automation |
| core | automationInventory | custom:custom32 | Automation |
| core | errorLogTile | custom:custom53 | Error_Log__c |
| core | householdMembersPanel | custom:custom15 | Households |
| core | householdOfPerson | custom:custom15 | Households |
| core | hubErrors | custom:custom53 | Error_Log__c |
| core | hubWelcome | custom:custom1 | BarnCRM_Home |
| core | recordInspector | custom:custom38 | Record_Inspector |
| core | relationshipPanel | custom:custom37 | Relationship__c |
| funders | fundersBoard | custom:custom100 | Funders_Board |
| funders | grantAnswerLibrary | custom:custom87 | Grant_Answer__c |
| funders | grantBudget | custom:custom8 | Grant__c |
| funders | grantCalendar | custom:custom82 | Grant_Calendar |
| funders | grantChecklist | custom:custom70 | Grant_Checklist_Item__c |
| funders | grantDocuments | custom:custom84 | Grant_Requirement__c |
| funders | grantFinder | custom:custom80 | Grant_Finder |
| funders | grantLinkedRecord | custom:custom88 | Program__c |
| funders | grantLinkedRecord | custom:custom42 | Fund__c |
| funders | grantRenewals | custom:custom8 | Grant__c |
| funders | grantOutcomes | custom:custom62 | Logic_Model__c |
| funders | grantPipeline | custom:custom92 | Grant_Pipeline |
| funders | grantReport | custom:custom99 | Funder_Report_Template__c |
| giving | acknowledgments | custom:custom71 | Acknowledgments |
| giving | askPipeline | custom:custom54 | Ask_Pipeline |
| giving | commitmentNew | custom:custom46 | Commitment__c |
| giving | donorLevels | custom:custom65 | Donor_Levels |
| giving | donorSegments | custom:custom68 | Donor_Segments |
| giving | giftAllocations | custom:custom17 | Gift_Allocation__c |
| giving | giftBatchEntry | custom:custom13 | Gift_Batch__c |
| giving | giftSoftCredits | custom:custom26 | Soft_Credit__c |
| giving | pledgeReminders | custom:custom95 | Pledge_Reminders |
| giving | quickGiftEntry | custom:custom40 | Quick_Gift_Entry |
| giving | receiptActions | custom:custom23 | Receipt__c |
| giving | stewardshipPlans | custom:custom4 | Stewardship_Plans |
| giving | tributeNotification | custom:custom5 | Tribute__c |
| corporatehub | hubBoardPanel | custom:custom58 | Board__c |
| corporatehub | hubMeetingPanel | custom:custom56 | Board_Meeting__c |
| lwcbuilder | lwcBuilderStudio | custom:custom34 | LWC_Builder |
| forms | formBuilder | custom:custom28 | Form__c |
| forms | formRunner | custom:custom28 | Form__c |
| forms | formSubmission | custom:custom51 | Form_Submission__c |
| logicmodels | logicModelBuilder | custom:custom62 | Logic_Model__c |
| mirror | accountingExport | custom:custom21 | Accounting_Export |
| mirror | campaignSync | custom:custom35 | Campaign_Sync |
| mirror | giftTransactionMirror | custom:custom31 | Gift_Transaction_Mirror |
| mirror | opportunityMirror | custom:custom30 | Opportunity_Mirror |
| programs | cohortMembers | custom:custom50 | Cohort__c |
| programs | personEnrollments | custom:custom60 | Enrollment__c |
| programs | programDashboard | custom:custom9 | Programs_Dashboard |
| programs | programRoster | custom:custom60 | Enrollment__c |
| programs | programsSettings | custom:custom73 | Programs_Settings |
| programs | serviceDeliveryLog | custom:custom16 | Service_Delivery__c |
| programs | servicePlan | custom:custom96 | Goal__c |
| programs | sessionScheduler | custom:custom20 | Session__c |
| programs | sessionScheduleSessions | custom:custom20 | Session__c |
| rollups | rollupBuilder | custom:custom63 | Rollup_Builder |
| rollups | rollupDefinitions | custom:custom63 | Rollup_Builder |
| volunteers | shiftScheduleShifts | custom:custom74 | Volunteer_Shift__c |
| volunteers | shiftSignups | custom:custom2 | Volunteer_Signup__c |
| volunteers | volunteerHoursApproval | custom:custom91 | Volunteer_Approve_Hours |
