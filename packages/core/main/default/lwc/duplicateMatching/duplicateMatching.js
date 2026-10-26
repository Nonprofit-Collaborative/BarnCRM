import { LightningElement } from 'lwc';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canReviewDuplicates from '@salesforce/customPermission/Review_Duplicate_Suggestions';

import TITLE from '@salesforce/label/c.Core_DuplicateMatching_Title';
import INTRO from '@salesforce/label/c.Core_DuplicateMatching_Intro';
import REVIEW from '@salesforce/label/c.Core_DuplicateMatching_Review';
import NO_ACCESS from '@salesforce/label/c.Core_DuplicateMatching_NoAccess';

const REVIEW_AREA = 'review';

/**
 * The Duplicate Matching tab (ADR-NEXT, admin guide duplicates.md): one tab per area, each
 * created only when first opened. Review needs Manage BarnCRM Settings or Review Duplicate
 * Suggestions (BarnCRM Duplicate Review, which reads the list but cannot scan, dismiss or
 * merge). Each embedded component keeps its own server check.
 */
export default class DuplicateMatching extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    review: REVIEW,
    noAccess: NO_ACCESS
  };

  activeArea;
  /** The areas opened so far; an area stays loaded once opened. */
  opened = {};

  connectedCallback() {
    const first = this.areas[0];
    if (first) {
      this.activeArea = first;
      this.opened = { [first]: true };
    }
  }

  get canSeeReview() {
    return Boolean(canManageSettings || canReviewDuplicates);
  }

  /** The areas this person may open, in the order the tabs show them. */
  get areas() {
    return this.canSeeReview ? [REVIEW_AREA] : [];
  }

  get hasAnyArea() {
    return this.areas.length > 0;
  }

  get reviewOpened() {
    return Boolean(this.opened[REVIEW_AREA]);
  }

  handleActive(event) {
    const name = event.target.value;
    this.activeArea = name;
    if (!this.opened[name]) {
      this.opened = { ...this.opened, [name]: true };
    }
  }
}
