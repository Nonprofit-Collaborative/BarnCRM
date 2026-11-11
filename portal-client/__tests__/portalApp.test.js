import { mountPortal } from '../src/portalApp.js';
import { PortalError } from '../src/portalApi.js';

const MENU = {
  ok: true,
  title: 'My Account',
  firstName: 'Pat',
  pages: [
    { key: 'profile', title: 'My Details' },
    { key: 'roles', title: 'My Roles' }
  ]
};

const PROFILE = {
  ok: true,
  key: 'profile',
  title: 'My Details',
  kind: 'person',
  canUpdate: true,
  canCreate: false,
  actions: [],
  fields: [
    { field: 'FirstName', label: 'First Name', type: 'string', edit: false },
    { field: 'MobilePhone', label: 'Mobile', type: 'phone', edit: true }
  ],
  records: [{ id: '003A', values: { FirstName: '<b>Pat</b>', MobilePhone: '555' } }]
};

function flush() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function fakeApi(overrides) {
  return {
    start: jest.fn(() => Promise.resolve({ ok: true, challenge: 'ch' })),
    verify: jest.fn(() => Promise.resolve({ ok: true, status: 'signedIn' })),
    secondFactor: jest.fn(() => Promise.resolve({ ok: true, status: 'signedIn' })),
    me: jest.fn(() => Promise.resolve(MENU)),
    page: jest.fn(() => Promise.resolve(PROFILE)),
    save: jest.fn(() => Promise.resolve({ ok: true, id: '003A' })),
    action: jest.fn(() => Promise.resolve({ ok: true, message: 'Thanks sent' })),
    logout: jest.fn(() => Promise.resolve({ ok: true })),
    ...overrides
  };
}

function submit(root, name, value) {
  const input = root.querySelector('[name="' + name + '"]');
  input.value = value;
  input.closest('form').dispatchEvent(new Event('submit', { cancelable: true }));
}

function buttonNamed(root, text) {
  return Array.from(root.querySelectorAll('button')).find((b) => b.textContent === text);
}

