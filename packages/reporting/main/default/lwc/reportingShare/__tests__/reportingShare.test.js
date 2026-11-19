import { createElement } from 'lwc';
import ReportingShare from 'c/reportingShare';
import findPeople from '@salesforce/apex/ReportingLibrary.findPeople';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ReportingLibrary.findPeople', () => ({ default: jest.fn() }), {
  virtual: true
});

function mount(props) {
  const element = createElement('c-reporting-share', { is: ReportingShare });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];

describe('c-reporting-share', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('finds people and groups, sets access, removes and saves', async () => {
    findPeople.mockResolvedValue([
      { id: '005000000000002AAA', name: 'Ben Ames', kind: 'user' },
      { id: '00G000000000001AAA', name: 'Board', kind: 'group' }
    ]);
    const element = mount({
      title: 'By Fund',
      sharing: { users: [{ id: '005000000000001AAA', name: 'Ana', access: 'edit' }] }
    });
    const saved = jest.fn();
    element.addEventListener('save', saved);
    await Promise.resolve();
    expect(findAll(element, 'access')[0].value).toBe('edit');
    await expectAccessible(element);

    find(element, 'search').dispatchEvent(new CustomEvent('change', { detail: { value: 'b' } }));
    jest.runAllTimers();
    expect(findPeople).not.toHaveBeenCalled();

    find(element, 'search').dispatchEvent(new CustomEvent('change', { detail: { value: 'bo' } }));
    jest.runAllTimers();
    await Promise.resolve();
    await Promise.resolve();
    expect(findPeople).toHaveBeenCalledWith({ term: 'bo' });
    const adds = findAll(element, 'add');
    expect(adds).toHaveLength(2);
    expect(adds[1].title).toBe('c.Reporting_Share_GroupName');
    adds[1].click();
    await Promise.resolve();
    expect(findAll(element, 'add')).toHaveLength(1);

    findAll(element, 'access')[1].dispatchEvent(
      new CustomEvent('change', { detail: { value: 'edit' } })
    );
    findAll(element, 'remove')[0].click();
    await Promise.resolve();
    find(element, 'save').click();
    expect(saved.mock.calls[0][0].detail.sharing).toEqual({
      users: [],
      groups: [{ id: '00G000000000001AAA', name: 'Board', access: 'edit' }]
    });
    expect(element.sharing.groups).toHaveLength(1);
  });

  it('says when only the owner can see it, shows search errors and cancels', async () => {
    findPeople.mockRejectedValue({ body: { message: 'Search failed' } });
    const element = mount({ sharing: null });
    const cancelled = jest.fn();
    element.addEventListener('cancel', cancelled);
    await Promise.resolve();
    expect(find(element, 'none')).not.toBeNull();
    find(element, 'search').dispatchEvent(new CustomEvent('change', { detail: { value: 'zed' } }));
    jest.runAllTimers();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    expect(find(element, 'error').message).toBe('Search failed');
    find(element, 'cancel').click();
    expect(cancelled).toHaveBeenCalled();
  });
});
