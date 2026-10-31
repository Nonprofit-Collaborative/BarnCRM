import { LightningElement } from 'lwc';
import getStorage from '@salesforce/apex/OrgOptimizerStorageController.getStorage';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import STORAGE from '@salesforce/label/c.Core_OrgOptimizer_Storage';
import LIMITS_HEADING from '@salesforce/label/c.Core_OrgOptimizer_LimitsHeading';
import LIMIT_USAGE from '@salesforce/label/c.Core_OrgOptimizer_LimitUsage';
import LIMIT_DATA from '@salesforce/label/c.Core_OrgOptimizer_LimitDataStorage';
import LIMIT_FILE from '@salesforce/label/c.Core_OrgOptimizer_LimitFileStorage';
import LIMIT_API from '@salesforce/label/c.Core_OrgOptimizer_LimitApiRequests';
import LIMIT_ASYNC from '@salesforce/label/c.Core_OrgOptimizer_LimitAsyncApex';
import LIMIT_EMAIL from '@salesforce/label/c.Core_OrgOptimizer_LimitSingleEmail';
import OWN_HEADING from '@salesforce/label/c.Core_OrgOptimizer_OwnHeading';
import OWN_INTRO from '@salesforce/label/c.Core_OrgOptimizer_OwnIntro';
import COLUMN_OBJECT from '@salesforce/label/c.Core_OrgOptimizer_ColumnObject';
import COLUMN_RECORDS from '@salesforce/label/c.Core_OrgOptimizer_ColumnRecords';
import COLUMN_MB from '@salesforce/label/c.Core_OrgOptimizer_ColumnMB';
import MORE_THAN from '@salesforce/label/c.Core_OrgOptimizer_MoreThan';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import NEAR_LIMIT from '@salesforce/label/c.Core_OrgOptimizer_NearLimit';
import { format } from 'c/findCsv';

/** A limit used to this percentage or more carries a Near Limit badge. */
const NEAR_LIMIT_PERCENT = 80;

const LIMIT_LABELS = {
  DataStorageMB: LIMIT_DATA,
  FileStorageMB: LIMIT_FILE,
  DailyApiRequests: LIMIT_API,
  DailyAsyncApexExecutions: LIMIT_ASYNC,
  SingleEmail: LIMIT_EMAIL
};

/**
 * Org Optimizer's Storage and limits section (admin guide org-optimizer.md): the org's storage
 * and daily limits from OrgLimits, and the records BarnCRM's own objects hold. Read only; read
 * when the section is opened and on Refresh. After each read it fires `summary` with
 * `detail.dataStoragePercent` for the Overview tile.
 */
export default class OptimizerStorage extends LightningElement {
  labels = {
    title: STORAGE,
    limitsHeading: LIMITS_HEADING,
    ownHeading: OWN_HEADING,
    ownIntro: OWN_INTRO,
    refresh: REFRESH,
    nearLimit: NEAR_LIMIT
  };

  columns = [
    { label: COLUMN_OBJECT, fieldName: 'label' },
    { label: COLUMN_RECORDS, fieldName: 'recordsText' },
    { label: COLUMN_MB, fieldName: 'estimatedMB', type: 'number' }
  ];

  storage;
  errorMessage;
  loading = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.storage = await getStorage();
      const data = ((this.storage && this.storage.limits) || []).find(
        (use) => use.name === 'DataStorageMB'
      );
      if (data) {
        this.dispatchEvent(
          new CustomEvent('summary', { detail: { dataStoragePercent: data.percent } })
        );
      }
    } catch (error) {
      this.errorMessage = (error && error.body && error.body.message) || UNEXPECTED_ERROR;
    } finally {
      this.loading = false;
    }
  }

  get limits() {
    return ((this.storage && this.storage.limits) || []).map((use) => ({
      ...use,
      label: LIMIT_LABELS[use.name] || use.name,
      usage: format(LIMIT_USAGE, use.used, use.max, use.percent),
      nearLimit: use.percent >= NEAR_LIMIT_PERCENT
    }));
  }

  get ownObjects() {
    const cap = this.storage ? this.storage.countCap : 0;
    return ((this.storage && this.storage.ownObjects) || []).map((own) => ({
      ...own,
      recordsText: own.moreThan ? format(MORE_THAN, cap) : String(own.records)
    }));
  }

  handleRefresh() {
    this.load();
  }
}
