/**
 * Turns a form's answers into BarnCRM records (canonical model 29ZY, R-FS1 to R-FS4; ADR-NEXT
 * `NEXT-forms-module.md`, decisions 6 to 9).
 *
 * The server decides: the published version's rules are applied again (`FormRules`), hidden
 * answers are dropped, and the answers are kept on a Form Submission before anything else is
 * written, so nothing typed is lost. The person and organization are then found with Core's
 * matchers, never a second one: `ImportMatcher` by email, then last name and postal code, each
 * narrowed by first name (R-IB12), then the org's duplicate rules (`ImportDuplicateRuleMatcher`).
 * A key several records hold is never guessed (R-FS2). Everything runs as the person, under one
 * savepoint (R-FS3); a module that attached the form hears about it last (R-FS4).
 *
 * Plain values in and out (plan 9.9): C-42b adds a guest entry point beside this one.
 */
public with sharing class FormSubmitService {
	public static final String PROCESSED = 'Processed';
	public static final String NEEDS_REVIEW = 'Needs Review';
	public static final String FAILED = 'Failed';
	/** The result of answers the rules refused: nothing was saved. */
	public static final String INVALID = 'Invalid';
	private static final String CONTEXT = 'FormSubmitService';
	private static final Integer MESSAGE_LENGTH = 255;

	/** A request the person can fix, worded for them. */
	public class FormException extends Exception {
	}

	/** A person or organization several records match (R-FS2). */
	private class AmbiguousException extends Exception {
	}

	/** One record written or found. */
	public class Written {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public String recordId;
		/** matched (found, nothing to fill), updated (found and filled) or created. */
		@AuraEnabled
		public String action;
	}

	/** What happened to one submission. */
	public class Result {
		@AuraEnabled
		public String submissionId;
		/** Processed, Needs Review, Failed, or Invalid when the answers were refused. */
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String message;
		/** The problem code of each refused answer, by field key (Invalid only). */
		@AuraEnabled
		public Map<String, String> problems = new Map<String, String>();
		@AuraEnabled
		public List<Written> records = new List<Written>();
	}

	/** One record entry with the values the answers give it (c/formMapping planWrites). */
	public class Plan {
		public String key;
		public String kind;
		public String objectName;
		public Map<String, Object> fields = new Map<String, Object>();
		public Map<String, String> links = new Map<String, String>();
		public String rule;
		public String onMatch;
	}

	/**
	 * Submits answers to a form's published version.
	 *
	 * @param formId the form
	 * @param answers the answers by field key, as the page sends them
	 * @param contextRecordId the record the form was filled from, or null
	 */
	public static Result submit(Id formId, Map<String, Object> answers, Id contextRecordId) {
		Form__c form = publishedForm(formId);
		Form_Version__c version = latestVersion(form);
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		Result refused = new Result();
		refused.problems = FormRules.checkAll(definition, answers);
		if (!refused.problems.isEmpty()) {
			refused.status = INVALID;
			return refused;
		}
		Map<String, Object> counted = FormRules.countedAnswers(definition, answers);
		Form_Submission__c submission = new Form_Submission__c(
			Form__c = form.Id,
			Form_Version__c = version.Id,
			Status__c = NEEDS_REVIEW,
			Answers__c = JSON.serialize(counted),
			Context_Record_Id__c = contextRecordId
		);
		insert as user submission;
		return process(form, submission, definition, counted);
	}

	/**
	 * Processes a held or failed submission again, using the person and organization staff set
	 * on it, so a review is resolved without asking anyone to fill the form in twice.
	 */
	public static Result reprocess(Id submissionId) {
		List<Form_Submission__c> found = [
			SELECT
				Id,
				Form__c,
				Form__r.Name,
				Form_Version__c,
				Form_Version__r.Definition__c,
				Answers__c,
				Context_Record_Id__c,
				Status__c,
				Person__c,
				Organization__c
			FROM Form_Submission__c
			WHERE Id = :submissionId
			WITH USER_MODE
		];
		if (found.isEmpty()) {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_NotFound'));
		}
		Form_Submission__c submission = found[0];
		if (submission.Status__c == PROCESSED) {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_AlreadyProcessed'));
		}
		Map<String, Object> counted = (Map<String, Object>) JSON.deserializeUntyped(
			String.isBlank(submission.Answers__c) ? '{}' : submission.Answers__c
		);
		return process(
			new Form__c(Id = submission.Form__c, Name = submission.Form__r.Name),
			submission,
			FormRules.parse(submission.Form_Version__r.Definition__c),
			counted
		);
	}

	private static Form__c publishedForm(Id formId) {
		List<Form__c> forms = [
			SELECT Id, Name, Status__c, Published_Version__c
			FROM Form__c
			WHERE Id = :formId
			WITH USER_MODE
		];
		if (forms.isEmpty() || forms[0].Status__c != 'Published') {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_NotPublished'));
		}
		return forms[0];
	}

	private static Form_Version__c latestVersion(Form__c form) {
		List<Form_Version__c> versions = [
			SELECT Id, Definition__c
			FROM Form_Version__c
			WHERE Form__c = :form.Id
			WITH USER_MODE
			ORDER BY Version__c DESC
			LIMIT 1
		];
		if (versions.isEmpty()) {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_NotPublished'));
		}
		return versions[0];
	}

	/** Writes the plan for one submission and records the outcome on it. */
	private static Result process(
		Form__c form,
		Form_Submission__c submission,
		Map<String, Object> definition,
		Map<String, Object> counted
	) {
		Result result = new Result();
		result.submissionId = submission.Id;
		Id chosenPerson = submission.Person__c;
		Id chosenOrganization = submission.Organization__c;
		Id contextId = String.isBlank(submission.Context_Record_Id__c)
			? null
			: Id.valueOf(submission.Context_Record_Id__c);
		Map<String, Id> ids = new Map<String, Id>();
		System.Savepoint before = Database.setSavepoint();
		try {
			for (Plan entry : plan(definition, counted)) {
				Id chosen = entry.kind == 'person'
					? chosenPerson
					: (entry.kind == 'organization' ? chosenOrganization : null);
				Written written = write(entry, ids, contextId, chosen);
				if (written == null) {
					continue;
				}
				ids.put(entry.key, written.recordId);
				result.records.add(written);
				if (entry.kind == 'person') {
					submission.Person__c = written.recordId;
				} else if (entry.kind == 'organization') {
					submission.Organization__c = written.recordId;
				}
			}
			submission.Status__c = PROCESSED;
			submission.Message__c = null;
			List<String> failures = FormAttachmentExtensions.notify(
				receipt(form, submission, counted, ids, contextId)
			);
			if (!failures.isEmpty()) {
				submission.Status__c = NEEDS_REVIEW;
				submission.Message__c = BarnHelp.text(
						'Forms',
						'Forms_Submit_ModuleFailed',
						new List<Object>{ failures[0] }
					)
					.abbreviate(MESSAGE_LENGTH);
			}
		} catch (AmbiguousException manyMatch) {
			Database.rollback(before);
			held(result, submission, chosenPerson, chosenOrganization, NEEDS_REVIEW);
			submission.Message__c = manyMatch.getMessage().abbreviate(MESSAGE_LENGTH);
		} catch (Exception problem) {
			Database.rollback(before);
			ErrorLogger.log(problem, CONTEXT + '.process', submission.Id);
			held(result, submission, chosenPerson, chosenOrganization, FAILED);
			submission.Message__c = BarnHelp.text(
					'Forms',
					'Forms_Submit_Failed',
					new List<Object>{ problem.getMessage() }
				)
				.abbreviate(MESSAGE_LENGTH);
		}
		submission.Outcome__c = JSON.serialize(result.records);
		// Only what processing changes: the form it belongs to (master-detail) never moves.
		update as user new Form_Submission__c(
			Id = submission.Id,
			Status__c = submission.Status__c,
			Message__c = submission.Message__c,
			Outcome__c = submission.Outcome__c,
			Person__c = submission.Person__c,
			Organization__c = submission.Organization__c
		);
		result.status = submission.Status__c;
		result.message = submission.Message__c;
		return result;
	}

	/** Puts a submission back as it was before a rolled back attempt, with a new status. */
	private static void held(
		Result result,
		Form_Submission__c submission,
		Id person,
		Id organization,
		String status
	) {
		result.records.clear();
		submission.Person__c = person;
		submission.Organization__c = organization;
		submission.Status__c = status;
	}

	private static FormSubmissionReceipt receipt(
		Form__c form,
		Form_Submission__c submission,
		Map<String, Object> counted,
		Map<String, Id> ids,
		Id contextId
	) {
		FormSubmissionReceipt receipt = new FormSubmissionReceipt();
		receipt.formId = form.Id;
		receipt.formName = form.Name;
		receipt.submissionId = submission.Id;
		receipt.contextRecordId = contextId;
		receipt.personId = submission.Person__c;
		receipt.organizationId = submission.Organization__c;
		receipt.answers = counted;
		receipt.recordIds = ids;
		return receipt;
	}

	/**
	 * The records a submission writes, person first, then organization, then the rest in the
	 * listed order, with the mapped answers and constants (c/formMapping planWrites).
	 */
	public static List<Plan> plan(Map<String, Object> definition, Map<String, Object> counted) {
		List<Plan> people = new List<Plan>();
		List<Plan> organizations = new List<Plan>();
		List<Plan> related = new List<Plan>();
		Map<String, Plan> byKey = new Map<String, Plan>();
		for (Map<String, Object> record : FormRules.records(definition)) {
			Plan entry = new Plan();
			entry.key = String.valueOf(record.get('key'));
			entry.kind = String.valueOf(record.get('kind'));
			entry.objectName = entry.kind == 'person'
				? 'Contact'
				: (entry.kind == 'organization' ? 'Account' : String.valueOf(record.get('object')));
			if (record.get('values') instanceof Map<String, Object>) {
				entry.fields.putAll((Map<String, Object>) record.get('values'));
			}
			if (record.get('links') instanceof Map<String, Object>) {
				Map<String, Object> links = (Map<String, Object>) record.get('links');
				for (String field : links.keySet()) {
					entry.links.put(field, String.valueOf(links.get(field)));
				}
			}
			Map<String, Object> matching = record.get('matching') instanceof Map<String, Object>
				? (Map<String, Object>) record.get('matching')
				: new Map<String, Object>();
			entry.rule = matching.get('rule') == null
				? (entry.kind == 'organization' ? 'name' : 'emailThenNamePostal')
				: String.valueOf(matching.get('rule'));
			entry.onMatch = matching.get('onMatch') == null
				? 'fillBlanks'
				: String.valueOf(matching.get('onMatch'));
			byKey.put(entry.key, entry);
			if (entry.kind == 'person') {
				people.add(entry);
			} else if (entry.kind == 'organization') {
				organizations.add(entry);
			} else {
				related.add(entry);
			}
		}
		for (Map<String, Object> field : FormRules.allFields(definition)) {
			Map<String, Object> target = field.get('target') instanceof Map<String, Object>
				? (Map<String, Object>) field.get('target')
				: null;
			String key = String.valueOf(field.get('key'));
			if (target == null || !counted.containsKey(key)) {
				continue;
			}
			Plan entry = byKey.get(String.valueOf(target.get('record')));
			String fieldName = String.valueOf(target.get('field'));
			if (entry != null && String.isNotBlank(fieldName)) {
				entry.fields.put(fieldName, counted.get(key));
			}
		}
		List<Plan> ordered = new List<Plan>(people);
		ordered.addAll(organizations);
		ordered.addAll(related);
		return ordered;
	}

	/**
	 * Finds or creates one record of the plan and writes its values. Null when it is skipped: a
	 * person with no last name or an organization with no name that matched nobody (the
	 * questions were optional and left blank), or a related record linking to one skipped.
	 */
	private static Written write(Plan entry, Map<String, Id> ids, Id contextId, Id chosen) {
		for (String to : entry.links.values()) {
			if (to != 'context' && !ids.containsKey(to)) {
				return null;
			}
		}
		Schema.SObjectType type = typeOf(entry.objectName);
		Map<String, Schema.SObjectField> fieldMap = type.getDescribe(
				SObjectDescribeOptions.DEFERRED
			)
			.fields.getMap();
		Written written = new Written();
		written.key = entry.key;
		written.kind = entry.kind;
		written.objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
		Id matched = chosen;
		if (matched == null && entry.kind == 'person') {
			matched = findPerson(entry);
		} else if (matched == null && entry.kind == 'organization') {
			matched = findOrganization(entry);
		}
		if (matched != null) {
			written.recordId = matched;
			written.action = fill(type, fieldMap, entry, matched) ? 'updated' : 'matched';
			return written;
		}
		String nameField = entry.kind == 'person'
			? 'LastName'
			: (entry.kind == 'organization' ? 'Name' : null);
		if (nameField != null && text(entry.fields, nameField) == null) {
			return null;
		}
		Id recordTypeId = entry.kind == 'organization'
			? AccountKinds.organizationRecordTypeId()
			: null;
		// With no record type the field is left unset: an explicit null is refused (ADR-0141).
		SObject record = recordTypeId == null
			? type.newSObject()
			: type.newSObject(recordTypeId, true);
		for (String fieldName : entry.fields.keySet()) {
			put(record, fieldMap, written.objectName, fieldName, entry.fields.get(fieldName));
		}
		for (String fieldName : entry.links.keySet()) {
			String to = entry.links.get(fieldName);
			Id linked = to == 'context' ? contextId : ids.get(to);
			if (linked != null) {
				put(record, fieldMap, written.objectName, fieldName, linked);
			}
		}
		insert as user record;
		written.recordId = record.Id;
		written.action = 'created';
		return written;
	}

	/**
	 * Writes a found record's values: only into blank fields (fillBlanks), or over what it has
	 * (overwrite). Returns whether anything changed.
	 */
	private static Boolean fill(
		Schema.SObjectType type,
		Map<String, Schema.SObjectField> fieldMap,
		Plan entry,
		Id recordId
	) {
		if (entry.fields.isEmpty()) {
			return false;
		}
		String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
		SObject current = null;
		if (entry.onMatch != 'overwrite') {
			List<String> names = new List<String>();
			for (String fieldName : entry.fields.keySet()) {
				names.add(describedField(fieldMap, objectName, fieldName).getName());
			}
			current = Database.queryWithBinds(
				'SELECT Id, ' +
					String.join(names, ', ') +
					' FROM ' +
					objectName +
					' WHERE Id = :recordId',
				new Map<String, Object>{ 'recordId' => recordId },
				AccessLevel.USER_MODE
			)[0];
		}
		SObject record = type.newSObject(recordId);
		Boolean changed = false;
		for (String fieldName : entry.fields.keySet()) {
			String name = describedField(fieldMap, objectName, fieldName).getName();
			if (current == null || FormRules.isBlank(current.get(name))) {
				put(record, fieldMap, objectName, fieldName, entry.fields.get(fieldName));
				changed = true;
			}
		}
		if (changed) {
			update as user record;
		}
		return changed;
	}

	private static Id findPerson(Plan entry) {
		String first = text(entry.fields, 'FirstName');
		ImportMatcher.forgetHeldKeys();
		String emailKey = ImportMatcher.emailKey(text(entry.fields, 'Email'));
		if (emailKey != null) {
			Id found = byKey(
				ImportMatcher.contactsByEmail(new Set<String>{ emailKey }),
				emailKey,
				first
			);
			if (found != null) {
				return found;
			}
		}
		String namePostal = ImportMatcher.nameAndPostalKey(
			text(entry.fields, 'LastName'),
			text(entry.fields, 'MailingPostalCode')
		);
		if (entry.rule == 'emailThenNamePostal' && namePostal != null) {
			Id found = byKey(
				ImportMatcher.contactsByNameAndPostalCode(new Set<String>{ namePostal }),
				namePostal,
				first
			);
			if (found != null) {
				return found;
			}
		}
		return byDuplicateRules(Contact.SObjectType, entry.fields, null);
	}

	private static Id findOrganization(Plan entry) {
		Id recordTypeId = AccountKinds.organizationRecordTypeId();
		ImportMatcher.forgetHeldKeys();
		String key = ImportMatcher.nameKey(text(entry.fields, 'Name'));
		if (key != null) {
			Map<String, Id> found = ImportMatcher.accountsByName(
				new Set<String>{ key },
				recordTypeId
			);
			if (found.containsKey(key)) {
				if (ImportMatcher.isHeldByMany(key)) {
					throw ambiguous(Account.SObjectType);
				}
				return found.get(key);
			}
		}
		return byDuplicateRules(Account.SObjectType, entry.fields, recordTypeId);
	}

	/**
	 * The holder of a key. With a first name, only a holder of that first name, or one with no
	 * first name, is taken, so one of two people sharing an email is never taken for the other
	 * (R-IB12). Without one, a key held by several is never guessed (R-FS2).
	 */
	private static Id byKey(Map<String, Id> found, String key, String first) {
		if (String.isNotBlank(first)) {
			List<String> narrowedKeys = new List<String>{
				ImportMatcher.firstNameKey(key, first),
				ImportMatcher.firstNameKey(key, null)
			};
			for (String narrowed : narrowedKeys) {
				if (found.containsKey(narrowed)) {
					if (ImportMatcher.isHeldByMany(narrowed)) {
						throw ambiguous(Contact.SObjectType);
					}
					return found.get(narrowed);
				}
			}
			return null;
		}
		if (!found.containsKey(key)) {
			return null;
		}
		if (ImportMatcher.isHeldByMany(key)) {
			throw ambiguous(Contact.SObjectType);
		}
		return found.get(key);
	}

	/** The org's own duplicate rules, when one is active: one match is taken, several held. */
	private static Id byDuplicateRules(
		Schema.SObjectType type,
		Map<String, Object> fields,
		Id recordTypeId
	) {
		Map<String, String> values = new Map<String, String>();
		for (String fieldName : fields.keySet()) {
			Object value = fields.get(fieldName);
			if (!FormRules.isBlank(value)) {
				values.put(fieldName, String.valueOf(value));
			}
		}
		if (values.isEmpty()) {
			return null;
		}
		SObject probe = ImportDuplicateRuleMatcher.probe(type, values, recordTypeId);
		List<List<SObject>> matches = ImportDuplicateRuleMatcher.matchesFor(
			new List<SObject>{ probe },
			recordTypeId == null ? null : new Set<Id>{ recordTypeId }
		);
		if (matches == null || matches.isEmpty() || matches[0].isEmpty()) {
			return null;
		}
		if (matches[0].size() > 1) {
			throw ambiguous(type);
		}
		return matches[0][0].Id;
	}

	private static AmbiguousException ambiguous(Schema.SObjectType type) {
		return new AmbiguousException(
			type == Contact.SObjectType
				? BarnHelp.text('Forms', 'Forms_Submit_ManyPeople')
				: BarnHelp.text('Forms', 'Forms_Submit_ManyOrganizations')
		);
	}

	private static String text(Map<String, Object> fields, String fieldName) {
		for (String name : fields.keySet()) {
			if (name.equalsIgnoreCase(fieldName)) {
				Object value = fields.get(name);
				return FormRules.isBlank(value) ? null : String.valueOf(value).trim();
			}
		}
		return null;
	}

	private static Schema.SObjectType typeOf(String objectName) {
		try {
			return Schema.describeSObjects(
					new List<String>{ objectName },
					SObjectDescribeOptions.DEFERRED
				)[0]
				.getSObjectType();
		} catch (Exception unknown) {
			throw new FormException(
				BarnHelp.text('Forms', 'Forms_Submit_NoObject', new List<Object>{ objectName })
			);
		}
	}

	private static Schema.DescribeFieldResult describedField(
		Map<String, Schema.SObjectField> fieldMap,
		String objectName,
		String fieldName
	) {
		Schema.SObjectField field = fieldName == null
			? null
			: fieldMap.get(fieldName.toLowerCase());
		if (field == null) {
			throw new FormException(
				BarnHelp.text(
					'Forms',
					'Forms_Submit_NoField',
					new List<Object>{ objectName, fieldName }
				)
			);
		}
		return field.getDescribe();
	}

	/** Sets one field, converting the answer to the field's type. */
	private static void put(
		SObject record,
		Map<String, Schema.SObjectField> fieldMap,
		String objectName,
		String fieldName,
		Object value
	) {
		Schema.DescribeFieldResult described = describedField(fieldMap, objectName, fieldName);
		record.put(described.getName(), FormSubmitService.converted(described, value));
	}

	/** An answer as the field's type takes it: a date, a number, true or false, or text. */
	public static Object converted(Schema.DescribeFieldResult described, Object value) {
		if (FormRules.isBlank(value)) {
			return value instanceof Boolean ? value : null;
		}
		String text = String.valueOf(value).trim();
		switch on described.getType() {
			when BOOLEAN {
				return value == true || text.equalsIgnoreCase('true');
			}
			when DATE {
				return Date.valueOf(text);
			}
			when DOUBLE, CURRENCY, PERCENT {
				return Decimal.valueOf(text);
			}
			when INTEGER {
				return Decimal.valueOf(text).intValue();
			}
			when REFERENCE {
				return Id.valueOf(text);
			}
			when else {
				return text;
			}
		}
	}
}
