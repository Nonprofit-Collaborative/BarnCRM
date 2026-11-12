<?php
/**
 * Plugin Name: BarnCRM Portal
 * Description: Shows a BarnCRM Portal Builder portal on a page, and passes its calls to Salesforce on the server so the OAuth secret and the session token never reach the browser.
 * Version: 0.2.0
 * Requires at least: 6.5
 * Requires PHP: 7.4
 * License: BSD-3-Clause
 *
 * How it works (ADR-0185 portal builder, decision 8):
 * - The shortcode [barncrm_portal key="..."] writes a div that js/boot.js fills. With app="yes"
 *   (and an optional name="...") the page can be added to a phone's home screen as an app.
 * - The browser calls this site's REST route /wp-json/barncrm-portal/v1/<path>.
 * - This plugin gets an access token for the integration user with the OAuth client credentials
 *   flow (cached for 20 minutes), adds it, and forwards the call to
 *   https://<domain>/services/apexrest/barncrm/portal/v1/<path>.
 * - The portal session token from a sign-in is kept in an HttpOnly, Secure, SameSite=Strict
 *   cookie and removed from the answer, so page scripts never see it.
 */

if (!defined('ABSPATH')) {
    exit;
}

const BARNCRM_PORTAL_OPTION = 'barncrm_portal_settings';
const BARNCRM_PORTAL_VERSION = '0.2.0';
const BARNCRM_PORTAL_PATHS = array(
    'login/start' => 'POST',
    'login/verify' => 'POST',
    'login/second-factor' => 'POST',
    'logout' => 'POST',
    'me' => 'GET',
    'page' => 'GET',
    'page/save' => 'POST',
    'page/action' => 'POST',
    'second-factor/enroll' => 'POST',
    'second-factor/confirm' => 'POST',
);
// Sign-in calls allowed per visitor address in ten minutes, before Salesforce's own limits.
const BARNCRM_PORTAL_SIGN_IN_CALLS = 20;

function barncrm_portal_settings() {
    $saved = get_option(BARNCRM_PORTAL_OPTION, array());
    return wp_parse_args(is_array($saved) ? $saved : array(), array(
        'domain' => '',
        'client_id' => '',
        'client_secret' => '',
    ));
}

/* ---------- Settings page (Settings, BarnCRM Portal) ---------- */

add_action('admin_menu', function () {
    add_options_page('BarnCRM Portal', 'BarnCRM Portal', 'manage_options', 'barncrm-portal', 'barncrm_portal_settings_page');
});

add_action('admin_init', function () {
    register_setting('barncrm_portal', BARNCRM_PORTAL_OPTION, array(
        'type' => 'array',
        'sanitize_callback' => 'barncrm_portal_sanitize',
        'show_in_rest' => false,
    ));
});

function barncrm_portal_sanitize($input) {
    $old = barncrm_portal_settings();
    $domain = strtolower(trim((string) ($input['domain'] ?? '')));
    $domain = preg_replace('#^https?://#', '', $domain);
    $domain = rtrim($domain, '/');
    if ($domain !== '' && !preg_match('/^[a-z0-9.-]+\.(salesforce\.com|force\.com)$/', $domain)) {
        add_settings_error(BARNCRM_PORTAL_OPTION, 'domain', 'The Salesforce domain must end in salesforce.com or force.com.');
        $domain = $old['domain'];
    }
    $secret = trim((string) ($input['client_secret'] ?? ''));
    delete_transient('barncrm_portal_token');
    return array(
        'domain' => $domain,
        'client_id' => sanitize_text_field($input['client_id'] ?? ''),
        // A blank box keeps the saved secret, which is never shown again.
        'client_secret' => $secret === '' ? $old['client_secret'] : $secret,
    );
}

