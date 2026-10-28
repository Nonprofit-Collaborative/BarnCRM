import { createElement } from 'lwc';
import IntegrationsPanel from 'c/integrationsPanel';
import getApps from '@salesforce/apex/IntegrationController.getApps';

jest.mock('@salesforce/apex/IntegrationController.getApps', () => ({ default: jest.fn() }), {
  virtual: true
});

function app(key, category, installed, extra = {}) {
  return {
    key,
    name: `Product ${key}`,
    category,
    description: `What ${key} does`,
    maintainer: 'A maintainer',
    licenseCost: 'Free',
    linkUrl: `https://example.invalid/${key}`,
    compatibility: `Note for ${key}`,
    installed,
    ...extra
  };
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-integrations-panel', { is: IntegrationsPanel });
  document.body.appendChild(element);
  await settle();
  return element;
}

function group(element, category) {
  return element.shadowRoot.querySelector(`section[data-group="${category}"]`);
}

function row(element, key) {
  return element.shadowRoot.querySelector(`li[data-app="${key}"]`);
}

describe('c-integrations-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('groups products by category, in the order the page shows them', async () => {
    getApps.mockResolvedValue([
      app('alt', 'Alternative', true),
      app('dev', 'InDevelopment', false),
      app('comp', 'Complement', false)
    ]);
    const element = await build();

    const headings = [...element.shadowRoot.querySelectorAll('[data-id="group-heading"]')].map(
      (heading) => heading.textContent
    );
    expect(headings).toEqual([
      'c.Core_Integrations_GroupComplement',
      'c.Core_Integrations_GroupInDevelopment',
      'c.Core_Integrations_GroupAlternative'
    ]);
    expect(group(element, 'Complement').querySelector('li[data-app="comp"]')).not.toBeNull();
    expect(group(element, 'InDevelopment').querySelector('li[data-app="dev"]')).not.toBeNull();
    expect(group(element, 'Alternative').querySelector('li[data-app="alt"]')).not.toBeNull();
  });

  it('draws no heading for a group with no product, so the alternatives are hidden when none is installed', async () => {
    getApps.mockResolvedValue([app('comp', 'Complement', false)]);
    const element = await build();

    expect(group(element, 'Complement')).not.toBeNull();
    expect(group(element, 'InDevelopment')).toBeNull();
    expect(group(element, 'Alternative')).toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="group-heading"]').length).toBe(1);
  });

  it('lists a product with an unknown category under the first group', async () => {
    getApps.mockResolvedValue([app('odd', 'Something else', false)]);
    const element = await build();

    expect(group(element, 'Complement').querySelector('li[data-app="odd"]')).not.toBeNull();
  });

  it('shows an Installed or Not installed badge from the check', async () => {
    getApps.mockResolvedValue([app('here', 'Complement', true), app('gone', 'Complement', false)]);
    const element = await build();

    const here = row(element, 'here').querySelector('[data-id="badge"]');
    const gone = row(element, 'gone').querySelector('[data-id="badge"]');
    expect(here.textContent).toBe('c.Core_Integrations_Installed');
    expect(here.className).toContain('slds-theme_success');
    expect(gone.textContent).toBe('c.Core_Integrations_NotInstalled');
    expect(gone.className).not.toContain('slds-theme_success');
  });

  it('shows the name, description, maintainer, cost and compatibility note', async () => {
    getApps.mockResolvedValue([app('one', 'Complement', false, { relatedModule: 'BarnCRM X' })]);
    const element = await build();

    const item = row(element, 'one');
    expect(item.querySelector('[data-id="name"]').textContent).toBe('Product one');
    expect(item.querySelector('[data-id="description"]').textContent).toBe('What one does');
    expect(item.querySelector('[data-id="maintainer"]')).not.toBeNull();
    expect(item.querySelector('[data-id="license-cost"]')).not.toBeNull();
    expect(item.querySelector('[data-id="related-module"]')).not.toBeNull();
    expect(item.querySelector('[data-id="compatibility"]').textContent).toContain('Note for one');
  });

  it('opens each link in a new tab and says so to a screen reader', async () => {
    getApps.mockResolvedValue([app('one', 'Complement', false)]);
    const element = await build();

    const item = row(element, 'one');
    const learn = item.querySelector('[data-id="learn-more"]');
    expect(learn.getAttribute('href')).toBe('https://example.invalid/one');
    expect(learn.target).toBe('_blank');
    expect(learn.rel).toContain('noopener');
    expect(learn.querySelector('.slds-assistive-text').textContent).toContain(
      'Core_SuiteChoice_NewTab'
    );
    expect(learn.querySelector('.slds-assistive-text').textContent).toContain('Product one');
    expect(item.querySelector('[data-id="install"]')).toBeNull();
  });

  it('shows no migration line when the row has none', async () => {
    getApps.mockResolvedValue([app('one', 'Complement', false)]);
    const element = await build();

    const item = row(element, 'one');
    expect(item.querySelector('[data-id="migration-path"]')).toBeNull();
  });

  it('shows a migration line once a row carries one', async () => {
    getApps.mockResolvedValue([
      app('one', 'Alternative', true, { migrationPath: 'See the guide' })
    ]);
    const element = await build();

    expect(row(element, 'one').querySelector('[data-id="migration-path"]')).not.toBeNull();
  });

  it('shows In Progress on every product unless its status says Available', async () => {
    getApps.mockResolvedValue([
      app('plan', 'Complement', false, { status: 'InProgress' }),
      app('done', 'Complement', false, { status: 'Available' })
    ]);
    const element = await build();

    expect(row(element, 'plan').querySelector('[data-id="status"]').textContent).toBe(
      'c.Core_Integrations_StatusInProgress'
    );
    expect(row(element, 'done').querySelector('[data-id="status"]').textContent).toBe(
      'c.Core_Integrations_StatusAvailable'
    );
  });

  it('ends with a request section whose two forms open in a new tab', async () => {
    getApps.mockResolvedValue([app('one', 'Complement', false)]);
    const element = await build();

    const request = element.shadowRoot.querySelector('[data-id="request"]');
    expect(request.querySelector('[data-id="request-heading"]').textContent).toBe(
      'c.Core_Integrations_RequestHeading'
    );
    for (const id of ['request-link', 'partner-link', 'guide-link']) {
      const link = request.querySelector(`[data-id="${id}"]`);
      expect(link.target).toBe('_blank');
      expect(link.rel).toContain('noopener');
      expect(link.querySelector('.slds-assistive-text').textContent).toContain(
        'Core_SuiteChoice_NewTab'
      );
    }
    expect(request.querySelector('[data-id="request-link"]').getAttribute('href')).toBe(
      'c.Core_Integrations_RequestUrl'
    );
    expect(request.querySelector('[data-id="partner-link"]').getAttribute('href')).toBe(
      'c.Core_Integrations_PartnerUrl'
    );
  });

  it('says so when the catalog holds nothing', async () => {
    getApps.mockResolvedValue([]);
    const element = await build();

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('section[data-group]').length).toBe(0);
  });

  it('shows the message when the list cannot be read', async () => {
    getApps.mockRejectedValue({ body: { message: 'Could not read' } });
    const element = await build();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'Could not read'
    );
  });

  it('reads the org again on Check again', async () => {
    getApps.mockResolvedValue([app('one', 'Complement', false)]);
    const element = await build();
    getApps.mockResolvedValue([app('one', 'Complement', true)]);

    element.shadowRoot.querySelector('[data-id="check-again"]').click();
    await settle();

    expect(getApps).toHaveBeenCalledTimes(2);
    expect(row(element, 'one').querySelector('[data-id="badge"]').textContent).toBe(
      'c.Core_Integrations_Installed'
    );
  });
});
