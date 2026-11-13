# BarnCRM Portal Client

The website half of BarnCRM Portal Builder (ADR-0185 portal builder, D-187). It is not deployed to Salesforce. Setup, from the Salesforce side: [Admin Guide, Portal Builder](../docs/admin-guide/portal-builder.md).

| Path | What it is |
|---|---|
| `src/portalApi.js` | Calls the portal API through the website's proxy. Never holds the OAuth secret or the session token. |
| `src/portalApp.js` | The sign-in screens (email, emailed code, authenticator) and the template's pages with edit forms. Framework-free; text only through `textContent`. A `url` field whose value starts with `https://` (a signed form link) shows as a link named for the field. A page with `calendar` offers Add to Calendar, one with `download` Download CSV, and a field with `scan` a Scan button where the browser reads QR codes from the camera (`BarcodeDetector`). |
| `src/pageFiles.js` | Builds the Add to Calendar (`.ics`) and Download CSV files in the browser from the records shown; nothing is sent anywhere. |
| `src/messages.js` | The words shown, English; pass a copy to `mountPortal` to change them. |
| `src/portalTemplate.js` | `checkTemplate(json)`: the template shape rules Salesforce applies, to check a template before pasting it into a Portal. Salesforce also checks objects and fields against the org. |
| `templates/sample.json` | A starting template: My Details (the person) and My Roles (their current affiliations). |
| `templates/volunteer.json`, `speaker.json`, `donor.json`, `board.json`, `applicant.json` | The ready-made templates (PB-03, PB-07, PB-08, PB-02, PB-06). Each names its module in `requiresModules` (Volunteers, Event Management, Giving, Corporate Hub, Scholarships); module actions go through Core's `PortalActionExtension`. Checked against the package metadata by `__tests__/portalTemplates.test.js`. |
| `templates/attendee.json`, `sponsor.json`, `service.json`, `partner.json`, `partner-funders.json` | The event attendee app (EV-22, EV-29) and sponsor lead scanning (EV-28), both Event Management; the service portal (PB-04, Programs) and the partner portal (PB-05, Programs, and Programs with Funders). Their shared lists are `personScope` catalogs, so a person sees only the records of their own events, cohorts or partner organizations. |
| `templates/requests.json` | Requests and issues (D-201, Projects): My Requests (send, reply, satisfaction) and Updates (the shared comments on their requests). Needs Take requests from outside on. |
| `wordpress/barncrm-portal/` | The WordPress plugin: settings page, the `[barncrm_portal key="..."]` shortcode, the proxy, and for `app="yes"` the web app manifest and service worker (`img/icon.svg` is the icon when the site has none). `css/portal.css` lays the portal out (one field per line, phone-width inputs, marked alerts) in the theme's own fonts and colors. |
| `build-wordpress.sh` | Builds `barncrm-portal.zip` with the client inside, for Plugins, Add New, Upload Plugin. |
| `__tests__/` | Jest tests, run with the repository's `npm run test:unit`. |

## WordPress

1. Run `bash portal-client/build-wordpress.sh` and upload `barncrm-portal.zip` in Plugins, Add New, Upload Plugin. Activate **BarnCRM Portal**.
2. In Settings, BarnCRM Portal, enter the Salesforce domain (`yourorg.my.salesforce.com`), the Consumer Key and the Consumer Secret of the External Client App. The secret is kept in the WordPress database and never shown again or sent to visitors.
3. Put `[barncrm_portal key="<portal key>"]` on a page. The site must use HTTPS.
4. Exclude that page from any full-page cache: the shortcode writes a nonce that must not be shared from a stale copy for more than a day.
5. To let people add the portal to their phone's home screen as an app, write `[barncrm_portal key="<portal key>" app="yes" name="<app name>"]`. The plugin then serves a manifest (`?barncrm_portal_manifest=`) that opens on that page, using the site icon (Appearance, Customize, Site Identity) or a bundled one, and a service worker at the site root (`?barncrm_portal_sw=1`) that keeps only the plugin's own scripts and style and shows an offline notice. It never stores a portal call or a page's data. No app store and no push service are involved.

## Any Other Website

The browser part needs a small server piece, the proxy, that does what the plugin's `barncrm_portal_proxy` does:

- Accept only the API paths in `BARNCRM_PORTAL_PATHS`, from your own pages (a nonce or CSRF token, and a SameSite=Strict cookie).
- Get an access token with the OAuth client credentials flow (`POST https://<domain>/services/oauth2/token`, `grant_type=client_credentials`), cache it, and add it as `Authorization: Bearer`. Keep the secret on the server.
- Forward to `https://<domain>/services/apexrest/barncrm/portal/v1/<path>`. On `login/start`, set `portal` to the page's portal key.
- When an answer carries `session`, store it in an HttpOnly, Secure, SameSite=Strict cookie and remove it from the answer. Send it back as the `X-Barn-Portal-Session` header on later calls. Clear the cookie on `logout` or `not_signed_in`.
- Limit sign-in calls per visitor address.

Then load the client as ES modules, with the plugin's `css/portal.css` (or your own styles for the `barncrm-portal` and `barn-portal-*` classes):

```html
<link rel="stylesheet" href="./portal.css" />
<div id="portal" class="barncrm-portal"></div>
<script type="module">
  import { createPortalApi } from './portalApi.js';
  import { mountPortal } from './portalApp.js';
  const api = createPortalApi({ baseUrl: '/portal-proxy', portal: 'volunteers', nonce: '<from your server>' });
  mountPortal(document.getElementById('portal'), { api });
</script>
```

## The API

Paths under `/services/apexrest/barncrm/portal/v1/`; every answer is JSON with `ok`, and `error` when refused.

| Call | Body or query | Answer |
|---|---|---|
| `POST login/start` | `portal`, `email` | `challenge` (the same answer whether or not the email is on file) |
| `POST login/verify` | `challenge`, `code` | `status`: `signedIn` (with `session`, `expires`), `secondFactor`, or `enroll` (with `secret`, `uri`) |
| `POST login/second-factor` | `challenge`, `code` | `status` `signedIn`, `session`, `expires` |
| `GET me` | | `title`, `firstName`, `secondFactor`, `pages`, `brand` (null, or `name`, `primaryColor`, `secondaryColor`, `phone`, `website`, `address` lines, while brands are on) |
| `GET page` | `key` | `fields`, `records` (`id`, `values`), `canUpdate`, `canCreate`, `actions` |
| `POST page/save` | `page`, `recordId` (blank to add), `values` | `id` |
| `POST page/action` | `page`, `recordId`, `action` | `message` |
| `POST second-factor/enroll`, `second-factor/confirm` | `code` for confirm | `secret`, `uri`; then nothing |
| `POST logout` | | nothing |

Errors and their HTTP status: `not_signed_in` 401, `not_allowed` and `locked` 403, `not_found` 404, `portal_unavailable` 503, `server_error` 500, anything else (`code_invalid`, `code_expired`, `required_missing`, `invalid_value`, `save_failed`, `action_failed`, `invalid_request`) 400.
