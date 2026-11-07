/**
 * The portal API the off-platform client calls as the integration user (ADR-NEXT
 * `NEXT-portal-builder-off-platform-portal-api.md`, decision 8):
 * `/services/apexrest/barncrm/portal/v1/<route>`. Thin: it reads JSON, calls `PortalAuth` and
 * `PortalData`, and writes plain JSON, `{ "ok": true, ... }` or `{ "ok": false, "error": code }`.
 *
 * Routes: POST `login/start`, `login/verify`, `login/second-factor`, `logout`,
 * `second-factor/enroll`, `second-factor/confirm`, `page/save`, `page/action`; GET `me`,
 * `page?key=`. Every route but the three sign-in ones needs the session token in the
 * `X-Barn-Portal-Session` header.
 */
@RestResource(urlMapping='/barncrm/portal/v1/*')
global with sharing class PortalApi {
	public static final String SESSION_HEADER = 'X-Barn-Portal-Session';
	private static final Map<String, Integer> STATUS_BY_ERROR = new Map<String, Integer>{
		'not_signed_in' => 401,
		'not_allowed' => 403,
		'locked' => 403,
		'not_found' => 404,
		'portal_unavailable' => 503
	};

	@HttpGet
	global static void doGet() {
		respond('GET');
	}

	@HttpPost
	global static void doPost() {
		respond('POST');
	}

	private static void respond(String method) {
		RestRequest request = RestContext.request;
		RestResponse response = RestContext.response;
		response.addHeader('Content-Type', 'application/json');
		response.addHeader('Cache-Control', 'no-store');
		Map<String, Object> result;
		try {
			result = route(method, routeOf(request.requestURI), request, bodyOf(request));
			result.put('ok', true);
			response.statusCode = 200;
		} catch (PortalAuth.RefusalException refusal) {
			result = new Map<String, Object>{ 'ok' => false, 'error' => refusal.getMessage() };
			response.statusCode = STATUS_BY_ERROR.containsKey(refusal.getMessage())
				? STATUS_BY_ERROR.get(refusal.getMessage())
				: 400;
		} catch (Exception failed) {
			ErrorLogger.log(failed, 'PortalApi.respond');
			result = new Map<String, Object>{ 'ok' => false, 'error' => 'server_error' };
			response.statusCode = 500;
		}
		response.responseBody = Blob.valueOf(JSON.serialize(result));
	}

	@TestVisible
	private static String routeOf(String uri) {
		String path = uri == null ? '' : uri.substringAfter('/barncrm/portal/v1/');
		return path.substringBefore('?').removeEnd('/');
	}

	private static Map<String, Object> bodyOf(RestRequest request) {
		if (request.requestBody == null || request.requestBody.size() == 0) {
			return new Map<String, Object>();
		}
		try {
			Object parsed = JSON.deserializeUntyped(request.requestBody.toString());
			if (parsed instanceof Map<String, Object>) {
				return (Map<String, Object>) parsed;
			}
		} catch (Exception notJson) {
			throw new PortalAuth.RefusalException('invalid_request');
		}
		throw new PortalAuth.RefusalException('invalid_request');
	}

	private static Map<String, Object> route(
		String method,
		String route,
		RestRequest request,
		Map<String, Object> body
	) {
		if (method == 'POST' && route == 'login/start') {
			String challenge = PortalAuth.start(text(body, 'portal'), text(body, 'email'));
			return new Map<String, Object>{ 'challenge' => challenge };
		}
		if (method == 'POST' && route == 'login/verify') {
			return PortalAuth.verifyCode(text(body, 'challenge'), text(body, 'code'));
		}
		if (method == 'POST' && route == 'login/second-factor') {
			return PortalAuth.verifySecondFactor(text(body, 'challenge'), text(body, 'code'));
		}
		String token = request.headers == null ? null : request.headers.get(SESSION_HEADER);
		if (method == 'POST' && route == 'logout') {
			PortalAuth.signOut(token);
			return new Map<String, Object>();
		}
		PortalAuth.Session session = PortalAuth.resolve(token);
		if (method == 'GET' && route == 'me') {
			return PortalData.describe(session);
		}
		if (method == 'GET' && route == 'page') {
			return PortalData.read(session, request.params.get('key'));
		}
		if (method == 'POST' && route == 'page/save') {
			Object values = body.get('values');
			Id saved = PortalData.save(
				session,
				text(body, 'page'),
				text(body, 'recordId'),
				values instanceof Map<String, Object> ? (Map<String, Object>) values : null
			);
			return new Map<String, Object>{ 'id' => saved };
		}
		if (method == 'POST' && route == 'page/action') {
			String message = PortalData.runAction(
				session,
				text(body, 'page'),
				text(body, 'recordId'),
				text(body, 'action')
			);
			return new Map<String, Object>{ 'message' => message };
		}
		if (method == 'POST' && route == 'second-factor/enroll') {
			return PortalAuth.startEnrolment(session);
		}
		if (method == 'POST' && route == 'second-factor/confirm') {
			PortalAuth.confirmEnrolment(session, text(body, 'code'));
			return new Map<String, Object>();
		}
		throw new PortalAuth.RefusalException('not_found');
	}

	private static String text(Map<String, Object> body, String key) {
		Object value = body.get(key);
		return value == null ? null : String.valueOf(value);
	}
}
