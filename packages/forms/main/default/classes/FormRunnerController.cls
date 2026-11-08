/**
 * The Form Runner (C-42a): a published form to fill in, and sending the answers. Thin by design
 * (plan 9.9): plain shapes out; the steps, conditions and checks run in the framework-free
 * modules `c/formRules` and `c/formDefinition`, and `FormSubmitService` decides on the server.
 * Everything runs as the person.
 */
public with sharing class FormRunnerController {
	private static final String CONTEXT = 'FormRunnerController';
	@TestVisible
	private static final Integer FORM_LIMIT = 500;

	/** A published form, as the runner draws it. */
	public class FormView {
		@AuraEnabled
		public String formId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String description;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Integer version;
		/** The published definition's JSON, or null when the form is not published. */
		@AuraEnabled
		public String definition;
		@AuraEnabled
		public String contextRecordId;
		/** Whether the person may send answers (create submissions). */
		@AuraEnabled
		public Boolean canSubmit = false;
	}

	/** One form in the picker. */
	public class FormOption {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
	}

	/** The published forms, by name, for the runner's picker. */
	@AuraEnabled(cacheable=true)
	public static List<FormOption> getPublishedForms() {
		try {
			List<FormOption> options = new List<FormOption>();
			for (Form__c form : [
				SELECT Id, Name
				FROM Form__c
				WHERE Status__c = 'Published'
				WITH USER_MODE
				ORDER BY Name
				LIMIT :FORM_LIMIT
			]) {
				FormOption option = new FormOption();
				option.id = form.Id;
				option.name = form.Name;
				options.add(option);
			}
			return options;
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getPublishedForms', false);
		}
	}

	/**
	 * A form to fill in: the one given, or else the one a module attached to the record it is
	 * filled from (`FormAttachmentExtensions`). Null when there is neither.
	 */
	@AuraEnabled
	public static FormView getForm(Id formId, Id contextRecordId) {
		try {
			Id chosen = formId != null ? formId : FormAttachmentExtensions.formFor(contextRecordId);
			if (chosen == null) {
				return null;
			}
			List<Form__c> forms = [
				SELECT Id, Name, Description__c, Status__c, Published_Version__c
				FROM Form__c
				WHERE Id = :chosen
				WITH USER_MODE
			];
			if (forms.isEmpty()) {
				return null;
			}
			Form__c form = forms[0];
			FormView view = new FormView();
			view.formId = form.Id;
			view.name = form.Name;
			view.description = form.Description__c;
			view.status = form.Status__c;
			view.contextRecordId = contextRecordId;
			view.canSubmit = Schema.SObjectType.Form_Submission__c.isCreateable();
			if (form.Status__c != 'Published') {
				return view;
			}
			for (Form_Version__c version : [
				SELECT Definition__c, Version__c
				FROM Form_Version__c
				WHERE Form__c = :form.Id
				WITH USER_MODE
				ORDER BY Version__c DESC
				LIMIT 1
			]) {
				view.definition = version.Definition__c;
				view.version = version.Version__c.intValue();
			}
			return view;
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getForm', true);
		}
	}

	/**
	 * Sends the answers. Refused answers come back as problem codes with status Invalid and
	 * nothing saved; otherwise the submission is kept and its outcome returned.
	 *
	 * @param answersJson the answers by field key, as JSON
	 * @param filesJson the files for file questions, `{ key: { name, data } }` as JSON, or blank
	 */
	@AuraEnabled
	public static FormSubmitService.Result submit(
		Id formId,
		String answersJson,
		Id contextRecordId,
		String filesJson
	) {
		try {
			return FormSubmitService.submit(
				formId,
				FormRules.jsonMap(answersJson),
				contextRecordId,
				FormRules.jsonMap(filesJson)
			);
		} catch (FormSubmitService.FormException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.submit', true);
		}
	}
}
