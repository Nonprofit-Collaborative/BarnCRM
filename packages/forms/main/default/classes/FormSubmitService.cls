/**
 * Turns a form's answers into BarnCRM records (canonical model 29ZY, R-FS1 to R-FS4; ADR-0175
 * `0175-forms-module.md`, decisions 6 to 9).
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
	private static final String PERSON_ACCOUNT_FIELD = 'IsPersonAccount'; // detection-only: read only after the describe found person accounts
	private static final String PERSON_ACCOUNT_QUERY = 'SELECT IsPersonAccount FROM Contact WHERE Id = :found'; // detection-only: run only after the describe found person accounts

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
	 * Submits answers to a form's published version, with the files for the form's file
	 * questions (C-42c, R-FS7).
	 *
	 * @param formId the form
	 * @param answers the answers by field key, as the page sends them
	 * @param contextRecordId the record the form was filled from, or null
	 * @param files `{ key: { name, data } }`, data in base64, or null
	 */
	public static Result submit(
		Id formId,
		Map<String, Object> answers,
		Id contextRecordId,
		Map<String, Object> files
	) {
		Form__c form = publishedForm(formId);
		Form_Version__c version = latestVersion(form);
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		Result refused = new Result();
		refused.problems = FormRules.checkAll(definition, answers);
		Map<String, Object> counted = FormRules.countedAnswers(definition, answers);
		List<FormFiles.Upload> uploads = refused.problems.isEmpty()
			? FormFiles.read(definition, counted, files, refused.problems)
			: null;
		if (!refused.problems.isEmpty()) {
			refused.status = INVALID;
			return refused;
		}
		Form_Submission__c submission = new Form_Submission__c(
			Form__c = form.Id,
			Form_Version__c = version.Id,
			Status__c = NEEDS_REVIEW,
			Answers__c = JSON.serialize(counted),
			Context_Record_Id__c = contextRecordId
		);
		insert as user submission;
		FormFiles.keep(submission.Id, uploads, false);
		return process(form, submission, definition, counted);
	}

	/**
	 * Processes a held or failed submission again, using the person and organization staff set
	 * on it, so a review is resolved without asking anyone to fill the form in twice.
	 */
	public static Result reprocess(Id submissionId) {
		Form_Submission__c submission = stored(submissionId);
		if (submission.Status__c == PROCESSED) {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_AlreadyProcessed'));
		}
		return processStored(submission);
	}

	/**
	 * Processes a public submission the intake stored (R-FS6), in user mode as the person
	 * running it: the allowlist is checked again before anything is written (R-FM3).
	 */
	public static Result processReceived(Id submissionId) {
		Form_Submission__c submission = stored(submissionId);
		if (submission.Status__c != FormIntakeService.RECEIVED) {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_AlreadyProcessed'));
		}
		return processStored(submission);
	}

	private static Form_Submission__c stored(Id submissionId) {
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
				Source__c,
				Person__c,
				Organization__c
			FROM Form_Submission__c
			WHERE Id = :submissionId
			WITH USER_MODE
		];
		if (found.isEmpty()) {
			throw new FormException(BarnHelp.text('Forms', 'Forms_Submit_NotFound'));
		}
		return found[0];
	}

	private static Result processStored(Form_Submission__c submission) {
		Map<String, Object> counted = (Map<String, Object>) JSON.deserializeUntyped(
			String.isBlank(submission.Answers__c) ? '{}' : submission.Answers__c
		);
		Form__c form = new Form__c(Id = submission.Form__c, Name = submission.Form__r.Name);
		Map<String, Object> definition = FormRules.parse(submission.Form_Version__r.Definition__c);
		String refused = isPublic(submission) ? publicRefusal(form, submission, definition) : null;
		if (refused != null) {
			Result result = new Result();
			result.submissionId = submission.Id;
			result.status = NEEDS_REVIEW;
			result.message = refused.abbreviate(MESSAGE_LENGTH);
			update as user new Form_Submission__c(
				Id = submission.Id,
				Status__c = NEEDS_REVIEW,
				Message__c = result.message
			);
			return result;
		}
		return process(form, submission, definition, counted);
	}

	private static Boolean isPublic(Form_Submission__c submission) {
		return submission.Source__c == FormIntakeService.SOURCE_PUBLIC;
	}

	/**
	 * Why a public submission is held rather than written, or null (R-FS6): a mapping the
	 * allowlist refuses, or a record it was filled from that no module names this form for.
	 */
	private static String publicRefusal(
		Form__c form,
		Form_Submission__c submission,
		Map<String, Object> definition
	) {
		String problem = FormPublicPolicy.problem(definition);
		if (problem != null) {
			return problem;
		}
		if (
			String.isNotBlank(submission.Context_Record_Id__c) &&
			FormAttachmentExtensions.formFor(Id.valueOf(submission.Context_Record_Id__c)) != form.Id
		) {
			return BarnHelp.text('Forms', 'Forms_Public_ContextNotAttached');
		}
		return null;
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
				if (isPublic(submission)) {
					// An anonymous answer never replaces what is on file (R-FS6).
					entry.onMatch = 'fillBlanks';
				}
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
			FormFiles.share(
				submission.Id,
				new List<Id>{ submission.Person__c, submission.Organization__c }
			);
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
	 * Throws a FormException naming the first object or field the definition writes that this org
	 * lacks, so a form is never published with a target it cannot write (the Form Builder).
	 */
	public static void checkTargets(Map<String, Object> definition) {
		Map<String, Object> everyAnswer = new Map<String, Object>();
		for (Map<String, Object> field : FormRules.allFields(definition)) {
			everyAnswer.put(String.valueOf(field.get('key')), '');
		}
		for (Plan entry : plan(definition, everyAnswer)) {
			Map<String, Schema.SObjectField> fieldMap = typeOf(entry.objectName)
				.getDescribe(SObjectDescribeOptions.DEFERRED)
				.fields.getMap();
			Set<String> names = new Set<String>(entry.fields.keySet());
			names.addAll(entry.links.keySet());
			for (String fieldName : names) {
				describedField(fieldMap, entry.objectName, fieldName);
			}
		}
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
		// Defaults are not loaded here: the platform applies them on insert, and loading them
		// would set fields the user may not be able to edit, which a user mode insert refuses.
		SObject record = type.newSObject();
		if (recordTypeId != null) {
			record.put('RecordTypeId', recordTypeId);
		}
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

	/**
	 * The person found, unless they are stored as a person account: a person account is held for
	 * review, never written through its contact (R-FS6, closing ADR-0175's person account note).
	 */
	private static Id findPerson(Plan entry) {
		Id found = findContact(entry);
		if (
			found == null ||
			!Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
				.fields.getMap()
				.containsKey(PERSON_ACCOUNT_FIELD.toLowerCase())
		) {
			return found;
		}
		List<SObject> rows = Database.queryWithBinds(
			PERSON_ACCOUNT_QUERY,
			new Map<String, Object>{ 'found' => found },
			AccessLevel.USER_MODE
		);
		if (!rows.isEmpty() && rows[0].get(PERSON_ACCOUNT_FIELD) == true) {
			throw new AmbiguousException(BarnHelp.text('Forms', 'Forms_Submit_PersonAccount'));
		}
		return found;
	}

	/**
	 * Core's shared person matcher (`PersonMatcher`). The name and postal code step runs only
	 * for a form set to emailThenNamePostal, and the duplicate rules compare every mapped value.
	 */
	private static Id findContact(Plan entry) {
		PersonMatcher.Person person = new PersonMatcher.Person();
		person.firstName = text(entry.fields, 'FirstName');
		person.lastName = text(entry.fields, 'LastName');
		person.email = text(entry.fields, 'Email');
		person.postalCode = text(entry.fields, 'MailingPostalCode');
		person.byNameAndPostalCode = entry.rule == 'emailThenNamePostal';
		person.duplicateRuleValues = duplicateRuleValues(entry.fields);
		try {
			return PersonMatcher.find(person);
		} catch (PersonMatcher.AmbiguousException several) {
			throw ambiguous(Contact.SObjectType);
		}
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

	/** The answers the org's duplicate rules compare: every mapped value that is not blank. */
	private static Map<String, String> duplicateRuleValues(Map<String, Object> fields) {
		Map<String, String> values = new Map<String, String>();
		for (String fieldName : fields.keySet()) {
			Object value = fields.get(fieldName);
			if (!FormRules.isBlank(value)) {
				values.put(fieldName, String.valueOf(value));
			}
		}
		return values;
	}

	/** The org's own duplicate rules, when one is active: one match is taken, several held. */
	private static Id byDuplicateRules(
		Schema.SObjectType type,
		Map<String, Object> fields,
		Id recordTypeId
	) {
		Map<String, String> values = duplicateRuleValues(fields);
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
