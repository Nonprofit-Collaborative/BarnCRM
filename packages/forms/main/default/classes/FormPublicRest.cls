/**
 * Public forms for an API caller (C-42b, C-42c; ADR-NEXT public forms on a Salesforce Site,
 * decisions 7 and 11; D-187): Portal Builder, or any off-platform page, serves a form through a
 * signed-in integration user. The same intake as the Site page (`FormIntakeService`), as plain
 * JSON:
 *
 *   GET  /services/apexrest/barncrm/forms/v1/<formId>[?resume=<token>]  the public form, or 404
 *   POST /services/apexrest/barncrm/forms/v1/<formId>
 *        { ticket, answers, trap, contextRecordId, files?, resume? }  sends the answers
 *        { ticket, answers, trap, saveFor: <email>, step }          saves them for later
 *        returns { status, message, problems }
 *
 * Not given to the Site guest user. The caller's submission is processed at once, as the caller,
 * in user mode, so the integration user needs Forms Staff and access to what the form writes.
 */
@RestResource(urlMapping='/barncrm/forms/v1/*')
global with sharing class FormPublicRest {
	@HttpGet
	global static void getForm() {
		RestRequest request = RestContext.request;
		RestResponse response = RestContext.response;
		Id formId = formIdOf(request);
		String token = request.params == null ? null : request.params.get('resume');
		FormIntakeService.PublicForm form = formId == null
			? null
			: (String.isBlank(token)
					? FormIntakeService.load(formId)
					: FormIntakeService.resume(formId, token));
		response.addHeader('Content-Type', 'application/json');
		response.statusCode = form == null ? 404 : 200;
		response.responseBody = Blob.valueOf(form == null ? '{}' : JSON.serialize(form));
	}

	@HttpPost
	global static void submit() {
		RestRequest request = RestContext.request;
		RestResponse response = RestContext.response;
		response.addHeader('Content-Type', 'application/json');
		Object parsed;
		try {
			parsed = JSON.deserializeUntyped(
				request.requestBody == null ? '{}' : request.requestBody.toString()
			);
		} catch (JSONException notJson) {
			parsed = null;
		}
		if (!(parsed instanceof Map<String, Object>)) {
			response.statusCode = 400;
			response.responseBody = Blob.valueOf('{}');
			return;
		}
		Map<String, Object> body = (Map<String, Object>) parsed;
		FormIntakeService.Receipt receipt = body.containsKey('saveFor')
			? FormIntakeService.saveDraft(
					text(body.get('ticket')),
					mapOf(body.get('answers')),
					text(body.get('trap')),
					text(body.get('saveFor')),
					body.get('step') instanceof Integer ? (Integer) body.get('step') : 0
			  )
			: FormIntakeService.submit(
					text(body.get('ticket')),
					mapOf(body.get('answers')),
					text(body.get('trap')),
					text(body.get('contextRecordId')),
					mapOf(body.get('files')),
					text(body.get('resume'))
			  );
		response.statusCode = 200;
		response.responseBody = Blob.valueOf(JSON.serialize(receipt));
	}

	private static String text(Object value) {
		return value instanceof String ? (String) value : null;
	}

	private static Map<String, Object> mapOf(Object value) {
		return value instanceof Map<String, Object>
			? (Map<String, Object>) value
			: new Map<String, Object>();
	}

	private static Id formIdOf(RestRequest request) {
		String tail = request.requestURI == null ? '' : request.requestURI.substringAfterLast('/');
		try {
			Id given = Id.valueOf(tail);
			return given.getSObjectType() == Form__c.SObjectType ? given : null;
		} catch (Exception notAnId) {
			return null;
		}
	}
}
