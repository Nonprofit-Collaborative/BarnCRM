/**
 * The public intake: a form loaded and answers stored for someone with no BarnCRM login, on a
 * Salesforce Site or through an API caller (canonical model R-FS5, R-FS7; ADR-0184 public forms on
 * a Salesforce Site, decisions 1, 2, 5, 7 and 11).
 *
 * The one `without sharing` class in Forms, and deliberately narrow: it reads only the form and
 * version asked for (published and public), counts the form's public submissions and drafts in
 * the last hour, inserts one Form Submission with Status Received and its files, and keeps and
 * finds answers saved for later by the hash of an emailed token. It never reads a person, an
 * organization or any other record, and never returns a record identifier, so nothing about who
 * is on file can be learned from it. The answers are processed later as a staff user
 * (`FormPublicProcessor`), or at once when the caller is a signed-in user.
 *
 * Plain values in and out (plan 9.9): `FormPublicController` (a Site page) and `FormPublicRest`
 * (an integration user, D-187) are thin wrappers.
 */
public without sharing class FormIntakeService {
	public static final String RECEIVED = 'Received';
	public static final String SAVED = 'Saved';
	public static final String INVALID = 'Invalid';
	public static final String RETRY = 'Retry';
	public static final String EXPIRED = 'Expired';
	public static final String BUSY = 'Busy';
	public static final String CLOSED = 'Closed';
	public static final String FAILED = 'Failed';
	public static final String SOURCE_PUBLIC = 'Public';
	/** The problem key for the save-for-later email address. */
	public static final String SAVE_KEY = 'saveForLater';
	private static final Long TICKET_LIFE_MS = 24L * 60 * 60 * 1000;
	private static final Long DAY_MS = 24L * 60 * 60 * 1000;
	private static final Integer DRAFT_LENGTH = 131072;
	/** Save-for-later links one address may be sent for one form in an hour (R-FS7). */
	@TestVisible
	private static final Integer LINKS_PER_ADDRESS_HOUR = 3;
	/** Save-for-later links one form may send in an hour, at most (R-FS7). */
	@TestVisible
	private static final Integer LINKS_PER_FORM_HOUR = 100;
	private static final String CONTEXT = 'FormIntakeService';

	/** Set by tests to move the clock: milliseconds added to now. */
	@TestVisible
	private static Long clockShiftMs = 0;

	/** Set by tests to act as a Site guest user, whose submissions wait for processing. */
	@TestVisible
	private static Boolean actAsGuest = false;

	/** The last link emailed, for tests: the token is never stored. */
	@TestVisible
	private static String lastLink;

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
		/** True when the answers may be saved for later from an emailed link. */
		@AuraEnabled
		public Boolean canSave;
		/** The answers saved for later, as JSON, when the form was resumed. */
		@AuraEnabled
		public String answers;
		/** The step saved answers were on, when the form was resumed. */
		@AuraEnabled
		public Integer step;
	}

	/** What became of the answers, and nothing about any record. */
	public class Receipt {
		/** Received, Saved, Invalid, Retry, Expired, Busy, Closed or Failed. */
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
		return version == null ? null : viewOf(version);
	}

	/**
	 * A module's public page for one of its records, as JSON, or null when no module publishes
	 * it (ADR-0190 public event pages, decisions 1, 4 and 6). The module reads its own record;
	 * this class only checks that the form the page names is published and public, and when it
	 * is not, the page shows no form and the module's offline message.
	 */
	public static String publicPage(String recordId) {
		Id given = idOrNull(recordId);
		Map<String, Object> page = given == null ? null : PublicPageExtensions.page(given);
		if (page == null) {
			return null;
		}
		Object offline = page.remove('offlineMessage');
		Object named = page.get('formId');
		Id formId = named == null ? null : idOrNull(String.valueOf(named));
		Boolean formIsPublic =
			formId != null &&
			formId.getSObjectType() == Form__c.SObjectType &&
			latestPublicVersion(formId) != null;
		if (!formIsPublic) {
			page.put('formId', null);
			if (page.get('registration') != 'None') {
				page.put('registration', 'None');
				page.put('message', offline);
			}
		}
		return JSON.serialize(page);
	}

	/** A module's public list of one kind of page, as JSON, or null when none offers it. */
	public static String publicList(String kind) {
		Map<String, Object> listed = PublicPageExtensions.listPage(kind);
		return listed == null ? null : JSON.serialize(listed);
	}

	/**
	 * The form with the answers saved behind an emailed link, on the version they answer (R-FS7),
	 * or null when the link is unknown or expired or the form is no longer public.
	 */
	public static PublicForm resume(Id formId, String token) {
		Form_Draft__c draft = draftFor(token);
		if (draft == null || draft.Form__c != formId || draft.Form_Version__c == null) {
			return null;
		}
		Form_Version__c version = versionOf(draft.Form_Version__c);
		if (version == null || !isOpen(version)) {
			return null;
		}
		PublicForm view = viewOf(version);
		view.answers = draft.Answers__c;
		view.step = draft.Step__c == null ? 0 : draft.Step__c.intValue();
		return view;
	}

	private static PublicForm viewOf(Form_Version__c version) {
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		PublicForm view = new PublicForm();
		view.formId = version.Form__c;
		view.name = version.Form__r.Name;
		view.description = version.Form__r.Description__c;
		view.version = version.Version__c.intValue();
		view.definition = FormPublicPolicy.publicCopy(definition);
		view.ticket = ticketFor(version, now());
		view.canSave = FormPublicPolicy.canSave(definition);
		return view;
	}

	/** Stores the answers with no files (C-42b callers). */
	public static Receipt submit(
		String ticket,
		Map<String, Object> answers,
		String trap,
		String contextRecordId
	) {
		return submit(ticket, answers, trap, contextRecordId, null, null);
	}

	/**
	 * Stores the answers and their files after the spam checks and the answer checks (R-FS5,
	 * R-FS7), in that order, and forgets the saved answers they finish.
	 *
	 * @param ticket the ticket the form was loaded with
	 * @param answers the answers by field key
	 * @param trap the hidden question's answer: anything in it means a script filled the form
	 * @param contextRecordId the record the form was filled from, or blank
	 * @param files the files for file questions, `{ key: { name, data } }`, or null
	 * @param resumeToken the emailed token the form was resumed with, or blank
	 */
	public static Receipt submit(
		String ticket,
		Map<String, Object> answers,
		String trap,
		String contextRecordId,
		Map<String, Object> files,
		String resumeToken
	) {
		Receipt receipt = new Receipt();
		if (String.isNotBlank(trap)) {
			// Told it was received, so a script learns nothing; nothing is stored.
			receipt.status = RECEIVED;
			return receipt;
		}
		Form_Version__c version = checked(ticket, receipt);
		if (version == null) {
			return receipt;
		}
		String claim = claimPart(contextRecordId);
		Id contextId = idOrNull(idPart(contextRecordId));
		if (
			(String.isNotBlank(contextRecordId) && contextId == null) ||
			(contextId != null && !claimAllowed(version.Form__c, contextId, claim))
		) {
			receipt.status = CLOSED;
			return receipt;
		}
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		Map<String, Object> given = answers == null ? new Map<String, Object>() : answers;
		receipt.problems = FormRules.checkAll(definition, given);
		Map<String, Object> counted = FormRules.countedAnswers(definition, given);
		List<FormFiles.Upload> uploads = receipt.problems.isEmpty()
			? FormFiles.read(definition, counted, files, receipt.problems)
			: null;
		if (!receipt.problems.isEmpty()) {
			receipt.status = INVALID;
			return receipt;
		}
		Form_Submission__c submission = new Form_Submission__c(
			Form__c = version.Form__c,
			Form_Version__c = version.Id,
			Status__c = RECEIVED,
			Source__c = SOURCE_PUBLIC,
			Answers__c = JSON.serialize(counted),
			Context_Record_Id__c = contextId
		);
		Database.insert(submission, AccessLevel.SYSTEM_MODE);
		FormFiles.keep(submission.Id, uploads, true);
		forget(resumeToken);
		processNowIfSignedIn(submission.Id);
		receipt.status = RECEIVED;
		receipt.message = FormPublicPolicy.confirmation(definition);
		return receipt;
	}

	/**
	 * Saves the answers so far and emails a link to finish later (R-FS7), after the same spam
	 * checks as sending. The link's token is random, goes only into the email, and is stored as
	 * its SHA-256 hash; the link opens the same version until it expires. Files are not saved.
	 *
	 * @param email where the link goes; it is not stored
	 * @param step the step the person is on, where the resumed form opens
	 */
	public static Receipt saveDraft(
		String ticket,
		Map<String, Object> answers,
		String trap,
		String email,
		Integer step
	) {
		Receipt receipt = new Receipt();
		if (String.isNotBlank(trap)) {
			receipt.status = SAVED;
			return receipt;
		}
		Form_Version__c version = checked(ticket, receipt);
		if (version == null) {
			return receipt;
		}
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		String base = resumeBase();
		if (!FormPublicPolicy.canSave(definition) || base == null) {
			receipt.status = CLOSED;
			return receipt;
		}
		String address = email == null ? '' : email.trim();
		// Not named `saved`: Apex names ignore case, and that would hide the SAVED status.
		String answersJson = JSON.serialize(withoutFiles(definition, answers));
		String problem = FormRules.checkAnswer(
			new Map<String, Object>{ 'type' => 'email', 'required' => true },
			address
		);
		problem = problem == null && answersJson.length() > DRAFT_LENGTH ? 'tooLong' : problem;
		if (problem != null) {
			receipt.status = INVALID;
			receipt.problems.put(SAVE_KEY, problem);
			return receipt;
		}
		String addressKey = addressKeyOf(version, address);
		if (tooManyLinks(version, definition, addressKey)) {
			receipt.status = BUSY;
			return receipt;
		}
		String token = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
		Integer days = FormPublicPolicy.resumeDays(definition);
		Form_Draft__c draft = new Form_Draft__c(
			Form__c = version.Form__c,
			Form_Version__c = version.Id,
			Token_Hash__c = hashOf(token),
			Address_Key__c = addressKey,
			Expires__c = Datetime.newInstance(now() + days * DAY_MS),
			Answers__c = answersJson,
			Step__c = step == null || step < 0 ? 0 : step
		);
		Database.insert(draft, AccessLevel.SYSTEM_MODE);
		lastLink = base + '/FormsPublic?form=' + version.Form__c + '&resume=' + token;
		try {
			Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
			mail.setToAddresses(new List<String>{ address });
			mail.setSubject(
				BarnHelp.text(
					'Forms',
					'Forms_Resume_EmailSubject',
					new List<Object>{ version.Form__r.Name }
				)
			);
			mail.setPlainTextBody(
				BarnHelp.text(
					'Forms',
					'Forms_Resume_EmailBody',
					new List<Object>{ version.Form__r.Name, lastLink, days }
				)
			);
			mail.setSaveAsActivity(false);
			Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
		} catch (Exception e) {
			// No email, no way back to the draft: it is removed and the person is told.
			ErrorLogger.log(e, CONTEXT + '.saveDraft', version.Form__c);
			Database.delete(draft, AccessLevel.SYSTEM_MODE);
			receipt.status = FAILED;
			return receipt;
		}
		receipt.status = SAVED;
		return receipt;
	}

	/** The answers that count, without file answers: files are chosen again on resuming. */
	private static Map<String, Object> withoutFiles(
		Map<String, Object> definition,
		Map<String, Object> answers
	) {
		Map<String, Object> counted = FormRules.countedAnswers(
			definition,
			answers == null ? new Map<String, Object>() : answers
		);
		for (Map<String, Object> field : FormRules.allFields(definition)) {
			if (field.get('type') == 'file') {
				counted.remove(String.valueOf(field.get('key')));
			}
		}
		return counted;
	}

	/**
	 * The version a ticket names once the spam checks pass (R-FS5), or null with the receipt's
	 * status saying why: Expired, Closed, Retry or Busy.
	 */
	private static Form_Version__c checked(String ticket, Receipt receipt) {
		List<String> parts = String.isBlank(ticket) ? new List<String>() : ticket.split(':');
		Form_Version__c version = parts.size() == 3 ? versionOf(parts[0]) : null;
		if (version == null || !isOpen(version)) {
			receipt.status = version != null ? CLOSED : EXPIRED;
			return null;
		}
		Long issued = parts[1].isNumeric() ? Long.valueOf(parts[1]) : -1;
		Long age = now() - issued;
		// equals, not ==: Apex compares text with == ignoring case, and a signature must match exactly.
		if (
			!ticketFor(version, issued).equals(ticket) ||
			issued < 0 ||
			age < 0 ||
			age > TICKET_LIFE_MS
		) {
			receipt.status = EXPIRED;
			return null;
		}
		Map<String, Object> definition = FormRules.parse(version.Definition__c);
		if (!FormPublicPolicy.isPublic(definition)) {
			receipt.status = CLOSED;
		} else if (age < FormPublicPolicy.minSeconds(definition) * 1000L) {
			receipt.status = RETRY;
		} else if (recentCount(version.Form__c) >= FormPublicPolicy.hourlyLimit(definition)) {
			receipt.status = BUSY;
		}
		return receipt.status == null ? version : null;
	}

	private static Boolean isOpen(Form_Version__c version) {
		return version.Form__r.Public__c && version.Form__r.Status__c == 'Published';
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

	/**
	 * The signed claim for a link that names a record (EV-18): an HMAC-SHA256 of the form and the
	 * record, with the signing key of the form's current public version (the key of decision 5,
	 * no new secret). Null when the form is not public.
	 */
	public static String claimFor(Id formId, Id contextRecordId) {
		Form_Version__c version = contextRecordId == null ? null : latestPublicVersion(formId);
		if (version == null) {
			return null;
		}
		Blob mac = Crypto.generateMac(
			'hmacSHA256',
			Blob.valueOf('claim:' + formId + ':' + contextRecordId),
			EncodingUtil.convertFromHex(version.Signing_Key__c)
		);
		return EncodingUtil.base64Encode(mac).replace('+', '-').replace('/', '_').remove('=');
	}

	/**
	 * Whether a public submission may use this record. A record whose module asks for a signed
	 * claim (`FormAttachmentExtensions.signedClaimRequired`) needs the right signature and the
	 * module's own say that this form is the one attached to it, which for an attendee means the
	 * attendee attended. Any other record needs nothing more.
	 */
	private static Boolean claimAllowed(Id formId, Id contextId, String claim) {
		if (!FormAttachmentExtensions.signedClaimRequired(contextId)) {
			return true;
		}
		String expected = claimFor(formId, contextId);
		return expected != null &&
			String.isNotBlank(claim) &&
			expected.equals(claim) &&
			FormAttachmentExtensions.formFor(contextId) == formId;
	}

	/** The record id of `recordId` or `recordId.signature`. */
	private static String idPart(String value) {
		return value == null ? null : value.substringBefore('.');
	}

	private static String claimPart(String value) {
		return value == null || !value.contains('.') ? null : value.substringAfter('.');
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
			SELECT
				Id,
				Form__c,
				Form__r.Name,
				Form__r.Description__c,
				Form__r.Status__c,
				Form__r.Public__c,
				Version__c,
				Definition__c,
				Signing_Key__c
			FROM Form_Version__c
			WHERE Id = :given
			WITH SYSTEM_MODE
		];
		return versions.isEmpty() || String.isBlank(versions[0].Signing_Key__c)
			? null
			: versions[0];
	}

	/** Public submissions and saved drafts in the last hour: both count toward the limit. */
	private static Integer recentCount(Id formId) {
		Datetime hourAgo = Datetime.newInstance(now() - 60L * 60 * 1000);
		return [
				SELECT COUNT()
				FROM Form_Submission__c
				WHERE Form__c = :formId AND Source__c = :SOURCE_PUBLIC AND CreatedDate >= :hourAgo
				WITH SYSTEM_MODE
			] +
			[
				SELECT COUNT()
				FROM Form_Draft__c
				WHERE Form__c = :formId AND CreatedDate >= :hourAgo
				WITH SYSTEM_MODE
			];
	}

	/**
	 * Whether another emailed link would pass a cap (R-FS7): 3 an hour to one address for one
	 * form, and 100 an hour for one form, or the form's hourly limit when that is lower. Links are
	 * counted by their drafts, so a link already used to send the form no longer counts.
	 */
	private static Boolean tooManyLinks(
		Form_Version__c version,
		Map<String, Object> definition,
		String addressKey
	) {
		Datetime hourAgo = Datetime.newInstance(now() - 60L * 60 * 1000);
		Integer formCap = Math.min(FormPublicPolicy.hourlyLimit(definition), LINKS_PER_FORM_HOUR);
		Integer toAddress = [
			SELECT COUNT()
			FROM Form_Draft__c
			WHERE
				Form__c = :version.Form__c
				AND Address_Key__c = :addressKey
				AND CreatedDate >= :hourAgo
			WITH SYSTEM_MODE
		];
		if (toAddress >= LINKS_PER_ADDRESS_HOUR) {
			return true;
		}
		return [
				SELECT COUNT()
				FROM Form_Draft__c
				WHERE Form__c = :version.Form__c AND CreatedDate >= :hourAgo
				WITH SYSTEM_MODE
			] >= formCap;
	}

	/** The address as a keyed hash: links are counted per address, which is never stored. */
	@TestVisible
	private static String addressKeyOf(Form_Version__c version, String address) {
		return EncodingUtil.convertToHex(
			Crypto.generateMac(
				'hmacSHA256',
				Blob.valueOf(address.trim().toLowerCase()),
				EncodingUtil.convertFromHex(version.Signing_Key__c)
			)
		);
	}

	private static Form_Draft__c draftFor(String token) {
		if (String.isBlank(token)) {
			return null;
		}
		Datetime current = Datetime.newInstance(now());
		String hash = hashOf(token.trim());
		List<Form_Draft__c> drafts = [
			SELECT Id, Form__c, Form_Version__c, Answers__c, Step__c
			FROM Form_Draft__c
			WHERE Token_Hash__c = :hash AND Expires__c > :current
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return drafts.isEmpty() ? null : drafts[0];
	}

	/** Deletes the saved answers a token found, once they are sent. */
	private static void forget(String token) {
		Form_Draft__c draft = draftFor(token);
		if (draft != null) {
			Database.delete(draft, AccessLevel.SYSTEM_MODE);
		}
	}

	@TestVisible
	private static String hashOf(String token) {
		return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(token)));
	}

	/** Where an emailed link points: this Site, or the first active Site for an API caller. */
	private static String resumeBase() {
		String base = Site.getBaseSecureUrl();
		if (String.isBlank(base)) {
			List<String> urls = FormsSites.activeSiteUrls();
			base = urls.isEmpty() ? null : urls[0];
		}
		return base == null ? null : base.removeEnd('/');
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
