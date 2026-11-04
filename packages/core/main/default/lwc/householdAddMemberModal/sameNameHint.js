/**
 * Framework free (plan 9.9): how the same-name hint names an existing person, so two people
 * called Ana Garcia can be told apart at a glance: "Ana Garcia, Tampa (Garcia Household)".
 * The city and the household are each left out when unknown.
 */
export function describeSameNamePerson(match) {
  if (!match) {
    return '';
  }
  let text = match.name || '';
  if (match.city) {
    text += ', ' + match.city;
  }
  if (match.householdName) {
    text += ' (' + match.householdName + ')';
  }
  return text;
}

/** A person's name from its parts, without stray spaces. */
export function joinName(firstName, lastName) {
  return [firstName, lastName]
    .map((part) => (part || '').trim())
    .filter((part) => part)
    .join(' ');
}
