import {
  BLANK_ROWS,
  LAYOUTS,
  badgePageHtml,
  escapeHtml,
  layoutFor,
  selectAttendees,
  signInPageHtml,
  ticketNames
} from 'c/eventBadgesModel';

const PEOPLE = [
  { id: '1', name: 'Ann Lee', organization: 'Acme', ticketName: 'VIP' },
  { id: '2', name: 'Bo Kim', organization: 'Birch', ticketName: 'General' },
  { id: '3', name: 'Cy <b>Roe</b>', ticketName: 'General' }
];

describe('eventBadgesModel', () => {
  it('knows three layouts and falls back to the standard one', () => {
    expect(LAYOUTS.map((layout) => layout.value)).toEqual(['large', 'standard', 'compact']);
    expect(layoutFor('large').height).toBe(3);
    expect(layoutFor('nope').value).toBe('standard');
  });

  it('escapes text for HTML', () => {
    expect(escapeHtml(`<a href="x">'&`)).toBe('&lt;a href=&quot;x&quot;&gt;&#39;&amp;');
    expect(escapeHtml(undefined)).toBe('');
  });

  it('narrows by search and ticket', () => {
    expect(selectAttendees(PEOPLE, 'acme', '')).toHaveLength(1);
    expect(selectAttendees(PEOPLE, '', 'General')).toHaveLength(2);
    expect(selectAttendees(PEOPLE, 'bo', 'VIP')).toHaveLength(0);
    expect(selectAttendees(undefined, '', '')).toEqual([]);
    expect(ticketNames(PEOPLE)).toEqual(['General', 'VIP']);
  });

  it('builds badges with only the parts switched on, escaped', () => {
    const html = badgePageHtml(
      'Gala <Badges>',
      'large',
      [
        {
          name: 'Cy <b>Roe</b>',
          organization: 'Acme',
          ticketName: 'VIP',
          qr: 'data:image/png;base64,AA'
        }
      ],
      { organization: true, ticket: false, qr: true }
    );
    expect(html).toContain('width: 4in');
    expect(html).toContain('Cy &lt;b&gt;Roe&lt;/b&gt;');
    expect(html).toContain('class="org"');
    expect(html).not.toContain('class="ticket"');
    expect(html).toContain('<img class="qr" src="data:image/png;base64,AA"');
    expect(html).not.toContain('<b>Roe</b>');
    expect(html).toContain('Gala &lt;Badges&gt;');
    expect(html).toContain('@page');
  });

  it('builds a sign-in sheet with blank rows', () => {
    const html = signInPageHtml(
      'Spring Gala',
      'Nov 7',
      PEOPLE,
      { name: 'Name', organization: 'Organization', ticket: 'Ticket', signature: 'Signature' },
      BLANK_ROWS
    );
    expect((html.match(/class="blank"/g) || []).length).toBe(BLANK_ROWS);
    expect(html).toContain('<th class="sign">Signature</th>');
    expect(html).toContain('Ann Lee');
    expect(html).not.toContain('<b>Roe</b>');
  });
});
