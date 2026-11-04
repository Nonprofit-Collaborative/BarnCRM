/**
 * Framework free (plan 9.9): the shapes Merge or Split renders, apart from Salesforce.
 */

export const STAYS = 'stays';
export const MOVES = 'moves';

const SURVIVOR = 'Survivor';
const VICTIM = 'Victim';

/** The record picker filter: households (by record type), never the household itself. */
export function householdPickerFilter(householdRecordTypeId, excludeId) {
  const criteria = [
    { fieldPath: 'RecordTypeId', operator: 'eq', value: householdRecordTypeId || '' }
  ];
  if (excludeId) {
    criteria.push({ fieldPath: 'Id', operator: 'ne', value: excludeId });
  }
  return { criteria };
}

/**
 * The comparison rows. The columns stay This Household then The Other Household whichever is
 * kept, so the values never jump sides when the roles are swapped: thisValue and otherValue
 * are read from the survivor or the victim accordingly. Each choice keeps its value word
 * (Survivor or Victim, what Apex expects) and is labelled by the side it shows.
 */
export function comparisonRows(fields, swapped, labels) {
  return (fields || []).map((field) => {
    const thisWord = swapped ? VICTIM : SURVIVOR;
    const otherWord = swapped ? SURVIVOR : VICTIM;
    return {
      ...field,
      thisValue: swapped ? field.victimValue : field.survivorValue,
      otherValue: swapped ? field.survivorValue : field.victimValue,
      options: [
        { label: labels.keepThis, value: thisWord },
        { label: labels.keepOther, value: otherWord }
      ],
      selected: SURVIVOR
    };
  });
}

/**
 * The split board: who stays and who moves (a ticked member moves), with the drag state's
 * source tile and target column marked.
 */
export function splitColumns(members, dragState) {
  const state = dragState || {};
  const column = (id, tiles) => ({
    id,
    isTarget: !!state.active && state.overZone === id && state.fromZone !== id,
    tiles: tiles.map((member) => ({
      ...member,
      isDragging: !!state.active && state.itemId === member.personId
    })),
    isEmpty: tiles.length === 0
  });
  const list = members || [];
  return [
    column(
      STAYS,
      list.filter((member) => !member.selected)
    ),
    column(
      MOVES,
      list.filter((member) => member.selected)
    )
  ];
}
