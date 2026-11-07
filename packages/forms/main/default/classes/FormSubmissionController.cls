/**
 * The Submission panel (C-42a): one submission's answers by question, as the version it answered
 * asked them, what it wrote, and Process Again for one held for review or failed (R-FS2). Thin
 * by design (plan 9.9); everything runs as the person.
 */
public with sharing class FormSubmissionController {
	private static final String CONTEXT = 'FormSubmissionController';

	/** One answer, with the question as it was asked. */
	public class AnswerRow {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String type;
		/** The answer as text: an option's label for a picklist, true or false for a checkbox. */
		@AuraEnabled
		public String value;
	}

	/** What the panel draws. */
	public class SubmissionView {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String formName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String message;
		@AuraEnabled
		public List<AnswerRow> answers = new List<AnswerRow>();
		@AuraEnabled
		public List<FormSubmitService.Written> records = new List<FormSubmitService.Written>();
		/** Whether Process Again is offered: not yet processed, and the person may edit it. */
		@AuraEnabled
		public Boolean canProcess = false;
	}

	@AuraEnabled
	public static SubmissionView getSubmission(Id submissionId) {
		try {
			List<Form_Submission__c> found = [
				SELECT
					Id,
					Form__r.Name,
					Form_Version__r.Definition__c,
					Status__c,
					Message__c,
					Answers__c,
					Outcome__c
				FROM Form_Submission__c
				WHERE Id = :submissionId
				WITH USER_MODE
			];
			if (found.isEmpty()) {
				return null;
			}
			Form_Submission__c submission = found[0];
			SubmissionView view = new SubmissionView();
			view.id = submission.Id;
			view.formName = submission.Form__r.Name;
			view.status = submission.Status__c;
			view.message = submission.Message__c;
			view.canProcess =
				submission.Status__c != FormSubmitService.PROCESSED &&
				Schema.SObjectType.Form_Submission__c.isUpdateable();
			view.answers = rows(submission);
			if (String.isNotBlank(submission.Outcome__c)) {
				view.records = (List<FormSubmitService.Written>) JSON.deserialize(
					submission.Outcome__c,
					List<FormSubmitService.Written>.class
				);
			}
			return view;
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getSubmission', true);
		}
	}

	/** Processes a held or failed submission again with the person and organization set on it. */
	@AuraEnabled
	public static FormSubmitService.Result processAgain(Id submissionId) {
		try {
			return FormSubmitService.reprocess(submissionId);
		} catch (FormSubmitService.FormException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.processAgain', true);
		}
	}

	/** The answers in the order the version asks them; answers to removed keys are kept last. */
	private static List<AnswerRow> rows(Form_Submission__c submission) {
		Map<String, Object> answers = String.isBlank(submission.Answers__c)
			? new Map<String, Object>()
			: (Map<String, Object>) JSON.deserializeUntyped(submission.Answers__c);
		List<AnswerRow> rows = new List<AnswerRow>();
		Set<String> shown = new Set<String>();
		Map<String, Object> definition = String.isBlank(submission.Form_Version__r?.Definition__c)
			? new Map<String, Object>()
			: FormRules.parse(submission.Form_Version__r.Definition__c);
		for (Map<String, Object> field : FormRules.allFields(definition)) {
			String key = String.valueOf(field.get('key'));
			if (!answers.containsKey(key)) {
				continue;
			}
			AnswerRow row = new AnswerRow();
			row.key = key;
			row.label = String.valueOf(field.get('label'));
			row.type = String.valueOf(field.get('type'));
			row.value = display(field, answers.get(key));
			rows.add(row);
			shown.add(key);
		}
		for (String key : answers.keySet()) {
			if (!shown.contains(key)) {
				AnswerRow row = new AnswerRow();
				row.key = key;
				row.label = key;
				row.type = 'text';
				row.value = String.valueOf(answers.get(key));
				rows.add(row);
			}
		}
		return rows;
	}

	private static String display(Map<String, Object> field, Object value) {
		String text = String.valueOf(value);
		for (Map<String, Object> option : FormRules.maps(field.get('options'))) {
			if (String.valueOf(option.get('value')) == text) {
				return String.valueOf(option.get('label'));
			}
		}
		return text;
	}
}
