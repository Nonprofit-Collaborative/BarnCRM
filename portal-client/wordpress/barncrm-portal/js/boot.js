/**
 * Starts every BarnCRM portal on the page. The plugin's shortcode writes a
 * `<div data-barncrm-portal="key">` with the proxy address and nonce; portalApi.js and
 * portalApp.js are copied here from `portal-client/src` by `portal-client/build-wordpress.sh`.
 */
import { createPortalApi } from './portalApi.js';
import { mountPortal } from './portalApp.js';

document.querySelectorAll('[data-barncrm-portal]').forEach((root) => {
  const api = createPortalApi({
    baseUrl: root.dataset.barncrmEndpoint,
    portal: root.dataset.barncrmPortal,
    nonce: root.dataset.barncrmNonce
  });
  mountPortal(root, { api });
});
