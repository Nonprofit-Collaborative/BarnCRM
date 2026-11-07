/**
 * The public intake: a form loaded and answers stored for someone with no BarnCRM login, on a
 * Salesforce Site or through an API caller (canonical model R-FS5; ADR-NEXT public forms on a
 * Salesforce Site, decisions 1, 2, 5 and 7).
 *
 * The one `without sharing` class in Forms, and deliberately narrow: it reads only the form and
 * version asked for (published and public), counts the form's public submissions in the last
 * hour, and inserts one Form Submission with Status Received. It never reads a person, an
 * organization or any other record, and never returns a record identifier, so nothing about who
 * is on file can be learned from it. The answers are processed later as a staff user
 * (`FormPublicProcessor`), or at once when the caller is a signed-in user.
 *
 * Plain values in and out (plan 9.9): `FormPublicController` (a Site page) and `FormPublicRest`
 * (an integration user, D-187) are thin wrappers.
 */
public without sharing class FormIntakeService {
	public static final String RECEIVED = 'Received';
	public static final String INVALID = 'Invalid';
	public static final String RETRY = 'Retry';
	public static final String EXPIRED = 'Expired';
	public static final String BUSY = 'Busy';
	public static final String CLOSED = 'Closed';
	public static final String SOURCE_PUBLIC = 'Public';
	private static final Long TICKET_LIFE_MS = 24L * 60 * 60 * 1000;
	private static final String CONTEXT = 'FormIntakeService';

	/** Set by tests to move the clock: milliseconds added to now. */
	@TestVisible
	private static Long clockShiftMs = 0;

	/** Set by tests to act as a Site guest user, whose submissions wait for processing. */
	@TestVisible
	private static Boolean actAsGuest = false;

	/** A public form as a page draws it. */
	public class PublicForm {
		@AuraEnabled
		public String formId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String description;
		@AuraEnabled
		public Integer version;
		/** The public copy of the definition (no records, targets or constants). */
		@AuraEnabled
		public String definition;
		/** Sent back with the answers: which version, when it was loaded, and its signature. */
		@AuraEnabled
		public String ticket;
	}

	/** What became of the answers, and nothing about any record. */
	public class Receipt {
		/** Received, Invalid, Retry, Expired, Busy or Closed. */
		@AuraEnabled
		public String status;
		/** The form's own confirmation, when it has one and the answers were received. */
		@AuraEnabled
		public String message;
		/** The problem code of each refused answer, by field key (Invalid only). */
		@AuraEnabled
		public Map<String, String> problems = new Map<String, String>();
	}

	/** The form to fill in, or null when it is not published or not public. */
	public static PublicForm load(Id formId) {
		Form_Version__c version = latestPublicVersion(formId);
		if (version == null) {
			return null;
		}
		PublicForm view = new PublicForm();
		view.formId = version.Form__c;
		view.name = version.Form__r.Name;
		view.description = version.Form__r.Description__c;
		view.version = version.Version__c.intValue();
		view.definition = FormPublicPolicy.publicCopy(FormRules.parse(version.Definition__c));
		view.ticket = ticketFor(version, now());
		return view;
	}

	/**
	 * Stores the answers after the spam checks and the answer checks (R-FS5), in that order.
	 *
	 * @param ticket the ticket the form was loaded with
	 * @param answers the answers by field key
	 * @param trap the hidden question's answer: anything in it means a script filled the form
	 * @param contextRecordId the record the form was filled from, or blank
	 */
	public static Receipt submit(
		String ticket,
		Map<String, Object> answers,
		String trap,
		String contextRecordId
	) {
		Receipt receipt = new Receipt();
		if (String.isNotBlank(trap)) {
			// Told it was received, so a script learns nothing; nothing is stored.
			receipt.status = RECEIVED;
			return receipt;
		}
		List<String> parts = String.isBlank(ticket) ? new List<String>() : ticket.split(':');
		Form_Version__c version = parts.size() == 3 ? versionOf(parts[0]) : null;
		if (
			version == null ||
			!version.Form__r.Public__c ||
			version.Form__r.Status__c != 'Published'
		) {
			receipt.status = parts.size() == 3 && version != null ? CLOSED : EXPIRED;
			return receipt;
		}
		Long issued = parts[1].isNumeric() ? Long.valueOf(parts[1]) : -1;
		Long age = now() - issued;
		if (ticketFor(version, issued) != ticket || issued < 0 || age < 0 || age > TICKET_LIFE_MS) {
			receipt.status = EXPIRED;
			return receipt;
		}
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		Id contextId = idOrNull(contextRecordId);
		if (
			!FormPublicPolicy.isPublic(definition) ||
			(String.isNotBlank(contextRecordId) && contextId == null)
		) {
			receipt.status = CLOSED;
			return receipt;
		}
		if (age < FormPublicPolicy.minSeconds(definition) * 1000L) {
			receipt.status = RETRY;
			return receipt;
		}
		if (recentCount(version.Form__c) >= FormPublicPolicy.hourlyLimit(definition)) {
			receipt.status = BUSY;
			return receipt;
		}
		Map<String, Object> given = answers == null ? new Map<String, Object>() : answers;
		receipt.problems = FormRules.checkAll(definition, given);
		if (!receipt.problems.isEmpty()) {
			receipt.status = INVALID;
			return receipt;
		}
		Form_Submission__c submission = new Form_Submission__c(
			Form__c = version.Form__c,
			Form_Version__c = version.Id,
			Status__c = RECEIVED,
			Source__c = SOURCE_PUBLIC,
			Answers__c = JSON.serialize(FormRules.countedAnswers(definition, given)),
			Context_Record_Id__c = contextId
		);
		Database.insert(submission, AccessLevel.SYSTEM_MODE);
		processNowIfSignedIn(submission.Id);
		receipt.status = RECEIVED;
		receipt.message = FormPublicPolicy.confirmation(definition);
		return receipt;
	}

	/**
	 * A signed-in caller (an integration user) has its submission processed at once, as itself
	 * and in user mode (decision 2). A guest's waits for `FormPublicProcessor`.
	 */
	private static void processNowIfSignedIn(Id submissionId) {
		if (
			actAsGuest ||
			UserInfo.getUserType() == 'Guest' ||
			!Schema.SObjectType.Form_Submission__c.isUpdateable()
		) {
			return;
		}
		try {
			FormSubmitService.processReceived(submissionId);
		} catch (Exception e) {
			// Kept as Received: the scheduled processing takes it up.
			ErrorLogger.log(e, CONTEXT + '.processNowIfSignedIn', submissionId);
		}
	}

	/** Gives a newly published version its signing key (decision 5). */
	public static void giveKey(Id versionId) {
		Database.update(
			new Form_Version__c(
				Id = versionId,
				Signing_Key__c = EncodingUtil.convertToHex(Crypto.generateAesKey(256))
			),
			AccessLevel.SYSTEM_MODE
		);
	}

	private static Form_Version__c latestPublicVersion(Id formId) {
		List<Form_Version__c> versions = [
			SELECT
				Id,
				Form__c,
				Form__r.Name,
				Form__r.Description__c,
				Version__c,
				Definition__c,
				Signing_Key__c
			FROM Form_Version__c
			WHERE Form__c = :formId AND Form__r.Status__c = 'Published' AND Form__r.Public__c = TRUE
			WITH SYSTEM_MODE
			ORDER BY Version__c DESC
			LIMIT 1
		];
		if (versions.isEmpty() || String.isBlank(versions[0].Signing_Key__c)) {
			return null;
		}
		return FormPublicPolicy.isPublic(FormRules.parse(versions[0].Definition__c))
			? versions[0]
			: null;
	}

	private static Form_Version__c versionOf(String versionId) {
		Id given = idOrNull(versionId);
		if (given == null || given.getSObjectType() != Form_Version__c.SObjectType) {
			return null;
		}
		List<Form_Version__c> versions = [
			SELECT Id, Form__c, Form__r.Status__c, Form__r.Public__c, Definition__c, Signing_Key__c
			FROM Form_Version__c
			WHERE Id = :given
			WITH SYSTEM_MODE
		];
		return versions.isEmpty() || String.isBlank(versions[0].Signing_Key__c)
			? null
			: versions[0];
	}

	private static Integer recentCount(Id formId) {
		Datetime hourAgo = Datetime.newInstance(now() - 60L * 60 * 1000);
		return [
			SELECT COUNT()
			FROM Form_Submission__c
			WHERE Form__c = :formId AND Source__c = :SOURCE_PUBLIC AND CreatedDate >= :hourAgo
			WITH SYSTEM_MODE
		];
	}

	/** `versionId:issuedAt:signature`, the signature an HMAC of the first two with the version's key. */
	@TestVisible
	private static String ticketFor(Form_Version__c version, Long issued) {
		String signed = version.Id + ':' + issued;
		Blob mac = Crypto.generateMac(
			'hmacSHA256',
			Blob.valueOf(signed),
			EncodingUtil.convertFromHex(version.Signing_Key__c)
		);
		return signed +
			':' +
			EncodingUtil.base64Encode(mac).replace('+', '-').replace('/', '_').remove('=');
	}

	private static Long now() {
		return Datetime.now().getTime() + clockShiftMs;
	}

	private static Id idOrNull(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			return Id.valueOf(value.trim());
		} catch (Exception notAnId) {
			return null;
		}
	}
}
