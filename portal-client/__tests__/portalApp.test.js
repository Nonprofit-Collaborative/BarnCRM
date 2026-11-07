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

  it('signs out back to the email screen', async () => {
    const api = fakeApi();
    await mountPortal(root, { api });

    buttonNamed(root, 'Sign Out').click();
    await flush();

    expect(api.logout).toHaveBeenCalled();
    expect(root.querySelector('h2').textContent).toBe('Sign In');
  });
});
