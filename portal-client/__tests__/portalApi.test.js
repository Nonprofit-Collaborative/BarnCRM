import { createPortalApi, PortalError } from '../src/portalApi.js';

function answering(status, body) {
  return jest.fn(() =>
    Promise.resolve({
      ok: status >= 200 && status < 300,
      status,
      json: () =>
        body === undefined ? Promise.reject(new Error('no body')) : Promise.resolve(body)
    })
  );
}

describe('createPortalApi', () => {
  it('posts to the proxy with the portal key and nonce, never a token', async () => {
    const fetch = answering(200, { ok: true, challenge: 'abc' });
    const api = createPortalApi({
      baseUrl: '/wp-json/barncrm-portal/v1/',
      portal: 'sample',
      nonce: 'n1',
      fetch
    });

    const answer = await api.start('pat@example.org');

    expect(answer.challenge).toBe('abc');
    const [url, init] = fetch.mock.calls[0];
    expect(url).toBe('/wp-json/barncrm-portal/v1/login/start');
    expect(init.method).toBe('POST');
    expect(init.credentials).toBe('same-origin');
    expect(init.headers['X-BarnCRM-Portal']).toBe('sample');
    expect(init.headers['X-BarnCRM-Nonce']).toBe('n1');
    expect(JSON.parse(init.body)).toEqual({ portal: 'sample', email: 'pat@example.org' });
    expect(JSON.stringify(init.headers)).not.toMatch(/Authorization|Session/i);
  });

  it('reads a page by key with GET and no body', async () => {
    const fetch = answering(200, { ok: true, records: [] });
    const api = createPortalApi({ baseUrl: '/p', portal: 'sample', fetch });

    await api.page('my roles');

    const [url, init] = fetch.mock.calls[0];
    expect(url).toBe('/p/page?key=my%20roles');
    expect(init.method).toBe('GET');
    expect(init.body).toBeUndefined();
  });

  it('turns a refusal into a PortalError with its code', async () => {
    const api = createPortalApi({
      baseUrl: '/p',
      portal: 'sample',
      fetch: answering(403, { ok: false, error: 'not_allowed' })
    });

    await expect(api.save('profile', '003', { FirstName: 'M' })).rejects.toEqual(
      expect.objectContaining({ code: 'not_allowed', status: 403 })
    );
  });

  it('reports an answer that is not JSON, and no network, by code', async () => {
    const broken = createPortalApi({ baseUrl: '/p', portal: 's', fetch: answering(502) });
    const offline = createPortalApi({
      baseUrl: '/p',
      portal: 's',
      fetch: jest.fn(() => Promise.reject(new Error('down')))
    });

    await expect(broken.me()).rejects.toBeInstanceOf(PortalError);
    await expect(broken.me()).rejects.toEqual(expect.objectContaining({ code: 'server_error' }));
    await expect(offline.me()).rejects.toEqual(expect.objectContaining({ code: 'network_error' }));
  });
});
