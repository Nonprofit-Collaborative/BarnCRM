/**
 * The request intake API (D-201; ADR-NEXT `NEXT-projects-requests-and-issues.md` decision 6),
 * for another organization sending its requests in as its own integration user:
 *
 *   POST /services/apexrest/barncrm/requests/v1/requests   creates one (or finds it again)
 *   GET  /services/apexrest/barncrm/requests/v1/requests?orgId=..&refs=A,B   their status
 *
 * A call is served only while Take requests from outside is on and an Active Request Connection
 * names the calling user and the org id the call gives; every refusal is `403 not_allowed`. New
 * requests are capped per connection per hour (`429`), as PaymentWebhookRest caps per processor.
 * The integration user holds only Projects Request Intake (this class, no object access), so
 * the work runs in system mode and touches only that connection's requests. Answers carry a short
 * code, never a stack or another record's detail.
 *
 * `global` because the platform requires it of a REST resource.
 */
@RestResource(urlMapping='/barncrm/requests/v1/*')
global with sharing class ProjectRequestApi {
	@TestVisible
	private static final Integer MAX_BYTES = 32768;
	private static final Integer MAX_REFS = 200;
	private static final String CONTEXT = 'ProjectRequestApi';

	/** One answer: the status code and the JSON body. */
	@TestVisible
	private class Answer {
		Integer code;
		Object body;
		Answer(Integer code, Object body) {
			this.code = code;
			this.body = body;
		}
	}

	@HttpPost
	global static void submit() {
		respond(new Intake().submit(RestContext.request));
	}

	@HttpGet
	global static void status() {
		respond(new Intake().status(RestContext.request));
	}

	private static void respond(Answer answer) {
		RestResponse response = RestContext.response;
		response.addHeader('Content-Type', 'application/json');
		response.statusCode = answer.code;
		response.responseBody = Blob.valueOf(JSON.serialize(answer.body));
	}

	private static Answer refusal(Integer code, String error) {
		return new Answer(code, new Map<String, Object>{ 'error' => error });
	}

	/** A request as the sender reads it back. */
	private static Map<String, Object> view(Project_Request__c request) {
		return new Map<String, Object>{
			'reference' => request.External_Reference__c,
			'number' => request.Name,
			'status' => request.Status__c,
			'priority' => request.Priority__c,
			'dueDate' => request.Due_Date__c,
			'resolution' => request.Resolution__c
		};
	}

	private static String text(Object value, Integer max) {
		return value == null ? null : String.valueOf(value).trim().abbreviate(max);
	}

	/** The value when the picklist holds it, else the fallback. */
	private static String choice(Object value, Schema.SObjectField field, String fallback) {
		String given = text(value, 255);
		for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
			if (entry.isActive() && entry.getValue() == given) {
				return given;
			}
		}
		return fallback;
	}

	/** System mode, scoped to the calling connection (ADR-0185 decision 8 reasoning). */
	private without sharing class Intake {
		Answer submit(RestRequest call) {
			try {
				if (call.requestBody == null || call.requestBody.size() > MAX_BYTES) {
					return refusal(400, 'bad_request');
				}
				Object parsed = JSON.deserializeUntyped(call.requestBody.toString());
				if (!(parsed instanceof Map<String, Object>)) {
					return refusal(400, 'bad_request');
				}
				Map<String, Object> body = (Map<String, Object>) parsed;
				Request_Connection__c connection = connection(text(body.get('orgId'), 18));
				if (connection == null) {
					return refusal(403, 'not_allowed');
				}
				String reference = text(body.get('reference'), 80);
				String subject = text(body.get('subject'), 255);
				if (String.isBlank(reference) || String.isBlank(subject)) {
					return refusal(400, 'bad_request');
				}
				String key = connection.Id + ':' + reference;
				List<Project_Request__c> existing = [
					SELECT
						Id,
						Name,
						Status__c,
						Priority__c,
						Due_Date__c,
						Resolution__c,
						External_Reference__c
					FROM Project_Request__c
					WHERE External_Key__c = :key
					WITH SYSTEM_MODE
					LIMIT 1
				];
				if (!existing.isEmpty()) {
					return new Answer(200, view(existing[0]));
				}
				Integer limitPerHour = connection.Hourly_Limit__c == null
					? 60
					: connection.Hourly_Limit__c.intValue();
				if (
					[
						SELECT COUNT()
						FROM Project_Request__c
						WHERE
							Connection__c = :connection.Id
							AND CreatedDate >= :Datetime.now().addHours(-1)
						WITH SYSTEM_MODE
					] >= limitPerHour
				) {
					return refusal(429, 'too_many');
				}
				Project_Request__c request = new Project_Request__c(
					Subject__c = subject,
					Description__c = describe(body),
					Type__c = choice(
						body.get('type'),
						Project_Request__c.Type__c,
						'Service Request'
					),
					Priority__c = choice(
						body.get('priority'),
						Project_Request__c.Priority__c,
						'Medium'
					),
					Category__c = choice(
						body.get('category'),
						Project_Request__c.Category__c,
						'General'
					),
					Channel__c = ProjectRequestHandler.PARTNER,
					Connection__c = connection.Id,
					Account__c = connection.Account__c,
					External_Reference__c = reference,
					External_Key__c = key
				);
				Database.SaveResult saved = Database.insert(
					request,
					false,
					AccessLevel.SYSTEM_MODE
				);
				if (!saved.isSuccess()) {
					ErrorLogger.logMessage(
						saved.getErrors()[0].getMessage(),
						CONTEXT + '.submit',
						ErrorLogger.SEVERITY_WARNING
					);
					return refusal(422, 'save_failed');
				}
				return new Answer(
					201,
					view(
						[
							SELECT
								Id,
								Name,
								Status__c,
								Priority__c,
								Due_Date__c,
								Resolution__c,
								External_Reference__c
							FROM Project_Request__c
							WHERE Id = :saved.getId()
							WITH SYSTEM_MODE
						]
					)
				);
			} catch (JSONException notJson) {
				return refusal(400, 'bad_request');
			} catch (Exception failed) {
				ErrorLogger.log(failed, CONTEXT + '.submit');
				return refusal(400, 'bad_request');
			}
		}

		Answer status(RestRequest call) {
			try {
				Request_Connection__c connection = connection(text(call.params.get('orgId'), 18));
				if (connection == null) {
					return refusal(403, 'not_allowed');
				}
				Set<String> refs = new Set<String>();
				for (String ref : String.valueOf(call.params.get('refs') ?? '').split(',')) {
					if (String.isNotBlank(ref) && refs.size() < MAX_REFS) {
						refs.add(ref.trim());
					}
				}
				List<Map<String, Object>> found = new List<Map<String, Object>>();
				for (Project_Request__c request : [
					SELECT
						Id,
						Name,
						Status__c,
						Priority__c,
						Due_Date__c,
						Resolution__c,
						External_Reference__c
					FROM Project_Request__c
					WHERE Connection__c = :connection.Id AND External_Reference__c IN :refs
					WITH SYSTEM_MODE
					LIMIT 200
				]) {
					found.add(view(request));
				}
				return new Answer(200, new Map<String, Object>{ 'requests' => found });
			} catch (Exception failed) {
				ErrorLogger.log(failed, CONTEXT + '.status');
				return refusal(400, 'bad_request');
			}
		}

		/** The Active connection for the calling user and the org id it gave, or null. */
		Request_Connection__c connection(String orgId) {
			if (!ProjectsSettings.requestsExternalEnabled() || String.isBlank(orgId)) {
				return null;
			}
			Id org;
			try {
				org = Id.valueOf(orgId);
			} catch (Exception notAnId) {
				return null;
			}
			Id me = UserInfo.getUserId();
			for (Request_Connection__c row : [
				SELECT Id, Org_Id__c, Account__c, Hourly_Limit__c
				FROM Request_Connection__c
				WHERE Integration_User__c = :me AND Active__c = TRUE
				WITH SYSTEM_MODE
				LIMIT 50
			]) {
				try {
					if (Id.valueOf(row.Org_Id__c) == org) {
						return row;
					}
				} catch (Exception badStoredId) {
					continue;
				}
			}
			return null;
		}

		/** The description, then who asked at the sending organization (no Contact is made). */
		String describe(Map<String, Object> body) {
			String description = text(body.get('description'), 30000);
			String name = text(body.get('requesterName'), 120);
			String email = text(body.get('requesterEmail'), 120);
			if (String.isBlank(name) && String.isBlank(email)) {
				return description;
			}
			String who = BarnHelp.text(
				'Projects',
				'Projects_Requests_SubmittedBy',
				new List<Object>{ name ?? '', email ?? '' }
			);
			return String.isBlank(description) ? who : description + '\n\n' + who;
		}
	}
}
