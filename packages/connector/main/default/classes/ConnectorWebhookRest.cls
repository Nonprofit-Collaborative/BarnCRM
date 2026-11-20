/**
 * The BarnCRM Connector webhook receiver (CN-04; canonical model R-CR10; design Sections 3.3 and
 * 3.3a; security review F13), on the org's Salesforce Site for its guest user
 * (`BarnCRM_Connector_Webhook_Guest`):
 *
 *   POST <site URL>/services/apexrest/barncrm/connector/v1/hook
 *   with the header X-BarnCRM-Token: <token>, or ?token=<token> for apps that cannot send one
 *
 * It only stores: it finds the recipe by the token's hash, inserts one Run, Received, in system
 * mode (`ConnectorRunStore`), and publishes the lane's start event; the recipe's identity runs
 * it later. It makes no callout and reads no record but the recipe. No token, unknown token or
 * a recipe never published: 404 with an empty body, nothing stored. Too large: 413. Neither
 * JSON nor form fields: 415, or 400 when unreadable. Past the hourly cap: 429, the first each
 * hour writing one Error Log warning. A resend with the same event id: answered as the first,
 * not stored again. The token is never logged or stored.
 *
 * `global` because the platform requires it of a REST resource.
 */
@RestResource(urlMapping='/barncrm/connector/v1/hook')
global with sharing class ConnectorWebhookRest {
	/** The most characters a post may have: what a run's Input holds. */
	@TestVisible
	private static final Integer MAX_BODY = 131072;
	@TestVisible
	private static final String CONTEXT = 'ConnectorWebhookRest';

	@HttpPost
	global static void receive() {
		ConnectorWebhooks.Reply reply;
		try {
			reply = answer(RestContext.request);
		} catch (Exception failed) {
			// F7: a fixed message and the exception type only, never the request.
			ErrorLogger.logMessage(
				BarnHelp.text('Connector', 'Connector_Log_WebhookFailed', new List<Object>{ failed.getTypeName() }),
				CONTEXT,
				ErrorLogger.SEVERITY_ERROR
			);
			reply = new ConnectorWebhooks.Reply(500, null, null);
		}
		RestResponse response = RestContext.response;
		response.statusCode = reply.status;
		if (reply.body != null) {
			response.addHeader('Content-Type', reply.contentType);
			response.responseBody = Blob.valueOf(reply.body);
		}
	}

	/** What to answer a post, storing it when it is accepted. */
	@TestVisible
	private static ConnectorWebhooks.Reply answer(RestRequest request) {
		String hash = ConnectorWebhooks.hashOf(tokenOf(request));
		Connector_Recipe__c recipe = hash == null ? null : ConnectorRunStore.webhookRecipe(hash);
		Map<String, Object> starter = recipe == null ? null : starterOf(recipe);
		if (starter == null) {
			return refused(404);
		}
		Blob raw = request.requestBody;
		if (raw != null && raw.size() > MAX_BODY * 4) {
			return refused(413);
		}
		String body = raw == null ? '' : raw.toString();
		if (body.length() > MAX_BODY) {
			return refused(413);
		}
		String type = header(request, 'Content-Type');
		type = type == null ? '' : type.toLowerCase();
		Object payload;
		if (type.contains('x-www-form-urlencoded')) {
			payload = formFields(body, request.params);
		} else if (type.contains('json') || String.isBlank(type)) {
			payload = jsonOf(body);
			if (payload == null) {
				return refused(400);
			}
		} else {
			return refused(415);
		}
		String input = JSON.serialize(payload);
		if (input.length() > MAX_BODY) {
			return refused(413);
		}
		Integer cap = ConnectorWebhooks.hourlyCap(recipe);
		Datetime hourAgo = Datetime.now().addHours(-1);
		if (ConnectorRunStore.webhookPostsSince(recipe.Id, hourAgo, cap) >= cap) {
			if (!ConnectorRunStore.loggedSince(CONTEXT, recipe.Id, hourAgo)) {
				ErrorLogger.logMessage(
					BarnHelp.text('Connector', 'Connector_Log_WebhookCap', new List<Object>{ recipe.Name, cap }),
					CONTEXT,
					ErrorLogger.SEVERITY_WARNING,
					recipe.Id
				);
			}
			return refused(429);
		}
		Connector_Run__c run = ConnectorTriggers.newRun(recipe, ConnectorWebhooks.WEBHOOK, input);
		run.Status__c = ConnectorRunStore.RECEIVED;
		run.Reference__c = ConnectorWebhooks.newReference();
		String eventPath = ConnectorRecipeDocument.textOf(starter.get('eventId'));
		String eventId = String.isBlank(eventPath)
			? null
			: ConnectorMapRuntime.text(
					ConnectorMapRuntime.read(new Map<String, Object>{ 'trigger' => payload }, eventPath)
			  );
		if (String.isNotBlank(eventId)) {
			run.Event_Key__c = (recipe.Id + ':' + eventId).left(255);
		}
		String reference = ConnectorRunStore.storeReceived(run);
		if (reference == run.Reference__c) {
			ConnectorClock.publish(new Set<String>{ ConnectorClock.laneOf(recipe.Run_As__c) });
		}
		return ConnectorWebhooks.reply(starter, payload, request.params, reference);
	}

	/** The published `webhook` trigger of the recipe, or null when it has none. */
	private static Map<String, Object> starterOf(Connector_Recipe__c recipe) {
		if (String.isBlank(recipe.Definition_JSON__c)) {
			return null;
		}
		try {
			Map<String, Object> starter = ConnectorRecipeDocument.mapOf(
				ConnectorRecipeDocument.parse(recipe.Definition_JSON__c).get('trigger')
			);
			return starter.get('kind') == 'webhook' ? starter : null;
		} catch (ConnectorRecipeDocument.DocumentException unreadable) {
			return null;
		}
	}

	/** The token from the `X-BarnCRM-Token` header, else from `?token=` (F13). */
	private static String tokenOf(RestRequest request) {
		String given = header(request, ConnectorWebhooks.HEADER);
		return String.isNotBlank(given) ? given : request.params.get('token');
	}

	/** A posted JSON object; a list is `{ "items": [...] }`; blank is an empty object. */
	private static Object jsonOf(String body) {
		if (String.isBlank(body)) {
			return new Map<String, Object>();
		}
		try {
			Object parsed = JSON.deserializeUntyped(body);
			if (parsed instanceof List<Object>) {
				return new Map<String, Object>{ 'items' => parsed };
			}
			return parsed instanceof Map<String, Object> ? parsed : null;
		} catch (Exception unreadable) {
			return null;
		}
	}

	/** Form fields as text, from the body or, when the platform read them, the parameters. */
	private static Map<String, Object> formFields(String body, Map<String, String> params) {
		Map<String, Object> fields = new Map<String, Object>();
		if (String.isNotBlank(body)) {
			for (String pair : body.split('&')) {
				Integer split = pair.indexOf('=');
				String name = split < 0 ? pair : pair.substring(0, split);
				String value = split < 0 ? '' : pair.substring(split + 1);
				fields.put(EncodingUtil.urlDecode(name, 'UTF-8'), EncodingUtil.urlDecode(value, 'UTF-8'));
			}
		} else if (params != null) {
			fields.putAll(params);
		}
		fields.remove('token');
		return fields;
	}

	/** A header by name, whatever its case. */
	private static String header(RestRequest request, String name) {
		for (String key : request.headers.keySet()) {
			if (key.equalsIgnoreCase(name)) {
				return request.headers.get(key);
			}
		}
		return null;
	}

	private static ConnectorWebhooks.Reply refused(Integer status) {
		return new ConnectorWebhooks.Reply(status, null, null);
	}
}
