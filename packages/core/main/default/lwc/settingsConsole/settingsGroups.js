import EDITION_AND_FEATURES from '@salesforce/label/c.Core_SettingsGroup_EditionAndFeatures';
import PREFERENCES from '@salesforce/label/c.Core_SettingsGroup_Preferences';
import TOOLS from '@salesforce/label/c.Core_SettingsGroup_Tools';
import ORGANIZATION_DETAILS from '@salesforce/label/c.Core_SettingsGroup_OrganizationDetails';
import ORGANIZATION_ADDRESS from '@salesforce/label/c.Core_SettingsGroup_OrganizationAddress';
import RECEIPT_SIGNATURE from '@salesforce/label/c.Core_SettingsGroup_ReceiptSignature';
import PEOPLE from '@salesforce/label/c.Core_SettingsGroup_People';
import HOUSEHOLDS from '@salesforce/label/c.Core_SettingsGroup_Households';
import HOUSEHOLD_NAMES from '@salesforce/label/c.Core_SettingsGroup_HouseholdNames';
import RELATIONSHIPS from '@salesforce/label/c.Core_SettingsGroup_Relationships';
import ADDRESS_UPDATES from '@salesforce/label/c.Core_SettingsGroup_AddressUpdates';
import ADDRESS_CARD from '@salesforce/label/c.Core_SettingsGroup_AddressCard';
import SEASONAL_ADDRESSES from '@salesforce/label/c.Core_SettingsGroup_SeasonalAddresses';
import GIFT_DEFAULTS from '@salesforce/label/c.Core_SettingsGroup_GiftDefaults';
import INSTALLMENTS from '@salesforce/label/c.Core_SettingsGroup_Installments';
import DONOR_LEVELS from '@salesforce/label/c.Core_SettingsGroup_DonorLevels';
import ACKNOWLEDGMENTS from '@salesforce/label/c.Core_SettingsGroup_Acknowledgments';
import GIVING_JOBS from '@salesforce/label/c.Core_SettingsGroup_GivingJobs';
import MIRROR from '@salesforce/label/c.Core_SettingsGroup_Mirror';
import RECEIPT_DETAILS from '@salesforce/label/c.Core_SettingsGroup_ReceiptDetails';
import RECEIPT_PRINTING from '@salesforce/label/c.Core_SettingsGroup_ReceiptPrinting';
import RECEIPT_RUNS from '@salesforce/label/c.Core_SettingsGroup_ReceiptRuns';
import ROLLUP_PROCESSING from '@salesforce/label/c.Core_SettingsGroup_RollupProcessing';
import ROLLUP_BUILDER from '@salesforce/label/c.Core_SettingsGroup_RollupBuilder';
import HOURS_AND_SHIFTS from '@salesforce/label/c.Core_SettingsGroup_HoursAndShifts';
import ERROR_DIGEST from '@salesforce/label/c.Core_SettingsGroup_ErrorDigest';
import ERROR_LOG_RETENTION from '@salesforce/label/c.Core_SettingsGroup_ErrorLogRetention';
import IMPORTING from '@salesforce/label/c.Core_SettingsGroup_Importing';
import GIFT_MATCHING from '@salesforce/label/c.Core_SettingsGroup_GiftMatching';
import FIND_AND_BULK from '@salesforce/label/c.Core_SettingsGroup_FindAndBulk';

/**
 * The boxes (sub-sections) each BarnCRM Settings page shows its rows in (P1), by page name in
 * lower case, in the order they show.
 *
 * - `id` is stable and never translated: a link may name it instead of a page, and the console
 *   then opens the page it is on and scrolls to it. The People and Households ids match
 *   SettingSections (PEOPLE, HOUSEHOLDS, HOUSEHOLD_NAMES, RELATIONSHIPS), and Households and
 *   Relationships were pages until P1, so old links still land in the right box.
 * - `keys` are the rows it holds: a setting's key, or a panel row's developer name.
 * - `fallback` marks the box a row no box names goes in, so a row added later (by a module, or
 *   a branch this list has not seen) still shows. A page with no entry here shows one box,
 *   titled with the page name: Duplicate Matching (its panel is its one row), Modules,
 *   Automation, Access, Org Optimizer, Integrations and Health.
 *
 * Rows keep the order their Sort Order gives them inside a box.
 */
