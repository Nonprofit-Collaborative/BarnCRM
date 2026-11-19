/**
 * Gives each submission the name of the form and the number of the version it answers (canonical
 * model R-FS8), so it stays identifiable once a Forms administrator deletes the form and its
 * lookups are cleared (R-FM4). Run before insert and before update by the Core trigger dispatcher
 * through the registry row `Form_Submission_Names`, which always runs; fills only a submission
 * whose Form Name is blank.
 *
 * System mode reads: a public submission is stored by the Site guest user, who reads no form,
 * and only the form's name and the version's number are read.
 */
@NamespaceAccessible
public with sharing class FormSubmissionNames extends TriggerHandler {
	@NamespaceAccessible
	public FormSubmissionNames() {
		return;
	}

	public override String getName() {
		return 'FormSubmissionNames';
	}

	public override void beforeInsert() {
		fill((List<Form_Submission__c>) newRecords());
	}

	public override void beforeUpdate() {
		fill((List<Form_Submission__c>) newRecords());
	}

	/** Fills Form Name and Version Number on the submissions that have no Form Name yet. */
	public static void fill(List<Form_Submission__c> submissions) {
		Set<Id> versionIds = new Set<Id>();
		Set<Id> formIds = new Set<Id>();
		List<Form_Submission__c> unnamed = new List<Form_Submission__c>();
		for (Form_Submission__c submission : submissions) {
			if (String.isNotBlank(submission.Form_Name__c)) {
				continue;
			}
			if (submission.Form_Version__c != null) {
				versionIds.add(submission.Form_Version__c);
			} else if (submission.Form__c != null) {
				formIds.add(submission.Form__c);
			} else {
				continue;
			}
			unnamed.add(submission);
		}
		if (unnamed.isEmpty()) {
			return;
		}
		Map<Id, Form_Version__c> versions = new Map<Id, Form_Version__c>();
		if (!versionIds.isEmpty()) {
			versions.putAll(
				[
					SELECT Id, Version__c, Form__r.Name
					FROM Form_Version__c
					WHERE Id IN :versionIds
					WITH SYSTEM_MODE
				]
			);
		}
		Map<Id, Form__c> forms = new Map<Id, Form__c>();
		if (!formIds.isEmpty()) {
			forms.putAll([SELECT Id, Name FROM Form__c WHERE Id IN :formIds WITH SYSTEM_MODE]);
		}
		for (Form_Submission__c submission : unnamed) {
			Form_Version__c version = versions.get(submission.Form_Version__c);
			if (version != null) {
				submission.Form_Name__c = version.Form__r.Name;
				submission.Version_Number__c = version.Version__c;
			} else if (forms.containsKey(submission.Form__c)) {
				submission.Form_Name__c = forms.get(submission.Form__c).Name;
			}
		}
	}
}
