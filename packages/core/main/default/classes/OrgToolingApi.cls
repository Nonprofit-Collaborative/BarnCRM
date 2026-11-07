/**
 * The org's own Tooling API, called through the org connection `Barn_Org_Connection` (ADR-0148)
 * with the running job's session, for the Automation tab's scan, deactivation and restore
 * (ADR-NEXT, D-184). Only a queued job calls it: a Lightning session cannot call the API.
 */
public with sharing class OrgToolingApi {
	@TestVisible
	private static final String BASE =
		'callout:' +
		ImportNewFieldService.CONNECTION +
		'/services/data/v' +
		ImportNewFieldService.API_VERSION +
		'/tooling/';
	private static final Integer TIMEOUT_MS = 20000;

	public class ToolingException extends Exception {
	}

	/** The rows of a Tooling query, as maps; the first page only (2,000 rows at most). */
	public static List<Object> query(String soql) {
		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
			send('GET', 'query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'), null)
		);
		return (List<Object>) body.get('records');
	}

	/** One record of a Tooling object, with its Metadata. */
	public static Map<String, Object> read(String objectName, String recordId) {
		return (Map<String, Object>) JSON.deserializeUntyped(
			send('GET', 'sobjects/' + objectName + '/' + recordId, null)
		);
	}

	/** Saves new Metadata on a Tooling record. */
	public static void updateMetadata(
		String objectName,
		String recordId,
		Map<String, Object> metadata
	) {
		send(
			'PATCH',
			'sobjects/' + objectName + '/' + recordId,
			JSON.serialize(new Map<String, Object>{ 'Metadata' => metadata })
		);
	}

	private static String send(String method, String path, String body) {
		HttpRequest call = new HttpRequest();
		call.setEndpoint(BASE + path);
		call.setMethod(method);
		call.setTimeout(TIMEOUT_MS);
		call.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
		call.setHeader('Content-Type', 'application/json');
		if (body != null) {
			call.setBody(body);
		}
		HttpResponse response = new Http().send(call);
		Integer status = response.getStatusCode();
		if (status >= 200 && status < 300) {
			return response.getBody();
		}
		throw new ToolingException(errorText(response));
	}

	/** The API's own message ("[{"message":..., "errorCode":...}]"), else the HTTP status. */
	@TestVisible
	private static String errorText(HttpResponse response) {
		try {
			List<Object> errors = (List<Object>) JSON.deserializeUntyped(response.getBody());
			List<String> messages = new List<String>();
			for (Object each : errors) {
				messages.add(String.valueOf(((Map<String, Object>) each).get('message')));
			}
			return String.join(messages, ' ');
		} catch (Exception notJson) {
			return response.getStatusCode() + ' ' + response.getStatus();
		}
	}
}