const PAGE_GROUPS = {
  general: [
    { id: 'Edition and Features', label: EDITION_AND_FEATURES, keys: ['Suite', 'Features'] },
    {
      id: 'Preferences',
      label: PREFERENCES,
      fallback: true,
      keys: [
        'Coexistence_Mode__c',
        'Organization_Record_Type__c',
        'Job_Notifications__c',
        'App_Navigation_Style__c',
        'FiscalYearStartMonth'
      ]
    },
    { id: 'Tools', label: TOOLS, keys: ['Custom_Metadata_Manager', 'Sample_Data'] }
  ],
  organization: [
    {
      id: 'Organization Details',
      label: ORGANIZATION_DETAILS,
      fallback: true,
      keys: ['Name', 'Organization_Legal_Name__c', 'Organization_EIN__c']
    },
    {
      id: 'Organization Address',
      label: ORGANIZATION_ADDRESS,
      keys: ['Core_Organization_Address']
    },
    {
      id: 'Receipt Logo and Signature',
      label: RECEIPT_SIGNATURE,
      keys: [
        'Receipt_Logo_Document_Id__c',
        'Receipt_Signature_Document_Id__c',
        'Receipt_Signer_Name__c',
        'Receipt_Signer_Title__c'
      ]
    }
  ],
  'people and households': [
    {
      id: 'People',
      label: PEOPLE,
      keys: ['Household_Membership_Mode__c', 'Auto_Create_Households__c']
    },
    {
      id: 'Households',
      label: HOUSEHOLDS,
      fallback: true,
      keys: ['Delete_Empty_Households__c', 'Keep_Households_Of_Deleted_People__c']
    },
    {
      id: 'Household Names and Greetings',
      label: HOUSEHOLD_NAMES,
      keys: ['Household_Naming_Preview', 'Include_Deceased_In_Name__c']
    },
    {
      id: 'Relationships',
      label: RELATIONSHIPS,
      keys: ['Relationship_Auto_Reciprocal__c']
    }
  ],
  addresses: [
    {
      id: 'Address Updates',
      label: ADDRESS_UPDATES,
      fallback: true,
      keys: ['Contact_Address_Change_Behavior__c']
    },
    { id: 'Address Card', label: ADDRESS_CARD, keys: ['Address_Card_Fields__c'] },
    {
      id: 'Seasonal Addresses',
      label: SEASONAL_ADDRESSES,
      keys: ['Seasonal_Addresses_Enabled__c', 'Seasonal_Address_Job']
    }
  ],
  giving: [
    {
      id: 'Gift Defaults',
      label: GIFT_DEFAULTS,
      fallback: true,
      keys: ['Default_Fund__c', 'Default_Appeal__c', 'Automatic_Household_Soft_Credits__c']
    },
    {
      id: 'Commitments and Installments',
      label: INSTALLMENTS,
      keys: [
        'Installment_Generation_Horizon_Months__c',
        'Installment_Overdue_Grace_Days__c',
        'Auto_Apply_Gifts_To_Installments__c'
      ]
    },
    {
      id: 'Donor Levels',
      label: DONOR_LEVELS,
      keys: ['Donor_Levels_Enabled__c', 'Donor_Level_Source_Field__c', 'Donor_Levels_Page']
    },
    {
      id: 'Acknowledgments and Stewardship',
      label: ACKNOWLEDGMENTS,
      keys: [
        'Acknowledgments_Enabled__c',
        'Acknowledgment_From_Address__c',
        'Giving_Acknowledgments_Page',
        'Stewardship_Plans_Page',
        'Ask_Reminders_Enabled__c'
      ]
    },
    {
      id: 'Nightly Jobs and Accounting Periods',
      label: GIVING_JOBS,
      keys: ['Giving_Nightly_Jobs', 'Giving_Accounting_Periods']
    },
    {
      id: 'BarnCRM Mirror',
      label: MIRROR,
      keys: [
        'Mirror_Accounting_Export',
        'Campaign_Sync_Enabled__c',
        'Mirror_Campaign_Sync',
        'Opportunity_Mirror_Direction__c',
        'Opportunity_Mirror_Start__c',
        'Opportunity_Mirror_Record_Types__c',
        'Mirror_Opportunity_Mirror'
      ]
    }
  ],
  receipts: [
    {
      id: 'Receipt Details',
      label: RECEIPT_DETAILS,
      fallback: true,
      keys: [
        'Receipt_Number_Prefix__c',
        'Receipt_Next_Counter__c',
        'Receipt_Statement_Year__c',
        'Receipt_Place_Of_Issue__c'
      ]
    },
    {
      id: 'Receipt Printing',
      label: RECEIPT_PRINTING,
      keys: [
        'Receipt_Renderer__c',
        'Receipt_Print_Logo__c',
        'Receipt_Logo_Width_Mm__c',
        'Receipt_Logo_Delivery__c'
      ]
    },
    {
      id: 'Receipt Letters and Year End Statements',
      label: RECEIPT_RUNS,
      keys: ['Giving_Receipts_Console']
    }
  ],
  rollups: [
    {
      id: 'Rollup Processing',
      label: ROLLUP_PROCESSING,
      fallback: true,
      keys: ['Rollup_Mode_Default__c', 'Rollup_Processing__c', 'Nightly_Run_Hour__c']
    },
    { id: 'Rollup Builder', label: ROLLUP_BUILDER, keys: ['Rollup_Definitions'] }
  ],
  volunteers: [
    {
      id: 'Hours and Shifts',
      label: HOURS_AND_SHIFTS,
      fallback: true,
      keys: ['Hours_Require_Approval__c', 'Attendance_Creates_Hours__c', 'Shift_Horizon_Weeks__c']
    }
  ],
  'error log': [
    {
      id: 'Error Digest',
      label: ERROR_DIGEST,
      fallback: true,
      keys: ['Error_Digest_Job', 'Error_Digest_Recipients__c', 'Error_Digest_Frequency__c']
    },
    {
      id: 'Error Log Retention',
      label: ERROR_LOG_RETENTION,
      keys: ['Error_Log_Retention_Days__c']
    }
  ],
  import: [
    {
      id: 'Importing',
      label: IMPORTING,
      fallback: true,
      keys: [
        'Import_Wizard',
        'Import_Chunk_Size__c',
        'Import_Trial_Rows__c',
        'Import_Undo_Retention_Days__c',
        'Import_Row_Deletion__c',
        'Import_New_Field_Connection'
      ]
    },
    {
      id: 'Gift Matching on Import',
      label: GIFT_MATCHING,
      keys: ['Donation_Match_Date_Window_Days__c', 'Donation_Match_Amount_Tolerance__c']
    },
    {
      id: 'Find, Bulk Update and Bulk Delete',
      label: FIND_AND_BULK,
      keys: [
        'Find_Export_Row_Limit__c',
        'Bulk_Update_Run_Limit__c',
        'Bulk_Delete_Run_Limit__c',
        'Bulk_Chunk_Size__c'
      ]
    }
  ]
};