describe('mountPortal', () => {
  let root;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    root.remove();
  });

  it('asks for an email when nobody is signed in, then signs in with the code', async () => {
    let signedIn = false;
    const api = fakeApi({
      me: jest.fn(() =>
        signedIn ? Promise.resolve(MENU) : Promise.reject(new PortalError('not_signed_in', 401))
      ),
      verify: jest.fn(() => {
        signedIn = true;
        return Promise.resolve({ ok: true, status: 'signedIn' });
      })
    });

    await mountPortal(root, { api });
    expect(root.querySelector('h2').textContent).toBe('Sign In');

    submit(root, 'email', ' pat@example.org ');
    await flush();
    expect(api.start).toHaveBeenCalledWith('pat@example.org');
    expect(root.querySelector('h2').textContent).toBe('Check Your Email');

    submit(root, 'code', '123456');
    await flush();
    await flush();
    expect(api.verify).toHaveBeenCalledWith('ch', '123456');
    expect(root.querySelector('h3').textContent).toBe('My Details');
  });

  it('shows a wrong code as a message and stays on the code screen', async () => {
    const api = fakeApi({
      me: jest.fn(() => Promise.reject(new PortalError('not_signed_in', 401))),
      verify: jest.fn(() => Promise.reject(new PortalError('code_invalid', 400)))
    });
    await mountPortal(root, { api });
    submit(root, 'email', 'pat@example.org');
    await flush();

    submit(root, 'code', '000000');
    await flush();

    expect(root.querySelector('[role="alert"]').textContent).toMatch(/did not work/);
    expect(root.querySelector('[name="code"]')).not.toBeNull();
  });

  it('shows the authenticator key when the portal needs enrolment', async () => {
    const api = fakeApi({
      me: jest.fn(() => Promise.reject(new PortalError('not_signed_in', 401))),
      verify: jest.fn(() =>
        Promise.resolve({ ok: true, status: 'enroll', secret: 'ABCDEF', uri: 'otpauth://totp/x' })
      )
    });
    await mountPortal(root, { api });
    submit(root, 'email', 'pat@example.org');
    await flush();
    submit(root, 'code', '123456');
    await flush();

    expect(root.querySelector('h2').textContent).toBe('Set Up Your Authenticator');
    expect(root.querySelector('code').textContent).toBe('ABCDEF');
    submit(root, 'code', '654321');
    await flush();
    expect(api.secondFactor).toHaveBeenCalledWith('ch', '654321');
  });

  it('shows record values as text, never as HTML, and saves only editable fields', async () => {
    const api = fakeApi();
    await mountPortal(root, { api });

    expect(root.querySelector('b')).toBeNull();
    expect(root.querySelector('dd').textContent).toBe('<b>Pat</b>');
    expect(root.querySelector('p').textContent).toBe('Hello, Pat');

    buttonNamed(root, 'Edit').click();
    expect(root.querySelector('[name="FirstName"]')).toBeNull();
    submit(root, 'MobilePhone', '555-0100');
    await flush();

    expect(api.save).toHaveBeenCalledWith('profile', '003A', { MobilePhone: '555-0100' });
  });

  it('edits a multi-select picklist and sends only the fields that changed', async () => {
    const page = {
      ...PROFILE,
      fields: [
        {
          field: 'Skills__c',
          label: 'Skills',
          type: 'multipicklist',
          edit: true,
          options: [
            { value: 'Cook', label: 'Cooking' },
            { value: 'Drive', label: 'Driving' }
          ]
        },
        {
          field: 'Shirt__c',
          label: 'Shirt',
          type: 'picklist',
          edit: true,
          options: [{ value: 'M', label: 'Medium' }]
        },
        { field: 'MobilePhone', label: 'Mobile', type: 'phone', edit: true }
      ],
      records: [
        { id: '003A', values: { Skills__c: 'Cook;Drive', Shirt__c: 'XL', MobilePhone: '555' } }
      ]
    };
    const api = fakeApi({ page: jest.fn(() => Promise.resolve(page)) });
    await mountPortal(root, { api });
    expect(root.querySelector('dd').textContent).toBe('Cooking, Driving');

    buttonNamed(root, 'Edit').click();
    const skills = root.querySelector('[name="Skills__c"]');
    expect(skills.multiple).toBe(true);
    expect(root.querySelector('[name="Shirt__c"]').value).toBe('XL');
    skills.options[1].selected = false;
    submit(root, 'MobilePhone', '555');
    await flush();

    expect(api.save).toHaveBeenCalledWith('profile', '003A', { Skills__c: 'Cook' });
  });

  it('shows and edits a date and time in the visitor own time zone', async () => {
    const stored = '2026-01-31T14:00:00.000Z';
    const page = {
      ...PROFILE,
      fields: [{ field: 'Starts__c', label: 'Starts', type: 'datetime', edit: true }],
      records: [{ id: '003A', values: { Starts__c: stored } }]
    };
    const api = fakeApi({ page: jest.fn(() => Promise.resolve(page)) });
    await mountPortal(root, { api });
    expect(root.querySelector('dd').textContent).toBe(new Date(stored).toLocaleString());

    buttonNamed(root, 'Edit').click();
    const local = new Date(Date.parse(stored) - new Date(stored).getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16);
    expect(root.querySelector('[name="Starts__c"]').value).toBe(local);
    const later = local.slice(0, 11) + '18:30';
    submit(root, 'Starts__c', later);
    await flush();

    expect(api.save).toHaveBeenCalledWith('profile', '003A', {
      Starts__c: new Date(later).toISOString()
    });
  });

  it('reads the page again after a module action', async () => {
    const page = { ...PROFILE, actions: [{ name: 'Test.Thanks', label: 'Say Thanks' }] };
    const api = fakeApi({ page: jest.fn(() => Promise.resolve(page)) });
    await mountPortal(root, { api });

    buttonNamed(root, 'Say Thanks').click();
    await flush();
    await flush();

    expect(api.action).toHaveBeenCalledWith('profile', '003A', 'Test.Thanks');
    expect(api.page).toHaveBeenCalledTimes(2);
    expect(root.querySelector('[role="status"]').textContent).toBe('Thanks sent');
  });

  it('opens a secure web address as a link and shows any other address as text', async () => {
    const page = {
      ...PROFILE,
      fields: [
        { field: 'Form_Link__c', label: 'Application Form', type: 'url', edit: false },
        { field: 'Site__c', label: 'Site', type: 'url', edit: false }
      ],
      records: [
        {
          id: '003A',
          values: { Form_Link__c: 'https://example.org/f?t=1', Site__c: 'javascript:alert(1)' }
        }
      ]
    };
    const api = fakeApi({ page: jest.fn(() => Promise.resolve(page)) });
    await mountPortal(root, { api });

    const links = root.querySelectorAll('dd a');
    expect(links).toHaveLength(1);
    expect(links[0].getAttribute('href')).toBe('https://example.org/f?t=1');
    expect(links[0].textContent).toBe('Application Form');
    expect(root.querySelectorAll('dd')[1].textContent).toBe('javascript:alert(1)');
  });

  it('signs out back to the email screen', async () => {
    const api = fakeApi();
    await mountPortal(root, { api });

    buttonNamed(root, 'Sign Out').click();
    await flush();

    expect(api.logout).toHaveBeenCalled();
    expect(root.querySelector('h2').textContent).toBe('Sign In');
  });

  it('starts a page at its heading and the edit form at its first box', async () => {
    const api = fakeApi();
    await mountPortal(root, { api });
    expect(document.activeElement).toBe(root.querySelector('h3'));

    buttonNamed(root, 'Edit').click();
    expect(document.activeElement).toBe(root.querySelector('[name="MobilePhone"]'));
  });

  it('shows an action result as a status, not an alert, and yes or no for a checkbox', async () => {
    const api = fakeApi({
      me: jest.fn(() => Promise.resolve({ ...MENU, firstName: '' })),
      page: jest.fn(() =>
        Promise.resolve({
          ...PROFILE,
          canUpdate: false,
          actions: [{ name: 'thank', label: 'Send Thanks' }],
          fields: [{ field: 'Active__c', label: 'Active', type: 'boolean', edit: false }],
          records: [{ id: '003A', values: { Active__c: true } }]
        })
      )
    });
    await mountPortal(root, { api });
    expect(root.querySelector('p')).toBeNull();
    expect(root.querySelector('dd').textContent).toBe('Yes');

    buttonNamed(root, 'Send Thanks').click();
    await flush();
    expect(root.querySelector('[role="status"]').textContent).toBe('Thanks sent');
    expect(root.querySelector('[role="alert"]')).toBeNull();
  });
});
