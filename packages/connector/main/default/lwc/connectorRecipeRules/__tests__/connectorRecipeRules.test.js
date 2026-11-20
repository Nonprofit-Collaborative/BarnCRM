import {
  newDocument,
  readDocument,
  allSteps,
  freeId,
  newStep,
  flatten,
  addStep,
  removeStep,
  moveStep,
  updateStep,
  slotsOf,
  syncSlots,
  unsafeValue,
  pathProblem,
  isPill,
  headerNameOk,
  problems,
  pathSuggestions,
  readSample,
  readCodes,
  statusVariant,
  stepRows,
  setTrigger,
  updateTrigger,
  triggerProblem,
  runAsKey,
  triggerKindKey,
  MAX_STEPS
} from 'c/connectorRecipeRules';

const keys = (document) => problems(document).map((problem) => problem.key);

function callStep(changes) {
  return {
    ...newStep(newDocument(), 'callApp'),
    id: 'call1',
    connection: 'BarnConn_rest_a',
    ...changes
  };
}

describe('c/connectorRecipeRules', () => {
  it('reads a document, or starts a new one for blank or unreadable text', () => {
    expect(readDocument('')).toEqual(newDocument());
    expect(readDocument('not json')).toEqual(newDocument());
    expect(readDocument('[1]')).toEqual(newDocument());
    expect(readDocument('{"version":1}').steps).toEqual([]);
  });

  it('adds, nests, moves, updates and removes steps without changing the original', () => {
    let document = newDocument();
    document = addStep(document, 'find');
    document = addStep(document, 'if');
    const ifAddress = flatten(document)[1].address;
    document = addStep(document, 'upsert', ifAddress, 'then');
    document = addStep(document, 'stop', ifAddress, 'otherwise');
    const rows = flatten(document);
    expect(rows.map((row) => [row.step.id, row.depth, row.branch])).toEqual([
      ['find1', 0, 'steps'],
      ['if1', 0, 'steps'],
      ['upsert1', 1, 'then'],
      ['stop1', 1, 'otherwise']
    ]);
    expect(allSteps(document)).toHaveLength(4);
    expect(freeId(document, 'find')).toBe('find2');

    const moved = moveStep(document, rows[1].address, -1);
    expect(moved.steps.map((step) => step.id)).toEqual(['if1', 'find1']);
    expect(document.steps[0].id).toBe('find1');
    expect(moveStep(document, rows[0].address, -1).steps[0].id).toBe('find1');

    const updated = updateStep(document, rows[2].address, { map: 'a0C000000000001' });
    expect(updated.steps[1].then[0].map).toBe('a0C000000000001');
    expect(removeStep(document, rows[3].address).steps[1].otherwise).toEqual([]);
  });

  it('gives each kind its fields', () => {
    const document = newDocument();
    expect(newStep(document, 'update').recordId).toBe('');
    expect(newStep(document, 'find').stopIfNone).toBe(false);
    expect(newStep(document, 'callApp').method).toBe('GET');
    expect(newStep(document, 'if').conditions).toHaveLength(1);
    expect(newStep(document, 'stop').outcome).toBe('Succeeded');
  });

  it('keeps path values in step with the slots of a path', () => {
    expect(slotsOf('/people/{id}/notes/{id}/{note}')).toEqual(['id', 'note']);
    expect(
      syncSlots('/people/{id}/{tag}', [
        { name: 'id', path: 'trigger.id' },
        { name: 'gone', path: 'x' }
      ])
    ).toEqual([
      { name: 'id', path: 'trigger.id' },
      { name: 'tag', path: '' }
    ]);
  });

  it('refuses merge fields, line breaks and unsafe paths (F1, F4)', () => {
    expect(unsafeValue('{!$Credential.Password}')).toBe(true);
    expect(unsafeValue('a\r\nX-Evil: 1')).toBe(true);
    expect(unsafeValue('plain')).toBe(false);
    expect(pathProblem('/v1/people')).toBe(false);
    [
      '',
      'v1',
      '//evil.example',
      '/a@b',
      '/a\\b',
      '/a?b=1',
      '/a#b',
      '/a b',
      '/{!x}',
      `/${'a'.repeat(1000)}`
    ].forEach((path) => expect(pathProblem(path)).toBe(true));
    expect(isPill('steps.find1.records[0].Id')).toBe(true);
    expect(isPill('$Credential.x')).toBe(false);
    expect(headerNameOk('X-Request-Id')).toBe(true);
    expect(headerNameOk('Authorization')).toBe(false);
    expect(headerNameOk('Host')).toBe(false);
    expect(headerNameOk('Bad Name')).toBe(false);
  });

  it('reports a merge field anywhere first and alone', () => {
    const document = {
      ...newDocument(),
      steps: [{ ...newStep(newDocument(), 'stop'), message: '{!x}' }]
    };
    expect(keys(document)).toEqual(['Connector_Recipe_ErrorMergeField']);
  });

  it('reports each step problem with the step name', () => {
    expect(keys(newDocument())).toEqual(['Connector_Recipe_ErrorNoSteps']);
    const document = {
      ...newDocument(),
      steps: [
        { id: 'find1', kind: 'find', query: null },
        { id: 'update1', kind: 'update', map: 'm', input: 'trigger', recordId: 'oops' },
        { id: 'if1', kind: 'if', conditions: [], then: [], otherwise: [] },
        { id: 'stop1', kind: 'stop', outcome: 'Maybe' },
        { id: 'odd1', kind: 'odd' },
        { id: 'find1', kind: 'stop', outcome: 'Succeeded' }
      ]
    };
    expect(problems(document)).toEqual([
      { key: 'Connector_Recipe_ErrorFind', args: ['find1'] },
      { key: 'Connector_Recipe_ErrorRecordId', args: ['update1'] },
      { key: 'Connector_Recipe_ErrorCondition', args: ['if1'] },
      { key: 'Connector_Recipe_ErrorStop', args: ['stop1'] },
      { key: 'Connector_Recipe_ErrorStepKind', args: ['odd1'] },
      { key: 'Connector_Recipe_ErrorStepId', args: ['find1'] }
    ]);
  });

  it('checks Call an App connection, method, path, slots, query, headers and codes', () => {
    const one = (step) => keys({ ...newDocument(), steps: [step] });
    expect(one(callStep({}))).toEqual([]);
    expect(one(callStep({ connection: '' }))).toEqual(['Connector_Recipe_ErrorConnection']);
    expect(one(callStep({ method: 'TRACE' }))).toEqual(['Connector_Recipe_ErrorMethod']);
    expect(one(callStep({ path: '//evil' }))).toEqual(['Connector_Recipe_ErrorRequestPath']);
    expect(one(callStep({ path: '/p/{id}' }))).toEqual(['Connector_Recipe_ErrorSlot']);
    expect(one(callStep({ path: '/p/{id}', pathValues: [{ name: 'id', value: 'a\nb' }] }))).toEqual(
      ['Connector_Recipe_ErrorSlot']
    );
    expect(one(callStep({ query: [{ name: 'a b', value: '1' }] }))).toEqual([
      'Connector_Recipe_ErrorQuery'
    ]);
    expect(one(callStep({ headers: [{ name: 'Authorization', value: 'x' }] }))).toEqual([
      'Connector_Recipe_ErrorHeader'
    ]);
    expect(one(callStep({ success: [700] }))).toEqual(['Connector_Recipe_ErrorCodes']);
    expect(one(callStep({ bodyInput: 'nowhere' }))).toEqual(['Connector_Recipe_ErrorMap']);
  });

  it('limits nesting and the number of steps', () => {
    const deep = {
      ...newDocument(),
      steps: [
        {
          id: 'if1',
          kind: 'if',
          conditions: [{ path: 'trigger', operator: 'is null' }],
          then: [
            {
              id: 'if2',
              kind: 'if',
              conditions: [{ path: 'trigger', operator: 'is null' }],
              then: [
                { id: 'if3', kind: 'if', conditions: [{ path: 'trigger', operator: 'is null' }] }
              ]
            }
          ]
        }
      ]
    };
    expect(keys(deep)).toEqual(['Connector_Recipe_ErrorNesting']);
    const many = newDocument();
    for (let n = 0; n <= MAX_STEPS; n++) {
      many.steps.push({ id: `stop${n}`, kind: 'stop', outcome: 'Succeeded' });
    }
    expect(keys(many)).toEqual(['Connector_Recipe_ErrorTooManySteps']);
  });

  it('suggests value paths from the sample and earlier steps', () => {
    const document = {
      version: 1,
      trigger: { kind: 'manual', sample: { email: 'a@b.org', person: { last: 'Ada' } } },
      steps: [
        { id: 'find1', kind: 'find', query: { object: 'Contact', fields: ['Email'] } },
        { id: 'upsert1', kind: 'upsert' },
        { id: 'call1', kind: 'callApp' }
      ]
    };
    expect(pathSuggestions(document, document.steps[2])).toEqual([
      'trigger',
      'trigger.email',
      'trigger.person',
      'trigger.person.last',
      'steps.find1.count',
      'steps.find1.records[0].Id',
      'steps.find1.records[0].Email',
      'steps.upsert1.id',
      'steps.upsert1.action'
    ]);
  });

  it('reads sample data and success codes', () => {
    expect(readSample('')).toEqual({});
    expect(readSample('{"a":1}')).toEqual({ a: 1 });
    expect(readSample('nope')).toBeUndefined();
    expect(readCodes('200, 201')).toEqual([200, 201]);
    expect(readCodes('')).toEqual([]);
    expect(readCodes('200, ok')).toBeUndefined();
  });

  it('gives badge variants and step rows with what a test would have done', () => {
    expect(statusVariant('Failed')).toBe('error');
    expect(statusVariant('Unknown')).toBe('neutral');
    const rows = stepRows(
      JSON.stringify([
        {
          step: 'call1',
          kind: 'callApp',
          outcome: 'Succeeded',
          ms: 5,
          status: 200,
          ids: ['a', 'b']
        }
      ]),
      JSON.stringify({ call1: { request: { method: 'POST' } } })
    );
    expect(rows[0].ids).toBe('a, b');
    expect(rows[0].preview).toContain('POST');
    expect(stepRows('bad', 'bad')).toEqual([]);
    expect(statusVariant('Waiting')).toBe('warning');
  });

  it('switches triggers keeping the sample, and checks a schedule as the server does', () => {
    const start = readDocument(JSON.stringify({ trigger: { kind: 'manual', sample: { a: 1 } } }));
    const scheduled = setTrigger(start, 'schedule');
    expect(scheduled.trigger).toEqual({
      kind: 'schedule',
      every: 'day',
      at: '08:00',
      sample: { a: 1 }
    });
    expect(start.trigger.kind).toBe('manual');
    expect(triggerProblem(scheduled.trigger)).toBeNull();

    const weekly = updateTrigger(scheduled, { every: 'week' });
    expect(weekly.trigger.day).toBe('MON');
    expect(updateTrigger(weekly, { every: 'hour' }).trigger.day).toBeUndefined();
    expect(triggerProblem({ kind: 'schedule', every: 'day', at: '25:00' })).toBe(
      'Connector_Recipe_ErrorSchedule'
    );
    expect(triggerProblem({ kind: 'schedule', every: 'month' })).toBe(
      'Connector_Recipe_ErrorSchedule'
    );
    expect(triggerProblem({ kind: 'schedule', every: '15m' })).toBeNull();
    expect(triggerProblem({ kind: 'webhook' })).toBe('Connector_Recipe_ErrorTrigger');
    expect(
      keys({ ...newDocument(), trigger: { kind: 'schedule', every: 'week', at: '09:00' } })
    ).toContain('Connector_Recipe_ErrorSchedule');
  });

  it('checks a Record Change trigger and suggests what it gives the steps', () => {
    const watching = setTrigger(newDocument(), 'record');
    expect(triggerProblem(watching.trigger)).toBe('Connector_Recipe_ErrorRecordTrigger');
    const ready = updateTrigger(watching, {
      query: { version: 1, object: 'Contact', fields: ['LastName'] },
      savedQuery: 'a0Q000000000001'
    });
    expect(triggerProblem(ready.trigger)).toBeNull();
    expect(triggerProblem({ ...ready.trigger, limit: 201 })).toBe(
      'Connector_Recipe_ErrorRecordTrigger'
    );
    expect(triggerProblem({ ...ready.trigger, on: 'deleted' })).toBe(
      'Connector_Recipe_ErrorRecordTrigger'
    );
    expect(triggerProblem({ ...ready.trigger, limit: 50, mode: 'batch' })).toBeNull();

    expect(pathSuggestions(ready, null)).toEqual(
      expect.arrayContaining(['trigger.recordId', 'trigger.record.Id', 'trigger.record.LastName'])
    );
    const batch = updateTrigger(ready, { mode: 'batch' });
    expect(pathSuggestions(batch, null)).toEqual(
      expect.arrayContaining(['trigger.recordIds', 'trigger.records[0].LastName'])
    );
    expect(pathSuggestions(setTrigger(newDocument(), 'schedule'), null)).toContain(
      'trigger.scheduledAt'
    );
  });

  it('names Run As values and trigger kinds by help key', () => {
    expect(runAsKey('IntegrationUser')).toBe('Connector_RunAs_IntegrationUser');
    expect(runAsKey('System')).toBe('Connector_RunAs_System');
    expect(runAsKey(undefined)).toBe('Connector_RunAs_Automation');
    expect(triggerKindKey('Schedule')).toBe('Connector_Trigger_Schedule');
    expect(triggerKindKey('RecordChange')).toBe('Connector_Trigger_Record');
    expect(triggerKindKey('Manual')).toBe('Connector_Trigger_Manual');
  });
});