function barncrm_portal_settings_page() {
    if (!current_user_can('manage_options')) {
        return;
    }
    $s = barncrm_portal_settings();
    ?>
    <div class="wrap">
        <h1>BarnCRM Portal</h1>
        <p>Connects this website to your BarnCRM portal API. See the BarnCRM Admin Guide, Portal Builder.</p>
        <form method="post" action="options.php">
            <?php settings_fields('barncrm_portal'); ?>
            <table class="form-table" role="presentation">
                <tr>
                    <th scope="row"><label for="barncrm-domain">Salesforce Domain</label></th>
                    <td><input id="barncrm-domain" class="regular-text" name="<?php echo esc_attr(BARNCRM_PORTAL_OPTION); ?>[domain]" value="<?php echo esc_attr($s['domain']); ?>" placeholder="yourorg.my.salesforce.com"></td>
                </tr>
                <tr>
                    <th scope="row"><label for="barncrm-key">Consumer Key</label></th>
                    <td><input id="barncrm-key" class="regular-text" name="<?php echo esc_attr(BARNCRM_PORTAL_OPTION); ?>[client_id]" value="<?php echo esc_attr($s['client_id']); ?>"></td>
                </tr>
                <tr>
                    <th scope="row"><label for="barncrm-secret">Consumer Secret</label></th>
                    <td><input id="barncrm-secret" class="regular-text" type="password" autocomplete="new-password" name="<?php echo esc_attr(BARNCRM_PORTAL_OPTION); ?>[client_secret]" value="">
                        <p class="description"><?php echo $s['client_secret'] === '' ? 'Not saved yet.' : 'Saved. Leave blank to keep it.'; ?></p></td>
                </tr>
            </table>
            <?php submit_button(); ?>
        </form>
    </div>
    <?php
}

/* ---------- Shortcode ---------- */

add_shortcode('barncrm_portal', function ($atts) {
    $atts = shortcode_atts(array('key' => '', 'app' => 'no', 'name' => ''), $atts, 'barncrm_portal');
    $key = preg_replace('/[^A-Za-z0-9_-]/', '', (string) $atts['key']);
    if ($key === '') {
        return '';
    }
    wp_enqueue_script_module('barncrm-portal', plugins_url('js/boot.js', __FILE__), array(), BARNCRM_PORTAL_VERSION);
    wp_enqueue_style('barncrm-portal', plugins_url('css/portal.css', __FILE__), array(), BARNCRM_PORTAL_VERSION);
    $app = '';
    if ($atts['app'] === 'yes') {
        // An installable web app (ADR-0215 events attendee app, decision 3): a manifest for this
        // page and a service worker at the site root that caches only this plugin's own files.
        $manifest = add_query_arg(array(
            'barncrm_portal_manifest' => $key,
            'name' => barncrm_portal_app_name($atts['name']),
            'start' => get_permalink() ?: home_url('/'),
        ), home_url('/'));
        $app = sprintf(
            ' data-barncrm-manifest="%s" data-barncrm-worker="%s" data-barncrm-scope="%s" data-barncrm-icon="%s" data-barncrm-name="%s"',
            esc_url($manifest),
            esc_url(add_query_arg('barncrm_portal_sw', '1', home_url('/'))),
            esc_attr(barncrm_portal_scope()),
            esc_url(barncrm_portal_icon(180)),
            esc_attr(barncrm_portal_app_name($atts['name']))
        );
    }
    return sprintf(
        '<div class="barncrm-portal" data-barncrm-portal="%s" data-barncrm-endpoint="%s" data-barncrm-nonce="%s"%s></div>',
        esc_attr($key),
        esc_url(rest_url('barncrm-portal/v1')),
        esc_attr(wp_create_nonce('barncrm_portal')),
        $app
    );
});

/* ---------- Installable app: manifest and service worker ---------- */

function barncrm_portal_app_name($name) {
    $name = trim(sanitize_text_field((string) $name));
    return $name === '' ? get_bloginfo('name') : mb_substr($name, 0, 45);
}

/** The site icon at this size, else the plugin's own. */
function barncrm_portal_icon($size) {
    $site = get_site_icon_url($size);
    return $site ? $site : plugins_url('img/icon.svg', __FILE__);
}

/** The files the service worker keeps for offline start-up: this plugin's scripts and style. */
function barncrm_portal_app_files() {
    $files = array();
    foreach (array('js/boot.js', 'js/portalApi.js', 'js/portalApp.js', 'js/messages.js', 'js/pageFiles.js', 'css/portal.css') as $file) {
        $files[] = plugins_url($file, __FILE__);
    }
    return $files;
}

add_action('init', function () {
    if (isset($_GET['barncrm_portal_manifest'])) {
        barncrm_portal_manifest();
    } elseif (isset($_GET['barncrm_portal_sw'])) {
        barncrm_portal_worker();
    }
});

