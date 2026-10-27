import { LightningElement, api } from 'lwc';
import explain from '@salesforce/apex/RollupExplainController.explain';
import TITLE from '@salesforce/label/c.Core_RollupEase_ExplainTitle';
import EMPTY from '@salesforce/label/c.Core_RollupEase_ExplainEmpty';
import ADMIN from '@salesforce/label/c.Core_RollupEase_ExplainAdmin';
import SEEN from '@salesforce/label/c.Core_RollupEase_ExplainSeen';
import REFRESH from '@salesforce/label/c.Core_RollupEase_ExplainRefresh';
import ROWS_HEADING from '@salesforce/label/c.Core_RollupEase_RowsHeading';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';

/**
 * Explain These Totals (Rollup Builder ease of use U5, ADR-0136): on a record page, each total a
 * BarnCRM rollup fills there, what it counts, how many records counted and were left out and
 * why, when it was last calculated, and links to the records read. Reads only; writes nothing.
 */
export default class RollupExplain extends LightningElement {
  @api recordId;

  labels = { title: TITLE, empty: EMPTY, seen: SEEN, refresh: REFRESH, rowsHeading: ROWS_HEADING };

  explanations;
  error;
  loading = false;

  connectedCallback() {
    this.load();
  }

  load() {
    this.loading = true;
    this.error = undefined;
    return explain({ recordId: this.recordId })
      .then((result) => {
        this.explanations = (result || []).map((item) => ({
          ...item,
          heading: `${item.fieldLabel}: ${item.value}`,
          adminLine: item.calculatedNow ? ADMIN.replace('{0}', item.calculatedNow) : undefined,
          rowList: ((item.rows && item.rows.rows) || []).map((row) => ({
            ...row,
            url: '/' + row.recordId,
            outcomeClass: row.counted ? 'slds-text-color_success' : 'slds-text-color_weak'
          }))
        }));
      })
      .catch((error) => {
        this.explanations = undefined;
        this.error =
          error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
      })
      .finally(() => {
        this.loading = false;
      });
  }

  handleRefresh() {
    return this.load();
  }

  get isEmpty() {
    return Array.isArray(this.explanations) && this.explanations.length === 0;
  }

  get hasExplanations() {
    return Array.isArray(this.explanations) && this.explanations.length > 0;
  }
}
