/**
 * Scholarships' side of Core's form seam (ADR-0175 decision 9; ADR-0204
 * `0204-scholarships-outbound-grants-module.md` decisions 4 and 5): a cycle names its application
 * form, and its report form, by record ID as text. A submission filled from a cycle creates or
 * updates the person's application (R-SG5) with its eligibility (R-SG3); one filled from a Draft
 * application fills it; one filled from a requirement is the recipient's report. The last two
 * name a person's own record, so their links carry a signed claim (EV-18). Files on the
 * submission are linked to the record they fill.
 *
 * Core finds this class by name (`FormAttachmentExtensions.EXTENSION_CLASSES`). Without Forms it
 * is never called and staff enter applications by hand.
 */
@NamespaceAccessible
public with sharing class ScholarshipFormAttachment implements FormAttachmentExtension {
	private static final Set<String> UPDATABLE = new Set<String>{
		'Draft',
		'Submitted',
		'Eligible',
		'Ineligible'
	};

	@NamespaceAccessible
	public ScholarshipFormAttachment() {
		// Built by name from Core (FormAttachmentExtensions), so it needs a public constructor.
	}

	public Boolean handles(Schema.SObjectType contextType) {
		return contextType == Award_Cycle__c.SObjectType ||
			contextType == Award_Application__c.SObjectType ||
			contextType == Award_Requirement__c.SObjectType;
	}

	/** An application or a requirement is a person's own record. */
	public Boolean signedClaim(Id contextRecordId) {
		return contextRecordId.getSObjectType() != Award_Cycle__c.SObjectType;
	}

	public Id formFor(Id contextRecordId) {
		Schema.SObjectType kind = contextRecordId.getSObjectType();
		String key;
		if (kind == Award_Cycle__c.SObjectType) {
			for (Award_Cycle__c cycle : [
				SELECT Application_Form_Key__c
				FROM Award_Cycle__c
				WHERE Id = :contextRecordId
				WITH USER_MODE
			]) {
				key = cycle.Application_Form_Key__c;
			}
		} else if (kind == Award_Application__c.SObjectType) {
			for (Award_Application__c row : [
				SELECT Cycle__r.Application_Form_Key__c
				FROM Award_Application__c
				WHERE Id = :contextRecordId
				WITH USER_MODE
			]) {
				key = row.Cycle__r.Application_Form_Key__c;
			}
		} else if (kind == Award_Requirement__c.SObjectType) {
			for (Award_Requirement__c row : [
				SELECT Award__r.Cycle__r.Report_Form_Key__c
				FROM Award_Requirement__c
				WHERE Id = :contextRecordId
				WITH USER_MODE
			]) {
				key = row.Award__r.Cycle__r.Report_Form_Key__c;
			}
		}
		return idOf(key);
	}

	public void received(FormSubmissionReceipt receipt) {
		if (receipt == null || receipt.contextRecordId == null) {
			return;
		}
		Schema.SObjectType kind = receipt.contextRecordId.getSObjectType();
		String answers = JSON.serialize(receipt.answers ?? new Map<String, Object>());
		Id target;
		if (kind == Award_Requirement__c.SObjectType) {
			Award_Requirement__c report = new Award_Requirement__c(
				Id = receipt.contextRecordId,
				Status__c = 'Submitted',
				Submitted_Date__c = Date.today(),
				Response__c = answers.abbreviate(131072)
			);
			update as user report;
			target = report.Id;
		} else {
			target = application(receipt, kind, answers);
		}
		if (target != null) {
			linkFiles(receipt.submissionId, target);
		}
	}

	/** R-SG5: the application this submission fills, created when the person has none. */
	private static Id application(
		FormSubmissionReceipt receipt,
		Schema.SObjectType kind,
		String answers
	) {
		Award_Application__c row;
		Id cycleId;
		if (kind == Award_Application__c.SObjectType) {
			row = [
				SELECT Id, Status__c, Cycle__c
				FROM Award_Application__c
				WHERE Id = :receipt.contextRecordId
				WITH USER_MODE
			];
			cycleId = row.Cycle__c;
		} else {
			cycleId = receipt.contextRecordId;
			if (receipt.personId != null) {
				for (Award_Application__c existing : [
					SELECT Id, Status__c, Cycle__c
					FROM Award_Application__c
					WHERE
						Cycle__c = :cycleId
						AND Contact__c = :receipt.personId
						AND Status__c != 'Withdrawn'
					WITH USER_MODE
					LIMIT 1
				]) {
					row = existing;
				}
			}
		}
		if (row != null && !UPDATABLE.contains(row.Status__c)) {
			return null;
		}
		Award_Cycle__c cycle = [
			SELECT Eligibility_Rules__c
			FROM Award_Cycle__c
			WHERE Id = :cycleId
			WITH USER_MODE
		];
		List<String> unmet = unmetRules(cycle.Eligibility_Rules__c, receipt.answers);
		Award_Application__c filled = new Award_Application__c(
			Id = row?.Id,
			Answers__c = answers.abbreviate(131072),
			Submitted_Date__c = Date.today(),
			Form_Submission_Key__c = receipt.submissionId,
			Status__c = unmet == null ? 'Submitted' : (unmet.isEmpty() ? 'Eligible' : 'Ineligible'),
			Eligibility_Notes__c = unmet == null || unmet.isEmpty()
				? null
				: String.join(unmet, '\n')
		);
		if (row == null) {
			filled.Cycle__c = cycleId;
			filled.Contact__c = receipt.personId;
			filled.Organization__c = receipt.organizationId;
		} else {
			if (receipt.personId != null) {
				filled.Contact__c = receipt.personId;
			}
			if (receipt.organizationId != null) {
				filled.Organization__c = receipt.organizationId;
			}
		}
		Object title = receipt.answers?.get('purpose');
		if (title != null) {
			filled.Title__c = String.valueOf(title).abbreviate(255);
		}
		Object requested = receipt.answers?.get('amountRequested');
		if (requested != null) {
			try {
				filled.Amount_Requested__c = Decimal.valueOf(String.valueOf(requested));
			} catch (TypeException notANumber) {
				filled.Amount_Requested__c = null;
			}
		}
		upsert as user filled;
		return filled.Id;
	}

	/**
	 * R-SG3: the rules not met, each as `answer op value`; an empty list when all are met; null
	 * when there are no rules (or they cannot be read, which is logged).
	 */
	@TestVisible
	private static List<String> unmetRules(String rulesJson, Map<String, Object> answers) {
		if (String.isBlank(rulesJson)) {
			return null;
		}
		List<String> unmet = new List<String>();
		try {
			for (Object item : (List<Object>) JSON.deserializeUntyped(rulesJson)) {
				Map<String, Object> rule = (Map<String, Object>) item;
				String key = String.valueOf(rule.get('answer'));
				String op = String.valueOf(rule.get('op'));
				Object given = answers == null ? null : answers.get(key);
				if (!met(op, given, rule.get('value'))) {
					unmet.add(
						key +
							' ' +
							op +
							(rule.get('value') == null
								? ''
								: ' ' + String.valueOf(rule.get('value')))
					);
				}
			}
		} catch (Exception unreadable) {
			ErrorLogger.log(unreadable, 'ScholarshipFormAttachment.unmetRules');
			return null;
		}
		return unmet;
	}

	private static Boolean met(String op, Object given, Object expected) {
		String text = given == null ? '' : String.valueOf(given);
		String wanted = expected == null ? '' : String.valueOf(expected);
		switch on op {
			when 'equals' {
				return text.equalsIgnoreCase(wanted);
			}
			when 'notEquals' {
				return !text.equalsIgnoreCase(wanted);
			}
			when 'contains' {
				return text.containsIgnoreCase(wanted);
			}
			when 'isTrue' {
				return text.equalsIgnoreCase('true') || text.equalsIgnoreCase('yes');
			}
			when 'atLeast', 'atMost' {
				try {
					Decimal value = Decimal.valueOf(text);
					Decimal bound = Decimal.valueOf(wanted);
					return op == 'atLeast' ? value >= bound : value <= bound;
				} catch (TypeException notANumber) {
					return false;
				}
			}
			when else {
				return false;
			}
		}
	}

	/** Links the submission's files to the record it filled; a file already linked is skipped. */
	private static void linkFiles(Id submissionId, Id targetId) {
		if (submissionId == null) {
			return;
		}
		Set<Id> already = new Set<Id>();
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :targetId
			WITH USER_MODE
		]) {
			already.add(link.ContentDocumentId);
		}
		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :submissionId
			WITH USER_MODE
		]) {
			if (already.add(link.ContentDocumentId)) {
				links.add(
					new ContentDocumentLink(
						ContentDocumentId = link.ContentDocumentId,
						LinkedEntityId = targetId,
						ShareType = 'V'
					)
				);
			}
		}
		insert as user links;
	}

	/** The signed link to the form for a person's own application or requirement, or null. */
	public static String linkFor(Id recordId) {
		Id formId = new ScholarshipFormAttachment().formFor(recordId);
		return formId == null ? null : FormCatalogExtensions.publicLink(formId, recordId);
	}

	private static Id idOf(String key) {
		if (String.isBlank(key)) {
			return null;
		}
		try {
			return Id.valueOf(key.trim());
		} catch (StringException notAnId) {
			return null;
		}
	}
}