function barncrm_portal_manifest() {
    $name = barncrm_portal_app_name(wp_unslash($_GET['name'] ?? ''));
    // The app opens on the page that showed the portal, never on another site.
    $start = wp_validate_redirect(esc_url_raw(wp_unslash($_GET['start'] ?? '')), home_url('/'));
    $site_icon = get_site_icon_url(512);
    $icons = $site_icon
        ? array(
            array('src' => get_site_icon_url(192), 'sizes' => '192x192'),
            array('src' => $site_icon, 'sizes' => '512x512'),
        )
        : array(array('src' => plugins_url('img/icon.svg', __FILE__), 'sizes' => 'any', 'type' => 'image/svg+xml'));
    nocache_headers();
    header('Content-Type: application/manifest+json; charset=utf-8');
    echo wp_json_encode(array(
        'name' => $name,
        'short_name' => mb_substr($name, 0, 12),
        'start_url' => $start,
        'scope' => home_url('/'),
        'display' => 'standalone',
        'background_color' => '#ffffff',
        'theme_color' => '#ffffff',
        'icons' => $icons,
    ));
    exit;
}

/** The path the service worker controls: the site's own address, so a site in a subfolder stays inside it. */
function barncrm_portal_scope() {
    $path = wp_parse_url(home_url('/'), PHP_URL_PATH);
    return $path ? $path : '/';
}

function barncrm_portal_worker() {
    header('Content-Type: text/javascript; charset=utf-8');
    header('Service-Worker-Allowed: ' . barncrm_portal_scope());
    header('Cache-Control: no-cache');
    $files = wp_json_encode(barncrm_portal_app_files());
    $cache = wp_json_encode('barncrm-portal-' . BARNCRM_PORTAL_VERSION);
    $offline = wp_json_encode('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Offline</title><p style="font-family:sans-serif;padding:16px">You are offline. Connect to the internet and open the app again.</p>');
    // Only this plugin's files are cached. A portal call or a page's data is never stored, so
    // nothing about a person stays on the phone beyond the HttpOnly session cookie.
    echo <<<JS
const CACHE = {$cache};
const FILES = {$files};
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('barncrm-portal-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') {
    return;
  }
  if (FILES.includes(request.url.split('?')[0])) {
    event.respondWith(caches.match(request.url.split('?')[0]).then((hit) => hit || fetch(request)));
  } else if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => new Response({$offline}, { headers: { 'Content-Type': 'text/html; charset=utf-8' } }))
    );
  }
});
JS;
    exit;
}

/* ---------- The proxy ---------- */

add_action('rest_api_init', function () {
    register_rest_route('barncrm-portal/v1', '/(?P<path>[a-z/-]+)', array(
        'methods' => array('GET', 'POST'),
        'callback' => 'barncrm_portal_proxy',
        // Visitors are not WordPress users; the nonce, the cookie and Salesforce decide.
        'permission_callback' => '__return_true',
    ));
});

function barncrm_portal_cookie_name($portal) {
    return 'barncrm_portal_' . preg_replace('/[^A-Za-z0-9_]/', '_', $portal);
}

function barncrm_portal_refuse($error, $status) {
    $response = new WP_REST_Response(array('ok' => false, 'error' => $error), $status);
    $response->header('Cache-Control', 'no-store');
    return $response;
}

function barncrm_portal_access_token($fresh) {
    $cached = get_transient('barncrm_portal_token');
    if (!$fresh && is_string($cached) && $cached !== '') {
        return $cached;
    }
    $s = barncrm_portal_settings();
    if ($s['domain'] === '' || $s['client_id'] === '' || $s['client_secret'] === '') {
        return null;
    }
    $answer = wp_remote_post('https://' . $s['domain'] . '/services/oauth2/token', array(
        'timeout' => 15,
        'body' => array(
            'grant_type' => 'client_credentials',
            'client_id' => $s['client_id'],
            'client_secret' => $s['client_secret'],
        ),
    ));
    if (is_wp_error($answer) || wp_remote_retrieve_response_code($answer) !== 200) {
        return null;
    }
    $body = json_decode(wp_remote_retrieve_body($answer), true);
    $token = is_array($body) ? ($body['access_token'] ?? '') : '';
    if ($token === '') {
        return null;
    }
    set_transient('barncrm_portal_token', $token, 20 * MINUTE_IN_SECONDS);
    return $token;
}

