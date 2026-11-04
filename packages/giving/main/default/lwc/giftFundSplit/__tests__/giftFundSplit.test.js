/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import GiftFundSplit from 'c/giftFundSplit';
import { getRecords } from 'lightning/uiRecordApi';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

const BUILDING = 'a01000000000001AAA';
const GENERAL = 'a01000000000002AAA';
const SCHOLAR = 'a01000000000003AAA';

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function render(props) {
  const element = createElement('c-gift-fund-split', { is: GiftFundSplit });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function all(element, id) {
  return [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];
}

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function type(input, value) {
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

function pick(picker, recordId) {
  picker.dispatchEvent(new CustomEvent('change', { detail: { recordId } }));
}

describe('c-gift-fund-split', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Giving_FundSplit_LeftToAssign: 'Left to assign: {0}',
      Giving_FundSplit_DividerLabel: 'Divider between {0} and {1}',
      Giving_FundSplit_DividerValue: '{0} {1}%, {2} {3}%'
    });
  });

  afterEach(() => {
    clearHelpTextForTest();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('starts with one row holding the whole gift when nothing is given', async () => {
    const element = render({ total: 100 });
    await flush();
    const amounts = all(element, 'amount');
    expect(amounts).toHaveLength(1);
    expect(Number(amounts[0].value)).toBe(100);
    expect(one(element, 'remove').disabled).toBe(true);
    expect(one(element, 'bar')).toBeNull();
    expect(element.valid).toBe(false);
  });

  it('shows the given split with percents and nothing left to assign', async () => {
    const element = render({
      total: 200,
      allocations: [
        { fundId: BUILDING, fundName: 'Building Fund', amount: 150 },
        { fundId: GENERAL, fundName: 'General', amount: 50 }
      ]
    });
    await flush();
    expect(all(element, 'percent').map((input) => input.value)).toEqual([75, 25]);
    const badge = element.shadowRoot.querySelector('c-barn-status-badge');
    expect(badge.status).toBe('done');
    expect(badge.label).toContain('Left to assign');
    expect(element.valid).toBe(true);
    const dividers = all(element, 'divider');
    expect(dividers).toHaveLength(1);
    expect(dividers[0].getAttribute('aria-label')).toBe(
      'Divider between Building Fund and General'
    );
    expect(dividers[0].getAttribute('aria-valuenow')).toBe('75');
  });

  it('fires change with the allocations and whether they can be saved', async () => {
    const element = render({ total: 100 });
    const handler = jest.fn();
    element.addEventListener('change', handler);
    await flush();

    pick(one(element, 'fund'), BUILDING);
    type(one(element, 'amount'), '70');
    await flush();
    let detail = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(detail).toEqual({ allocations: [{ fundId: BUILDING, amount: 70 }], valid: false });
    expect(element.shadowRoot.querySelector('c-barn-status-badge').status).toBe('attention');

    one(element, 'add-row').click();
    await flush();
    const amounts = all(element, 'amount');
    expect(Number(amounts[1].value)).toBe(30);
    pick(all(element, 'fund')[1], GENERAL);
    await flush();
    detail = handler.mock.calls[handler.mock.calls.length - 1][0].detail;
    expect(detail.valid).toBe(true);
    expect(detail.allocations).toEqual([
      { fundId: BUILDING, amount: 70 },
      { fundId: GENERAL, amount: 30 }
    ]);
  });

  it('turns a percent into an amount', async () => {
    const element = render({
      total: 80,
      allocations: [
        { fundId: BUILDING, amount: 40 },
        { fundId: GENERAL, amount: 40 }
      ]
    });
    await flush();
    type(all(element, 'percent')[0], '25');
    await flush();
    expect(Number(all(element, 'amount')[0].value)).toBe(20);
    expect(all(element, 'percent')[0].value).toBe('25');
  });

  it('names the problems once someone has edited', async () => {
    const element = render({
      total: 100,
      allocations: [
        { fundId: BUILDING, amount: 50 },
        { fundId: BUILDING, amount: 50 }
      ]
    });
    await flush();
    expect(one(element, 'problems')).toBeNull();
    type(all(element, 'amount')[1], '');
    await flush();
    const lines = [...one(element, 'problems').querySelectorAll('p')].map((p) => p.textContent);
    expect(lines).toEqual(['c.Giving_FundSplit_DuplicateFund', 'c.Giving_FundSplit_NeedsAmount']);
  });

  it('removes a row', async () => {
    const element = render({
      total: 90,
      allocations: [
        { fundId: BUILDING, amount: 30 },
        { fundId: GENERAL, amount: 30 },
        { fundId: SCHOLAR, amount: 30 }
      ]
    });
    await flush();
    all(element, 'remove')[1].click();
    await flush();
    expect(element.allocations).toEqual([
      { fundId: BUILDING, amount: 30 },
      { fundId: SCHOLAR, amount: 30 }
    ]);
    expect(element.shadowRoot.querySelector('c-barn-status-badge').label).toContain('30');
  });

  it('moves money between two funds from the keyboard and announces it', async () => {
    const element = render({
      total: 100,
      allocations: [
        { fundId: BUILDING, fundName: 'Building Fund', amount: 50 },
        { fundId: GENERAL, fundName: 'General', amount: 50 }
      ]
    });
    await flush();
    const divider = one(element, 'divider');
    divider.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight' }));
    await flush();
    expect(element.allocations.map((row) => row.amount)).toEqual([51, 49]);
    one(element, 'divider').dispatchEvent(new KeyboardEvent('keydown', { key: 'PageDown' }));
    await flush();
    expect(element.allocations.map((row) => row.amount)).toEqual([41, 59]);
    expect(one(element, 'announce').textContent).toBe('Building Fund 41%, General 59%');
    one(element, 'divider').dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    await flush();
    expect(element.allocations.map((row) => row.amount)).toEqual([41, 59]);
  });

  it('moves the divider with a pointer drag', async () => {
    const element = render({
      total: 100,
      allocations: [
        { fundId: BUILDING, fundName: 'Building Fund', amount: 50 },
        { fundId: GENERAL, fundName: 'General', amount: 50 }
      ]
    });
    await flush();
    one(element, 'bar').getBoundingClientRect = () => ({ left: 0, width: 200 });
    const divider = one(element, 'divider');
    divider.dispatchEvent(new CustomEvent('pointerdown'));
    const move = new CustomEvent('pointermove');
    move.clientX = 140;
    divider.dispatchEvent(move);
    divider.dispatchEvent(new CustomEvent('pointerup'));
    await flush();
    expect(element.allocations.map((row) => row.amount)).toEqual([70, 30]);
    expect(one(element, 'announce').textContent).toBe('Building Fund 70%, General 30%');
    const after = new CustomEvent('pointermove');
    after.clientX = 20;
    one(element, 'divider').dispatchEvent(after);
    await flush();
    expect(element.allocations.map((row) => row.amount)).toEqual([70, 30]);
  });

  it('names picked funds from the record wire', async () => {
    const element = render({
      total: 100,
      allocations: [
        { fundId: BUILDING, amount: 60 },
        { fundId: GENERAL, amount: 40 }
      ]
    });
    await flush();
    getRecords.emit({
      results: [
        { result: { id: BUILDING, fields: { Name: { value: 'Building Fund' } } } },
        { result: { id: GENERAL, fields: { Name: { value: 'General' } } } }
      ]
    });
    await flush();
    expect(one(element, 'divider').getAttribute('aria-label')).toBe(
      'Divider between Building Fund and General'
    );
  });

  it('lets a single row follow the gift amount', async () => {
    const element = render({ total: 100 });
    const handler = jest.fn();
    element.addEventListener('change', handler);
    await flush();
    element.total = 125;
    await flush();
    expect(element.allocations).toEqual([{ fundId: null, amount: 125 }]);
    expect(handler.mock.calls[0][0].detail.allocations).toEqual([{ fundId: null, amount: 125 }]);
    element.allocations = [{ fundId: null, amount: 125 }];
    await flush();
    expect(all(element, 'amount')).toHaveLength(1);
  });
});
