/**
 * The public form page on a Salesforce Site (C-42b, C-42c; ADR-0184 public forms on a Salesforce
 * Site, decisions 1, 10 and 11): the only class the Site guest user may run (`Forms_Public_Guest`).
 * Thin by design: `FormIntakeService` decides, and nothing here reads or writes a record itself.
 */
public with sharing class FormPublicController {
	private static final String CONTEXT = 'FormPublicController';

	/**
	 * The form to fill in, or null when it is not published or not public. With an emailed resume
	 * token, the form with the answers saved behind it, or null when the link no longer works.
	 */
	@AuraEnabled
	public static FormIntakeService.PublicForm getForm(String formId, String resumeToken) {
		Id given;
		try {
			given = Id.valueOf(formId);
		} catch (Exception notAnId) {
			return null;
		}
		try {
			if (given.getSObjectType() != Form__c.SObjectType) {
				return null;
			}
			return String.isBlank(resumeToken)
				? FormIntakeService.load(given)
				: FormIntakeService.resume(given, resumeToken);
		} catch (Exception e) {
			throw failed(e, '.getForm');
		}
	}

	/**
	 * Sends the answers and their files. Nothing about any record comes back: only whether they
	 * were received, or which answers to fix.
	 *
	 * @param answersJson the answers by field key, as JSON
	 * @param trap the hidden question's answer, blank from a person
	 * @param filesJson the files for file questions, `{ key: { name, data } }` as JSON, or blank
	 * @param resumeToken the emailed token the form was resumed with, or blank
	 */
	@AuraEnabled
	public static FormIntakeService.Receipt submit(
		String ticket,
		String answersJson,
		String trap,
		String contextRecordId,
		String filesJson,
		String resumeToken
	) {
		try {
			return FormIntakeService.submit(
				ticket,
				FormRules.jsonMap(answersJson),
				trap,
				contextRecordId,
				FormRules.jsonMap(filesJson),
				resumeToken
			);
		} catch (Exception e) {
			throw failed(e, '.submit');
		}
	}

	/** Saves the answers so far and emails a link to finish later (C-42c). */
	@AuraEnabled
	public static FormIntakeService.Receipt saveDraft(
		String ticket,
		String answersJson,
		String trap,
		String email,
		Integer step
	) {
		try {
			return FormIntakeService.saveDraft(
				ticket,
				FormRules.jsonMap(answersJson),
				trap,
				email,
				step
			);
		} catch (Exception e) {
			throw failed(e, '.saveDraft');
		}
	}

	private static AuraHandledException failed(Exception e, String method) {
		ErrorLogger.log(e, CONTEXT + method);
		return UserErrors.message(BarnHelp.text('Forms', 'Forms_Public_Failed'));
	}
}