function barncrm_portal_too_many($path) {
    if (strpos($path, 'login/') !== 0) {
        return false;
    }
    $ip = isset($_SERVER['REMOTE_ADDR']) ? (string) $_SERVER['REMOTE_ADDR'] : 'unknown';
    $bucket = 'barncrm_portal_rate_' . md5($ip);
    $count = (int) get_transient($bucket);
    if ($count >= BARNCRM_PORTAL_SIGN_IN_CALLS) {
        return true;
    }
    set_transient($bucket, $count + 1, 10 * MINUTE_IN_SECONDS);
    return false;
}

function barncrm_portal_proxy(WP_REST_Request $request) {
    $path = (string) $request['path'];
    $method = $request->get_method();
    if (!isset(BARNCRM_PORTAL_PATHS[$path]) || BARNCRM_PORTAL_PATHS[$path] !== $method) {
        return barncrm_portal_refuse('not_found', 404);
    }
    if (!wp_verify_nonce((string) $request->get_header('x_barncrm_nonce'), 'barncrm_portal')) {
        return barncrm_portal_refuse('not_signed_in', 401);
    }
    $portal = preg_replace('/[^A-Za-z0-9_-]/', '', (string) $request->get_header('x_barncrm_portal'));
    if ($portal === '') {
        return barncrm_portal_refuse('invalid_request', 400);
    }
    if (barncrm_portal_too_many($path)) {
        return barncrm_portal_refuse('locked', 429);
    }

    $cookie = barncrm_portal_cookie_name($portal);
    $session = isset($_COOKIE[$cookie]) ? preg_replace('/[^A-Za-z0-9_-]/', '', (string) $_COOKIE[$cookie]) : '';
    $url = 'https://' . barncrm_portal_settings()['domain'] . '/services/apexrest/barncrm/portal/v1/' . $path;
    if ($path === 'page') {
        $url = add_query_arg('key', rawurlencode((string) $request->get_param('key')), $url);
    }
    $body = $method === 'POST' ? $request->get_json_params() : null;
    if ($path === 'login/start' && is_array($body)) {
        $body['portal'] = $portal; // A visitor signs in only to the portal this page shows.
    }

    $answer = null;
    foreach (array(false, true) as $fresh) {
        $token = barncrm_portal_access_token($fresh);
        if ($token === null) {
            return barncrm_portal_refuse('portal_unavailable', 503);
        }
        $headers = array('Authorization' => 'Bearer ' . $token, 'Content-Type' => 'application/json');
        if ($session !== '') {
            $headers['X-Barn-Portal-Session'] = $session;
        }
        $answer = wp_remote_request($url, array(
            'method' => $method,
            'timeout' => 20,
            'headers' => $headers,
            'body' => $body === null ? null : wp_json_encode($body ?: new stdClass()),
        ));
        // A 401 here is Salesforce refusing the access token, not the portal: try once more.
        if (is_wp_error($answer) || wp_remote_retrieve_response_code($answer) !== 401
            || strpos(wp_remote_retrieve_body($answer), 'INVALID_SESSION_ID') === false) {
            break;
        }
    }
    if (is_wp_error($answer)) {
        return barncrm_portal_refuse('network_error', 502);
    }
    $status = (int) wp_remote_retrieve_response_code($answer);
    $data = json_decode(wp_remote_retrieve_body($answer), true);
    if (!is_array($data) || !array_key_exists('ok', $data)) {
        return barncrm_portal_refuse('server_error', 502);
    }

    if (isset($data['session']) && is_string($data['session'])) {
        $expires = isset($data['expires']) ? strtotime($data['expires']) : 0;
        barncrm_portal_set_cookie($cookie, $data['session'], $expires ?: time() + 8 * HOUR_IN_SECONDS);
        unset($data['session']);
    }
    if ($path === 'logout' || ($data['error'] ?? '') === 'not_signed_in') {
        barncrm_portal_set_cookie($cookie, '', time() - HOUR_IN_SECONDS);
    }
    $response = new WP_REST_Response($data, $status);
    $response->header('Cache-Control', 'no-store');
    return $response;
}

function barncrm_portal_set_cookie($name, $value, $expires) {
    setcookie($name, $value, array(
        'expires' => $expires,
        'path' => '/',
        'secure' => true,
        'httponly' => true,
        'samesite' => 'Strict',
    ));
}
