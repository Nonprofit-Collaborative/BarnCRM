<?php
/**
 * Plugin Name: BarnCRM Portal
 * Description: Shows a BarnCRM Portal Builder portal on a page, and passes its calls to Salesforce on the server so the OAuth secret and the session token never reach the browser.
 * Version: 0.1.0
 * Requires at least: 6.5
 * Requires PHP: 7.4
 * License: BSD-3-Clause
 *
 * How it works (ADR-0185 portal builder, decision 8):
 * - The shortcode [barncrm_portal key="..."] writes a div that js/boot.js fills.
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
    $atts = shortcode_atts(array('key' => ''), $atts, 'barncrm_portal');
    $key = preg_replace('/[^A-Za-z0-9_-]/', '', (string) $atts['key']);
    if ($key === '') {
        return '';
    }
    wp_enqueue_script_module('barncrm-portal', plugins_url('js/boot.js', __FILE__), array(), '0.1.0');
    return sprintf(
        '<div class="barncrm-portal" data-barncrm-portal="%s" data-barncrm-endpoint="%s" data-barncrm-nonce="%s"></div>',
        esc_attr($key),
        esc_url(rest_url('barncrm-portal/v1')),
        esc_attr(wp_create_nonce('barncrm_portal'))
    );
});

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
