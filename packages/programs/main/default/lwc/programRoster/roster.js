/**
 * The Program Roster panel's display logic, framework free (plan Section 9.9): it takes the plain
 * roster the server returns and shapes the rows and figures the panel shows. No Lightning or
 * Salesforce import, so it runs and is tested anywhere.
 */

/** Replaces {0}, {1} and so on in a label with the values given. */
export function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.split(`{${index}}`).join(value),
    template || ''
  );
}

/** The stage figures, in picklist order: label, value and count. */
export function stageFigures(roster) {
  return (roster && roster.stages ? roster.stages : []).map((stage) => ({
    label: stage.label,
    value: stage.value,
    count: stage.count || 0
  }));
}

/** The stage options a picker offers. */
export function stageOptions(roster) {
  return stageFigures(roster).map(({ label, value }) => ({ label, value }));
}

/**
 * The rows the table lists: each with the name to show (the person, or the enrollment number when
 * the person cannot be read), the stage's label, a link and the hidden label of its stage picker.
 */
export function rosterRows(roster, stageForTemplate) {
  const labelOf = {};
  stageFigures(roster).forEach((stage) => {
    labelOf[stage.value] = stage.label;
  });
  return (roster && roster.enrollments ? roster.enrollments : []).map((row) => {
    const who = row.personName || row.name;
    return {
      ...row,
      displayName: who,
      href: `/lightning/r/Enrollment__c/${row.recordId}/view`,
      stageLabel: labelOf[row.stage] || row.stage,
      stageFor: format(stageForTemplate, who),
      startDate: row.startDate || '',
      endDate: row.endDate || ''
    };
  });
}

/** The label of a stage value, or the value itself. */
export function stageLabel(roster, value) {
  const found = stageFigures(roster).find((stage) => stage.value === value);
  return found ? found.label : value;
}
