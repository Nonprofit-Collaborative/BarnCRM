/**
 * The Programs card's display logic, framework free (plan Section 9.9): it shapes the plain list
 * the server returns into the rows the card shows. No Lightning or Salesforce import, so it runs
 * and is tested anywhere.
 */

/** The rows, in the server's order (open ones first), each with its links and badge. */
export function enrollmentRows(result) {
  return (result && result.enrollments ? result.enrollments : []).map((row) => ({
    ...row,
    key: row.recordId,
    enrollmentHref: `/lightning/r/Enrollment__c/${row.recordId}/view`,
    programLabel: row.programName || '',
    badgeClass: row.isOpen
      ? 'slds-badge slds-theme_success stage'
      : 'slds-badge slds-badge_lightest stage',
    startDate: row.startDate || '',
    endDate: row.endDate || ''
  }));
}

/** Whether there is a card to show: only for a person the user may see enrollments of. */
export function canShow(result) {
  return !!(result && result.canSee === true);
}
