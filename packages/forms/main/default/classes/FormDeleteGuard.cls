/**
 * Keeps a form, or a form version, that submissions answer from being deleted by anyone but a
 * Forms administrator (canonical model R-FM4, D-208 N-04). Run before delete by the Core trigger
 * dispatcher through the registry rows `Form_Delete_Guard` and `Form_Version_Delete_Guard`, which
 * always run.
 *
 * A person without the Manage Forms custom permission (`Forms_Manage`, in Forms Admin) gets the
 * message on each form or version that has submissions, which tells them to close the form
 * instead. A Forms administrator's delete goes ahead: the platform clears the submissions' Form
 * and Form Version lookups (set null on delete) and keeps them, and any submission saved before
 * R-FS8 is given its form name and version number first, so it stays identifiable. A form or
 * version no submission answers deletes as before.
 *
 * System mode: whether submissions exist must not depend on which of them the person may read,
 * and the names are written on rows no permission set may edit (Form Name is set by BarnCRM).
 */
@NamespaceAccessible
public with sharing class FormDeleteGuard extends TriggerHandler {
	public static final String MANAGE_PERMISSION = 'Forms_Manage';
	/** Submissions without a form name named in one delete; later ones keep their answers. */
	@TestVisible
	private static final Integer NAME_LIMIT = 2000;

	@NamespaceAccessible
	public FormDeleteGuard() {
		return;
	}

	public override String getName() {
		return 'FormDeleteGuard';
	}

	public override void beforeDelete() {
		Map<Id, SObject> deleting = oldRecordsById();
		if (deleting == null || deleting.isEmpty()) {
			return;
		}
		Boolean forms = deleting.values()[0] instanceof Form__c;
		Set<Id> answered = forms ? formsAnswered(deleting.keySet()) : versionsAnswered(deleting.keySet());
		if (answered.isEmpty()) {
			return;
		}
		if (FeatureManagement.checkPermission(MANAGE_PERMISSION)) {
			nameSubmissions(answered, forms);
			return;
		}
		for (Id recordId : answered) {
			SObject record = deleting.get(recordId);
			if (forms) {
				record.addError(
					BarnHelp.text(
						'Forms',
						'Forms_Delete_FormHasSubmissions',
						new List<Object>{ ((Form__c) record).Name }
					)
				);
			} else {
				record.addError(BarnHelp.text('Forms', 'Forms_Delete_VersionHasSubmissions'));
			}
		}
	}

	private static Set<Id> formsAnswered(Set<Id> formIds) {
		return new Map<Id, Form__c>(
				[
					SELECT Id
					FROM Form__c
					WHERE Id IN :formIds AND Id IN (SELECT Form__c FROM Form_Submission__c)
					WITH SYSTEM_MODE
				]
			)
			.keySet();
	}

	private static Set<Id> versionsAnswered(Set<Id> versionIds) {
		return new Map<Id, Form_Version__c>(
				[
					SELECT Id
					FROM Form_Version__c
					WHERE Id IN :versionIds AND Id IN (SELECT Form_Version__c FROM Form_Submission__c)
					WITH SYSTEM_MODE
				]
			)
			.keySet();
	}

	/** Names the answered records' submissions that have no form name yet, while they still can be. */
	private static void nameSubmissions(Set<Id> answered, Boolean forms) {
		List<Form_Submission__c> unnamed;
		if (forms) {
			unnamed = [
				SELECT Id, Form__c, Form_Version__c, Form_Name__c
				FROM Form_Submission__c
				WHERE Form__c IN :answered AND Form_Name__c = NULL
				WITH SYSTEM_MODE
				LIMIT :NAME_LIMIT
			];
		} else {
			unnamed = [
				SELECT Id, Form__c, Form_Version__c, Form_Name__c
				FROM Form_Submission__c
				WHERE Form_Version__c IN :answered AND Form_Name__c = NULL
				WITH SYSTEM_MODE
				LIMIT :NAME_LIMIT
			];
		}
		if (unnamed.isEmpty()) {
			return;
		}
		FormSubmissionNames.fill(unnamed);
		update as system unnamed;
	}
}
