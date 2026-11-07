/**
 * The public form page on a Salesforce Site (C-42b; ADR-NEXT public forms on a Salesforce Site,
 * decisions 1 and 10): the only class the Site guest user may run (`Forms_Public_Guest`). Thin by
 * design: `FormIntakeService` decides, and nothing here reads or writes a record itself.
 */
public with sharing class FormPublicController {
	private static final String CONTEXT = 'FormPublicController';

	/** The form to fill in, or null when it is not published or not public. */
	@AuraEnabled
	public static FormIntakeService.PublicForm getForm(String formId) {
		Id given;
		try {
			given = Id.valueOf(formId);
		} catch (Exception notAnId) {
			return null;
		}
		try {
			return given.getSObjectType() != Form__c.SObjectType
				? null
				: FormIntakeService.load(given);
		} catch (Exception e) {
			throw failed(e, '.getForm');
		}
	}

	/**
	 * Sends the answers. Nothing about any record comes back: only whether they were received,
	 * or which answers to fix.
	 *
	 * @param answersJson the answers by field key, as JSON
	 * @param trap the hidden question's answer, blank from a person
	 */
	@AuraEnabled
	public static FormIntakeService.Receipt submit(
		String ticket,
		String answersJson,
		String trap,
		String contextRecordId
	) {
		try {
			Object answers = JSON.deserializeUntyped(
				String.isBlank(answersJson) ? '{}' : answersJson
			);
			return FormIntakeService.submit(
				ticket,
				answers instanceof Map<String, Object>
					? (Map<String, Object>) answers
					: new Map<String, Object>(),
				trap,
				contextRecordId
			);
		} catch (Exception e) {
			throw failed(e, '.submit');
		}
	}

	private static AuraHandledException failed(Exception e, String method) {
		ErrorLogger.log(e, CONTEXT + method);
		return UserErrors.message(BarnHelp.text('Forms', 'Forms_Public_Failed'));
	}
}
