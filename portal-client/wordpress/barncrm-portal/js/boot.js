/**
 * Starts every BarnCRM portal on the page. The plugin's shortcode writes a
 * `<div data-barncrm-portal="key">` with the proxy address and nonce; portalApi.js and
 * portalApp.js are copied here from `portal-client/src` by `portal-client/build-wordpress.sh`.
 */
import { createPortalApi } from './portalApi.js';
import { mountPortal } from './portalApp.js';

/** Adds a tag to the page head once. */
function addToHead(tag, attrs) {
  const node = document.createElement(tag);
  Object.entries(attrs).forEach(([name, value]) => node.setAttribute(name, value));
  document.head.appendChild(node);
}

/**
 * A portal shown with app="yes" can be added to the home screen: its manifest, the Apple home
 * screen tags, and a service worker that caches only the plugin's own files.
 */
function installable(root) {
  const data = root.dataset;
  if (!data.barncrmManifest || document.querySelector('link[rel="manifest"]')) {
    return;
  }
  addToHead('link', { rel: 'manifest', href: data.barncrmManifest });
  addToHead('link', { rel: 'apple-touch-icon', href: data.barncrmIcon });
  addToHead('meta', { name: 'apple-mobile-web-app-capable', content: 'yes' });
  addToHead('meta', { name: 'mobile-web-app-capable', content: 'yes' });
  addToHead('meta', { name: 'apple-mobile-web-app-title', content: data.barncrmName });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register(data.barncrmWorker, { scope: '/' }).catch(() => undefined);
  }
}

document.querySelectorAll('[data-barncrm-portal]').forEach((root) => {
  installable(root);
  const api = createPortalApi({
    baseUrl: root.dataset.barncrmEndpoint,
    portal: root.dataset.barncrmPortal,
    nonce: root.dataset.barncrmNonce
  });
  mountPortal(root, { api });
});