function groupsFor(pageName) {
  return PAGE_GROUPS[String(pageName || '').toLowerCase()];
}

/**
 * A page's rows as boxes: `[{ id, label, rows }]`, in the order the page lists its boxes,
 * leaving out a box with nothing to show. No row is ever dropped: one no box names goes in the
 * page's fallback box, and a page with no boxes listed shows them all in one box titled with
 * the page name.
 */
export function groupRows(pageName, rows) {
  const defined = groupsFor(pageName);
  if (!defined) {
    return rows.length > 0 ? [{ id: pageName, label: pageName, rows }] : [];
  }
  const boxes = defined.map((group) => ({ id: group.id, label: group.label, rows: [] }));
  const marked = defined.findIndex((group) => group.fallback);
  const fallback = boxes[marked >= 0 ? marked : 0];
  rows.forEach((row) => {
    const index = defined.findIndex((group) => group.keys.includes(row.key));
    (index >= 0 ? boxes[index] : fallback).rows.push(row);
  });
  return boxes.filter((box) => box.rows.length > 0);
}

/**
 * The page and box a link names, when it names a box rather than a page (P1), among the pages
 * the console has: `{ page, box }`, else undefined. Capitals and spacing are ignored.
 */
export function findBox(pageNames, requested) {
  const wanted = String(requested || '')
    .trim()
    .toLowerCase();
  if (!wanted) {
    return undefined;
  }
  for (const page of pageNames) {
    const box = (groupsFor(page) || []).find((group) => group.id.toLowerCase() === wanted);
    if (box) {
      return { page, box: box.id };
    }
  }
  return undefined;
}
