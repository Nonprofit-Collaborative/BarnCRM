/**
 * Portal sign-in and sessions (ADR-0185 `0185-portal-builder-off-platform-portal-api.md`,
 * decisions 4 to 7; canonical model 29PB2 to 29PB4).
 *
 * Salesforce sends and checks the one-time code, checks the authenticator code, and issues the
 * session token; only hashes are stored. Runs `without sharing` in system mode because it is
 * called by the integration user, which has no object access: the checks here are the security
 * boundary (Without Sharing Register, Portal). Every refusal is a short code from `RefusalException`,
 * never a record detail, and `start` answers the same for every email.
 */
public without sharing class PortalAuth {
	public static final String STAGE_CODE_SENT = 'Code Sent';
	public static final String STAGE_SECOND_FACTOR = 'Second Factor';
	public static final String STAGE_ENROLL = 'Enroll';
	public static final String STAGE_ACTIVE = 'Active';
	public static final String STAGE_ENDED = 'Ended';
	public static final String STATUS_ACTIVE = 'Active';
	public static final String MODE_ANY = 'Any Matching Person';
	public static final String FACTOR_OFF = 'Off';
	public static final String FACTOR_REQUIRED = 'Required';
	private static final String CONTEXT = 'PortalAuth';
	/** A session's last-used time is written at most once a minute, to save writes. */
	private static final Integer TOUCH_SECONDS = 60;

	/** A refusal the API returns as its message: a short code such as `not_signed_in`. */
	public class RefusalException extends Exception {
	}

	/** Captures the last code sent, in tests only, since the email cannot be read back. */
	@TestVisible
	private static String lastCodeForTest;
	/** Stands in for the clock in tests. */
	@TestVisible
	private static Datetime nowForTest;

	/** A verified session: the portal, the person's access and the session itself. */
	public class Session {
		public Portal__c portal;
		public Portal_Access__c access;
		public Portal_Session__c record;

		public Id personId() {
			return access.Person__c;
		}
	}

	private static Datetime now() {
		return nowForTest != null ? nowForTest : Datetime.now();
	}

	// ---- Settings -------------------------------------------------------------------------

	private static Portal_Settings__c settings() {
		Portal_Settings__c stored = Portal_Settings__c.getOrgDefaults();
		return stored == null ? new Portal_Settings__c() : stored;
	}

	private static Integer setting(Decimal stored, Integer fallback, Integer low, Integer high) {
		Integer value = stored == null ? fallback : stored.intValue();
		return Math.max(low, Math.min(high, value));
	}

	private static void requireEnabled() {
		if (settings().Enabled__c != true || ModuleManagerService.turnedOff().contains('portal')) {
			throw new RefusalException('portal_unavailable');
		}
	}

	// ---- Sign-in --------------------------------------------------------------------------

	/**
	 * Starts a sign-in: emails a code when the email belongs to someone allowed in, within the
	 * limits. Always returns a fresh challenge token, matched to a session only when a code was
	 * sent, so the answer never says who is on file (R-PST1).
	 */
	public static String start(String portalKey, String email) {
		requireEnabled();
		Portal__c portal = activePortal(portalKey);
		String address = email == null ? '' : email.trim().toLowerCase();
		if (!Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', address) || address.length() > 80) {
			throw new RefusalException('invalid_request');
		}
		String challenge = PortalTokens.newToken();
		try {
			Portal_Access__c access = accessFor(portal, address);
			if (access != null && withinLimits(portal, access)) {
				sendCode(portal, access, address, challenge);
			}
		} catch (Exception failed) {
			ErrorLogger.log(failed, CONTEXT + '.start', portal.Id);
		}
		return challenge;
	}

	/**
	 * Checks the emailed code. Returns `signedIn` with the session token, `secondFactor`, or
	 * `enroll` with a new authenticator secret, each keyed as the client expects.
	 */
	public static Map<String, Object> verifyCode(String challenge, String code) {
		requireEnabled();
		Portal_Session__c session = pending(challenge, new Set<String>{ STAGE_CODE_SENT });
		Portal_Access__c access = accessOf(session);
		Portal__c portal = portalOf(access);
		String expected = PortalTokens.hash(
			session.Token_Hash__c + ':' + (code == null ? '' : code.trim())
		);
		checkCodeWindow(session, access, PortalTokens.sameText(expected, session.Code_Hash__c));
		session.Code_Hash__c = null;
		Boolean enrolled = access.Second_Factor_Enrolled__c == true;
		if (portal.Second_Factor__c != FACTOR_OFF && enrolled) {
			session.Stage__c = STAGE_SECOND_FACTOR;
			update as system session;
			return new Map<String, Object>{ 'status' => 'secondFactor', 'challenge' => challenge };
		}
		if (portal.Second_Factor__c == FACTOR_REQUIRED) {
			access.Second_Factor_Secret__c = PortalTokens.newSecret();
			access.Second_Factor_Last_Step__c = null;
			update as system access;
			session.Stage__c = STAGE_ENROLL;
			update as system session;
			return enrolment(portal, access, challenge, 'enroll');
		}
		return activate(session, access, portal);
	}

	/** Checks the authenticator code after the emailed one, enrolling it when asked to. */
	public static Map<String, Object> verifySecondFactor(String challenge, String code) {
		requireEnabled();
		Portal_Session__c session = pending(
			challenge,
			new Set<String>{ STAGE_SECOND_FACTOR, STAGE_ENROLL }
		);
		Portal_Access__c access = accessOf(session);
		Portal__c portal = portalOf(access);
		Long step = freshStep(access, code);
		checkCodeWindow(session, access, step != null);
		access.Second_Factor_Last_Step__c = step;
		if (session.Stage__c == STAGE_ENROLL) {
			access.Second_Factor_Enrolled__c = true;
		}
		return activate(session, access, portal);
	}

	/** Ends the session the token belongs to. Quietly does nothing for an unknown token. */
	public static void signOut(String token) {
		List<Portal_Session__c> found = [
			SELECT Id, Stage__c
			FROM Portal_Session__c
			WHERE Token_Hash__c = :PortalTokens.hash(token) AND Stage__c = :STAGE_ACTIVE
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (!found.isEmpty()) {
			found[0].Stage__c = STAGE_ENDED;
			update as system found;
		}
	}

	// ---- Sessions -------------------------------------------------------------------------

	/** The verified session for a token, or `not_signed_in` (R-PS2). */
	public static Session resolve(String token) {
		requireEnabled();
		if (String.isBlank(token)) {
			throw new RefusalException('not_signed_in');
		}
		List<Portal_Session__c> found = [
			SELECT Id, Stage__c, Expires__c, Last_Used__c, Portal_Access__c
			FROM Portal_Session__c
			WHERE Token_Hash__c = :PortalTokens.hash(token)
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (found.isEmpty() || found[0].Stage__c != STAGE_ACTIVE) {
			throw new RefusalException('not_signed_in');
		}
		Portal_Session__c record = found[0];
		Portal_Access__c access = accessOf(record);
		Portal__c portal = portalOf(access);
		Integer idle = setting(settings().Idle_Minutes__c, 30, 5, 480);
		Datetime current = now();
		Boolean usable =
			record.Expires__c != null &&
			record.Expires__c > current &&
			record.Last_Used__c != null &&
			record.Last_Used__c.addMinutes(idle) > current &&
			access.Status__c == STATUS_ACTIVE &&
			access.Person__c != null &&
			!isLocked(access) &&
			portal.Status__c == STATUS_ACTIVE;
		if (!usable) {
			record.Stage__c = STAGE_ENDED;
			update as system record;
			throw new RefusalException('not_signed_in');
		}
		if (record.Last_Used__c.addSeconds(TOUCH_SECONDS) < current) {
			record.Last_Used__c = current;
			update as system record;
		}
		Session session = new Session();
		session.portal = portal;
		session.access = access;
		session.record = record;
		return session;
	}

	/** Starts enrolment for a signed-in person on a portal with an Optional second factor. */
	public static Map<String, Object> startEnrolment(Session session) {
		if (
			session.portal.Second_Factor__c == FACTOR_OFF ||
			session.access.Second_Factor_Enrolled__c == true
		) {
			throw new RefusalException('not_allowed');
		}
		session.access.Second_Factor_Secret__c = PortalTokens.newSecret();
		session.access.Second_Factor_Last_Step__c = null;
		update as system session.access;
		return enrolment(session.portal, session.access, null, 'enrolling');
	}

	/** Confirms enrolment with a first authenticator code. */
	public static void confirmEnrolment(Session session, String code) {
		Long step = freshStep(session.access, code);
		if (session.access.Second_Factor_Enrolled__c == true || step == null) {
			throw new RefusalException('code_invalid');
		}
		session.access.Second_Factor_Enrolled__c = true;
		session.access.Second_Factor_Last_Step__c = step;
		update as system session.access;
	}

	/**
	 * The step of an authenticator code that matches and is later than the last one accepted, or
	 * null: a code already used, or an earlier one, counts as wrong (R-PA3).
	 */
	@TestVisible
	private static Long freshStep(Portal_Access__c access, String code) {
		Long step = PortalTokens.matchedStep(access.Second_Factor_Secret__c, code, now());
		Decimal last = access.Second_Factor_Last_Step__c;
		return step == null || (last != null && step <= last.longValue()) ? null : step;
	}

	// ---- Helpers --------------------------------------------------------------------------

	/** The active portal with this key, or `portal_unavailable`. */
	public static Portal__c activePortal(String portalKey) {
		if (String.isBlank(portalKey)) {
			throw new RefusalException('invalid_request');
		}
		List<Portal__c> portals = [
			SELECT
				Id,
				Name,
				Key__c,
				Status__c,
				Access_Mode__c,
				Second_Factor__c,
				Session_Hours__c,
				Sender_Address__c,
				Template__c
			FROM Portal__c
			WHERE Key__c = :portalKey.trim()
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (portals.isEmpty() || portals[0].Status__c != STATUS_ACTIVE) {
			throw new RefusalException('portal_unavailable');
		}
		return portals[0];
	}

	/** The one active access this email signs in as, or null (none, several, or suspended). */
	private static Portal_Access__c accessFor(Portal__c portal, String address) {
		List<Portal_Access__c> accesses = [
			SELECT Id, Person__c, Status__c, Locked_Until__c, Failed_Attempts__c
			FROM Portal_Access__c
			WHERE Portal__c = :portal.Id AND Person__r.Email = :address
			WITH SYSTEM_MODE
			LIMIT 2
		];
		if (accesses.size() == 1) {
			Portal_Access__c access = accesses[0];
			return access.Status__c == STATUS_ACTIVE && !isLocked(access) ? access : null;
		}
		if (!accesses.isEmpty() || portal.Access_Mode__c != MODE_ANY) {
			return null;
		}
		List<Contact> people = [
			SELECT Id
			FROM Contact
			WHERE Email = :address
			WITH SYSTEM_MODE
			LIMIT 2
		];
		if (people.size() != 1) {
			return null;
		}
		Portal_Access__c created = new Portal_Access__c(
			Portal__c = portal.Id,
			Person__c = people[0].Id,
			Status__c = STATUS_ACTIVE,
			Failed_Attempts__c = 0
		);
		insert as system created;
		return created;
	}

	private static Boolean withinLimits(Portal__c portal, Portal_Access__c access) {
		Portal_Settings__c config = settings();
		Datetime hourAgo = now().addHours(-1);
		Integer mine = [
			SELECT COUNT()
			FROM Portal_Session__c
			WHERE Portal_Access__c = :access.Id AND CreatedDate >= :hourAgo
			WITH SYSTEM_MODE
		];
		if (mine >= setting(config.Code_Requests_Per_Hour__c, 5, 1, 20)) {
			return false;
		}
		Integer portalWide = [
			SELECT COUNT()
			FROM Portal_Session__c
			WHERE Portal_Access__r.Portal__c = :portal.Id AND CreatedDate >= :hourAgo
			WITH SYSTEM_MODE
		];
		return portalWide < setting(config.Emails_Per_Portal_Hour__c, 200, 10, 5000);
	}

	private static void sendCode(
		Portal__c portal,
		Portal_Access__c access,
		String address,
		String challenge
	) {
		String code = PortalTokens.newCode();
		String tokenHash = PortalTokens.hash(challenge);
		Integer minutes = setting(settings().Code_Minutes__c, 10, 2, 30);
		insert as system new Portal_Session__c(
			Portal_Access__c = access.Id,
			Stage__c = STAGE_CODE_SENT,
			Token_Hash__c = tokenHash,
			Code_Hash__c = PortalTokens.hash(tokenHash + ':' + code),
			Code_Expires__c = now().addMinutes(minutes),
			Attempts__c = 0
		);
		if (Test.isRunningTest()) {
			lastCodeForTest = code;
		}
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setToAddresses(new List<String>{ address });
		message.setSaveAsActivity(false);
		String subject = BarnHelp.text(
			'Portal',
			'Portal_Code_Email_Subject',
			new List<Object>{ portal.Name }
		);
		String body = BarnHelp.text(
			'Portal',
			'Portal_Code_Email_Body',
			new List<Object>{ portal.Name, code, minutes }
		);
		message.setSubject(String.isBlank(subject) ? portal.Name : subject);
		message.setPlainTextBody(String.isBlank(body) ? code : body);
		Id sender = senderId(portal.Sender_Address__c);
		if (sender != null) {
			message.setOrgWideEmailAddressId(sender);
		}
		Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message }, false);
	}

	private static Id senderId(String address) {
		if (String.isBlank(address)) {
			return null;
		}
		List<OrgWideEmailAddress> found = [
			SELECT Id
			FROM OrgWideEmailAddress
			WHERE Address = :address
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return found.isEmpty() ? null : found[0].Id;
	}

	private static Portal_Session__c pending(String challenge, Set<String> stages) {
		if (String.isBlank(challenge)) {
			throw new RefusalException('code_invalid');
		}
		List<Portal_Session__c> found = [
			SELECT
				Id,
				Stage__c,
				Token_Hash__c,
				Code_Hash__c,
				Code_Expires__c,
				Attempts__c,
				Portal_Access__c
			FROM Portal_Session__c
			WHERE Token_Hash__c = :PortalTokens.hash(challenge)
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (found.isEmpty() || !stages.contains(found[0].Stage__c)) {
			throw new RefusalException('code_invalid');
		}
		return found[0];
	}

	private static Portal_Access__c accessOf(Portal_Session__c session) {
		Portal_Access__c access = [
			SELECT
				Id,
				Portal__c,
				Person__c,
				Person__r.Email,
				Status__c,
				Failed_Attempts__c,
				Locked_Until__c,
				Second_Factor_Enrolled__c,
				Second_Factor_Secret__c,
				Second_Factor_Last_Step__c
			FROM Portal_Access__c
			WHERE Id = :session.Portal_Access__c
			WITH SYSTEM_MODE
		];
		return access;
	}

	private static Portal__c portalOf(Portal_Access__c access) {
		Portal__c portal = [
			SELECT
				Id,
				Name,
				Key__c,
				Status__c,
				Access_Mode__c,
				Second_Factor__c,
				Session_Hours__c,
				Sender_Address__c,
				Template__c
			FROM Portal__c
			WHERE Id = :access.Portal__c
			WITH SYSTEM_MODE
		];
		if (portal.Status__c != STATUS_ACTIVE) {
			throw new RefusalException('portal_unavailable');
		}
		return portal;
	}

	private static Boolean isLocked(Portal_Access__c access) {
		return access.Locked_Until__c != null && access.Locked_Until__c > now();
	}

	/**
	 * Refuses a code that is wrong, expired, or for a person who cannot sign in now (R-PST1). A
	 * wrong code always answers `code_invalid`, whatever the reason, so the answer is the same as
	 * for an address not on file; `locked` and `code_expired` are told only to someone who gave
	 * the right code, who already holds the inbox. Only a wrong code in time counts toward the
	 * lockout (R-PA1).
	 */
	private static void checkCodeWindow(
		Portal_Session__c session,
		Portal_Access__c access,
		Boolean correct
	) {
		Boolean expired = session.Code_Expires__c == null || session.Code_Expires__c < now();
		if (expired) {
			session.Stage__c = STAGE_ENDED;
			update as system session;
		}
		if (access.Status__c != STATUS_ACTIVE || access.Person__c == null) {
			throw new RefusalException('code_invalid');
		}
		if (!correct && !expired && !isLocked(access)) {
			fail(session, access);
		}
		if (!correct) {
			throw new RefusalException('code_invalid');
		}
		if (isLocked(access)) {
			throw new RefusalException('locked');
		}
		if (expired) {
			throw new RefusalException('code_expired');
		}
	}

	/** Counts a wrong code against the challenge and the person, then refuses (R-PA1). */
	private static void fail(Portal_Session__c session, Portal_Access__c access) {
		Portal_Settings__c config = settings();
		session.Attempts__c = (session.Attempts__c == null ? 0 : session.Attempts__c) + 1;
		if (session.Attempts__c >= setting(config.Attempts_Per_Code__c, 5, 1, 10)) {
			session.Stage__c = STAGE_ENDED;
		}
		access.Failed_Attempts__c =
			(access.Failed_Attempts__c == null ? 0 : access.Failed_Attempts__c) + 1;
		if (access.Failed_Attempts__c >= setting(config.Failures_Before_Lockout__c, 10, 3, 50)) {
			access.Locked_Until__c = now()
				.addMinutes(setting(config.Lockout_Minutes__c, 30, 5, 1440));
			access.Failed_Attempts__c = 0;
			session.Stage__c = STAGE_ENDED;
		}
		update as system session;
		update as system access;
		throw new RefusalException('code_invalid');
	}

	private static Map<String, Object> activate(
		Portal_Session__c session,
		Portal_Access__c access,
		Portal__c portal
	) {
		String token = PortalTokens.newToken();
		Datetime current = now();
		Integer hours = setting(portal.Session_Hours__c, 8, 1, 720);
		session.Stage__c = STAGE_ACTIVE;
		session.Token_Hash__c = PortalTokens.hash(token);
		session.Code_Hash__c = null;
		session.Expires__c = current.addHours(hours);
		session.Last_Used__c = current;
		access.Failed_Attempts__c = 0;
		access.Last_Sign_In__c = current;
		update as system session;
		update as system access;
		return new Map<String, Object>{
			'status' => 'signedIn',
			'session' => token,
			'expires' => session.Expires__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
		};
	}

	private static Map<String, Object> enrolment(
		Portal__c portal,
		Portal_Access__c access,
		String challenge,
		String status
	) {
		String account = access.Person__r == null ? portal.Key__c : access.Person__r.Email;
		Map<String, Object> result = new Map<String, Object>{
			'status' => status,
			'secret' => access.Second_Factor_Secret__c,
			'uri' => PortalTokens.enrolmentUri(portal.Name, account, access.Second_Factor_Secret__c)
		};
		if (challenge != null) {
			result.put('challenge', challenge);
		}
		return result;
	}
}
