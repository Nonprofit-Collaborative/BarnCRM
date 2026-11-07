/**
 * One icon per concept, from one registry (D-144 extended by the v1.0 visual standard).
 *
 * Rule: anything that names or navigates to a BarnCRM tab, and any card about a tab's object,
 * uses that tab's icon. Keys are the tab's API name (the object's API name for an object tab),
 * so a card about gifts uses `iconFor('Gift__c')` and a link to Ask Pipeline uses
 * `iconFor('Ask_Pipeline')`. Standard records Core shows without a BarnCRM tab use their
 * standard icon.
 *
 * Framework free (no lightning or @salesforce imports), so the same map serves BarnCRM for
 * WordPress (plan 9.9). Names are data here, never a reference: a module's entry costs Core
 * nothing when the module is not installed. scripts/ci/tests/test_core_navigation.py checks
 * that every tab is listed with its own motif number and that nothing else is.
 */
const ICONS = Object.freeze({
  // Core
  Address__c: 'custom:custom78',
  Affiliation__c: 'custom:custom33',
  Automation: 'custom:custom32',
  BarnCRM_Home: 'custom:custom1',
  BarnCRM_Settings: 'custom:custom67',
  Bulk_Update: 'custom:custom19',
  Data_Hygiene: 'custom:custom94',
  Data_Manager: 'custom:custom57',
  Duplicate_Matching: 'custom:custom90',
  Error_Log__c: 'custom:custom53',
  Find: 'custom:custom39',
  Household_Member__c: 'custom:custom14',
  Households: 'custom:custom15',
  Import: 'custom:custom18',
  Import_Row__c: 'custom:custom83',
  Organizations: 'custom:custom24',
  Record_Inspector: 'custom:custom38',
  Relationship__c: 'custom:custom37',
  // Events
  Event__c: 'custom:custom89',
  Events_Home: 'custom:custom81',
  // Funders
  Funder_Report_Template__c: 'custom:custom99',
  Funders_Board: 'custom:custom100',
  Grant_Answer__c: 'custom:custom87',
  Grant_Calendar: 'custom:custom82',
  Grant_Pipeline: 'custom:custom92',
  Grant_Requirement__c: 'custom:custom84',
  Grant__c: 'custom:custom8',
  // Giving
  Acknowledgment_Rule__c: 'custom:custom76',
  Acknowledgment_Run__c: 'custom:custom98',
  Acknowledgment__c: 'custom:custom22',
  Acknowledgments: 'custom:custom71',
  Appeal__c: 'custom:custom11',
  Ask_Pipeline: 'custom:custom54',
  Ask__c: 'custom:custom64',
  Commitment__c: 'custom:custom46',
  Donor_Level__c: 'custom:custom48',
  Donor_Levels: 'custom:custom65',
  Donor_Segments: 'custom:custom68',
  Fund__c: 'custom:custom42',
  Fundraising_Home: 'custom:custom61',
  Gift_Allocation__c: 'custom:custom17',
  Gift_Batch__c: 'custom:custom13',
  Gift__c: 'custom:custom41',
  Giving_Accounting_Periods: 'custom:custom55',
  Giving_Nightly_Jobs: 'custom:custom10',
  Installment__c: 'custom:custom45',
  Pledge_Reminder_Step__c: 'custom:custom79',
  Pledge_Reminder__c: 'custom:custom25',
  Pledge_Reminders: 'custom:custom95',
  Quick_Gift_Entry: 'custom:custom40',
  Receipt_Run__c: 'custom:custom36',
  Receipt__c: 'custom:custom23',
  Receipts: 'custom:custom27',
  Soft_Credit__c: 'custom:custom26',
  Stewardship_Plan_Template__c: 'custom:custom7',
  Stewardship_Plan__c: 'custom:custom43',
  Stewardship_Plans: 'custom:custom4',
  Tribute__c: 'custom:custom5',
  // Logic Models
  Logic_Model__c: 'custom:custom62',
  // Mirror
  Accounting_Export: 'custom:custom21',
  Campaign_Sync: 'custom:custom35',
  Gift_Transaction_Mirror: 'custom:custom31',
  Opportunity_Mirror: 'custom:custom30',
  // Programs
  Case_Note__c: 'custom:custom12',
  Cohort__c: 'custom:custom50',
  Enrollment__c: 'custom:custom60',
  Goal__c: 'custom:custom96',
  Program__c: 'custom:custom88',
  Programs_Dashboard: 'custom:custom9',
  Programs_Settings: 'custom:custom73',
  Referral__c: 'custom:custom85',
  Service_Count__c: 'custom:custom6',
  Service_Delivery__c: 'custom:custom16',
  Session__c: 'custom:custom20',
  // Rollups
  Rollup_Builder: 'custom:custom63',
  // Volunteers
  Skill__c: 'custom:custom69',
  Volunteer_Approve_Hours: 'custom:custom91',
  Volunteer_Hours__c: 'custom:custom3',
  Volunteer_Job__c: 'custom:custom44',
  Volunteer_Letter_Template__c: 'custom:custom29',
  Volunteer_Requirement__c: 'custom:custom86',
  Volunteer_Shift__c: 'custom:custom74',
  Volunteer_Signup__c: 'custom:custom2',
  Volunteers_Home: 'custom:custom52',
  // Standard records with no BarnCRM tab
  Account: 'standard:account',
  Contact: 'standard:contact'
});

/** The icon for a tab or object API name, or `fallback` when the registry has none. */
export function iconFor(name, fallback) {
  return Object.prototype.hasOwnProperty.call(ICONS, name) ? ICONS[name] : fallback;
}

export { ICONS };
