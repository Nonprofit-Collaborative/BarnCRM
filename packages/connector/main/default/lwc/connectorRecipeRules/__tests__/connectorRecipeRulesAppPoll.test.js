import {
  newDocument,
  setTrigger,
  triggerProblem,
  triggerKindKey,
  pathSuggestions,
  WATERMARK_PATH
} from 'c/connectorRecipeRules';

/** A complete App Poll trigger, as the editor saves it (R-CR20). */
function poll(changes = {}) {
  return {
    ...setTrigger(newDocument(), 'appPoll').trigger,
    connection: 'BarnConn_rest_abc123',
    path: '/lists/{listId}/members',
    pathValues: [{ name: 'listId', value: 'a1b2' }],
    query: [{ name: 'since_last_changed', path: WATERMARK_PATH }],
    items: 'members',
    id: 'id',
    stamp: 'last_changed',
    ...changes
  };
}

describe('c/connectorRecipeRules App Poll (CN-13)', () => {
  it('starts an App Poll trigger with one run per item and the sample kept', () => {
    const document = newDocument();
    document.trigger.sample = { item: { email: 'ann@example.org' } };
    const trigger = setTrigger(document, 'appPoll').trigger;
    expect(trigger).toMatchObject({ kind: 'appPoll', mode: 'each', id: 'id', items: '' });
    expect(trigger.sample).toEqual({ item: { email: 'ann@example.org' } });
    expect(triggerKindKey('AppPoll')).toBe('Connector_Trigger_AppPoll');
  });

  it('accepts a complete trigger and a blank item list', () => {
    expect(triggerProblem(poll())).toBeNull();
    expect(triggerProblem(poll({ items: '', mode: 'batch', limit: 50 }))).toBeNull();
    expect(triggerProblem(poll({ items: 'data.items[0].list' }))).toBeNull();
  });

  it.each([
    ['no connection', { connection: '' }],
    ['a credential BarnCRM did not make', { connection: 'Barn_Stripe' }],
    ['a path without a slash', { path: 'lists' }],
    ['a path naming another host', { path: '//evil.example.org/x' }],
    ['a slot left empty', { pathValues: [] }],
    ['a merge field in a value (F1)', { query: [{ name: 'q', value: '{!$Credential.x}' }] }],
    ['a value read from run data', { query: [{ name: 'q', path: 'trigger.email' }] }],
    ['no item id', { id: '' }],
    ['no stamp', { stamp: '' }],
    ['an item path with spaces', { stamp: 'last changed' }],
    ['an unknown mode', { mode: 'some' }],
    ['a limit over 200', { limit: 201 }],
    ['a reserved header', { headers: [{ name: 'Authorization', value: 'x' }] }]
  ])('refuses %s', (_name, changes) => {
    expect(triggerProblem(poll(changes))).toBe('Connector_Recipe_ErrorAppPoll');
  });

  it('suggests the item paths for each mode', () => {
    const each = { ...newDocument(), trigger: poll() };
    expect(pathSuggestions(each)).toEqual(
      expect.arrayContaining(['trigger.itemId', 'trigger.item'])
    );
    const batch = { ...newDocument(), trigger: poll({ mode: 'batch' }) };
    expect(pathSuggestions(batch)).toEqual(
      expect.arrayContaining(['trigger.itemIds', 'trigger.items'])
    );
  });
});
