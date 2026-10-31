/**
 * The Programs settings page's logic, framework free (plan Section 9.9): it turns the plain
 * settings the server returns into what the page shows. No Lightning or Salesforce import.
 */

/** Replaces {0}, {1} and so on in a label with the values given. */
export function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.split(`{${index}}`).join(value),
    template || ''
  );
}

/** One row per intake picklist: its name, its choices as one line, its default and its link. */
export function picklistRows(settings, labels) {
  const picklists = settings && settings.intakePicklists ? settings.intakePicklists : [];
  return picklists.map((picklist) => ({
    key: picklist.apiName,
    label: picklist.label,
    choices: (picklist.values || []).join(', '),
    defaultText: picklist.defaultValue ? format(labels.defaultValue, picklist.defaultValue) : '',
    setupUrl: picklist.setupUrl,
    linkLabel: format(labels.changeFor, picklist.label)
  }));
}
