/**
 * Webhooks in and data sent back (CN-04, D-216; canonical model R-CR10, R-CR11; design Sections
 * 3.3 and 3.3a; security review F4, F7, F13). The rules of the `webhook` trigger and its reply,
 * the token (made here, kept only as its hash), the receiver addresses on the org's Sites, the
 * Health Check of guest access, and the one check every address read from data passes before a
 * callout: fetch back and callback addresses (F4).
 *
 * The receiver itself is `ConnectorWebhookRest`; its reads and its one write are in
 * `ConnectorRunStore`. Nothing here takes or returns a token except `newToken`, which shows it
 * once.
 */
public with sharing class ConnectorWebhooks {
	public static final String HEADER = 'X-BarnCRM-Token';
	public static final String RECEIVER_PATH = '/services/apexrest/barncrm/connector/v1/hook';
	public static final String WEBHOOK = 'Webhook';
	public static final String GUEST_SET = 'Connector_Webhook_Guest';
	public static final String FIX_GUEST = 'connector_webhook_guest';
	public static final Integer MAX_REPLY = 4000;
	public static final Integer MAX_ECHO = 1000;
	public static final String DEFAULT_REPLY = '{"received": true, "reference": "{reference}"}';
	private static final Pattern TOKEN_SHAPE = Pattern.compile('[0-9a-f]{64}');
	private static final Pattern FIELD_NAME = Pattern.compile('[A-Za-z0-9_.-]{1,100}');
	private static final Pattern UNSAFE_QUERY = Pattern.compile('.*[\\s\\\\@#].*');

	/** Sites a test reports, since a test cannot create one. */
	@TestVisible
	private static List<SiteInfo> testSites;
	/** Named Credential addresses a test reports, by name. */
	@TestVisible
	private static Map<String, String> testEndpoints;

	/** What the receiver answers. A refused post has no body. */
	public class Reply {
		public Integer status;
		public String body;
		public String contentType;

		public Reply(Integer status, String body, String contentType) {
			this.status = status;
			this.body = body;
			this.contentType = contentType;
		}
	}

	/** One active Salesforce Site: its guest user and secure address. */
	public class SiteInfo {
		public String name;
		public Id guestUserId;
		public String url;
	}

	/** The Webhook card of a recipe: never the token, which only `newToken` shows, once. */
	public class View {
		@AuraEnabled
		public Boolean hasToken;
		@AuraEnabled
		public String token;
		@AuraEnabled
		public Integer hourlyCap;
		@AuraEnabled
		public String header = ConnectorWebhooks.HEADER;
		@AuraEnabled
		public List<String> addresses = new List<String>();
	}

	// ---------------------------------------------------------------------------------------
	// The trigger and its reply (R-CR1, R-CR10)
	// ---------------------------------------------------------------------------------------

	/** What is wrong with a `webhook` trigger, in words, or null. */
	public static String triggerProblem(Map<String, Object> starter) {
		String eventId = text(starter.get('eventId'));
		Map<String, Object> reply = ConnectorRecipeDocument.mapOf(starter.get('reply'));
		Object status = reply.get('status');
		String body = text(reply.get('body'));
		String challenge = text(reply.get('challenge'));
		Boolean bad =
			(String.isNotBlank(eventId) && !ConnectorRecipeDocument.isPath(eventId)) ||
			(status != null &&
			status != 200 &&
			status != 202) ||
			body.length() > MAX_REPLY ||
			(String.isNotBlank(body) && !isJson(body)) ||
			(String.isNotBlank(challenge) &&
			(!FIELD_NAME.matcher(challenge).matches() || challenge.equalsIgnoreCase('token')));
		return bad ? BarnHelp.text('Connector', 'Connector_Recipe_ErrorWebhook') : null;
	}

	private static Boolean isJson(String body) {
		try {
			JSON.deserializeUntyped(body);
			return true;
		} catch (Exception unreadable) {
			return false;
		}
	}

	/**
	 * The reply to a stored post (design Section 3.3a): the challenge value as plain text when
	 * the trigger names one and the post carries it, else the fixed body with `{reference}`
	 * filled. Never a record or a step's result: nothing has run yet.
	 */
	public static Reply reply(Map<String, Object> starter, Object payload, Map<String, String> params, String ref) {
		Map<String, Object> settings = ConnectorRecipeDocument.mapOf(starter.get('reply'));
		String challenge = text(settings.get('challenge'));
		if (String.isNotBlank(challenge)) {
			Object value = ConnectorRecipeDocument.mapOf(payload).get(challenge);
			if (value == null && params != null) {
				value = params.get(challenge);
			}
			if (
				(value instanceof String ||
				value instanceof Integer ||
				value instanceof Long ||
				value instanceof Decimal) &&
				String.isNotBlank(String.valueOf(value)) &&
				String.valueOf(value).length() <= MAX_ECHO
			) {
				return new Reply(200, String.valueOf(value), 'text/plain');
			}
		}
		Integer status = settings.get('status') == 200 ? 200 : 202;
		String body = String.isBlank(text(settings.get('body'))) ? DEFAULT_REPLY : text(settings.get('body'));
		return new Reply(status, body.replace('{reference}', ref == null ? '' : ref), 'application/json');
	}

	/** The SHA-256 of a token in lower-case hexadecimal, or null when it is not 64 hex digits. */
	public static String hashOf(String token) {
		String given = token == null ? '' : token.trim().toLowerCase();
		if (!TOKEN_SHAPE.matcher(given).matches()) {
			return null;
		}
		return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(given)));
	}

	/** An opaque run reference: 20 random hexadecimal characters. */
	public static String newReference() {
		return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(20);
	}

	/** Webhook Hourly Cap, 1 to 5,000; blank or out of range is 500 (R-CR10). */
	public static Integer hourlyCap(Connector_Recipe__c recipe) {
		Decimal value = recipe?.Webhook_Hourly_Cap__c;
		return value == null || value < 1 || value > 5000 ? 500 : value.intValue();
	}

	// ---------------------------------------------------------------------------------------
	// Addresses read from data: fetch back and callbacks (R-CR11, F4)
	// ---------------------------------------------------------------------------------------

	/**
	 * The path and query to append to `callout:<connection>` for an address read from a post or
	 * a response. Refused unless it is `https`, has no user information or fragment, has the
	 * connection's exact host and port and starts with the connection's own path; the posted
	 * address is never the endpoint. Throws a refusal written for a person.
	 */
	public static String calloutAddress(String posted, String connection) {
		String given = posted == null ? '' : posted.trim();
		String home = endpointOf(connection);
		Url url;
		Url base;
		try {
			url = new Url(given);
			base = new Url(home);
		} catch (Exception malformed) {
			throw refusedAddress();
		}
		String basePath = base.getPath() == null ? '' : base.getPath().removeEnd('/');
		String path = url.getPath() == null ? '' : url.getPath();
		Boolean underBase = String.isBlank(basePath) || path == basePath || path.startsWith(basePath + '/');
		if (
			!given.toLowerCase().startsWith('https://') ||
			url.getProtocol() != 'https' ||
			base.getProtocol() != 'https' ||
			String.isNotBlank(url.getUserInfo()) ||
			String.isNotBlank(url.getRef()) ||
			String.isBlank(url.getHost()) ||
			!url.getHost().equalsIgnoreCase(base.getHost()) ||
			portOf(url) != portOf(base) ||
			!underBase ||
			given.contains('{!')
		) {
			throw refusedAddress();
		}
		String rest = path.substring(basePath.length());
		rest = String.isBlank(rest) ? '/' : rest;
		String query = url.getQuery();
		if (
			ConnectorRecipeDocument.pathProblem(rest) ||
			(String.isNotBlank(query) && (UNSAFE_QUERY.matcher(query).matches() || query.contains('{!')))
		) {
			throw refusedAddress();
		}
		return rest + (String.isBlank(query) ? '' : '?' + query);
	}

	private static Integer portOf(Url address) {
		return address.getPort() == -1 ? address.getDefaultPort() : address.getPort();
	}

	private static ConnectorRecipeDocument.DocumentException refusedAddress() {
		return new ConnectorRecipeDocument.DocumentException(
			BarnHelp.text('Connector', 'Connector_Run_ErrorDataAddress')
		);
	}

	/**
	 * A connection's Named Credential address, read in system mode, server side only (F5), once
	 * per transaction: a For Each may fetch back an address for every item.
	 */
	private static String endpointOf(String connection) {
		if (testEndpoints != null) {
			return testEndpoints.get(connection);
		}
		if (!endpoints.containsKey(connection)) {
			String found;
			for (NamedCredential named : [
				SELECT Endpoint
				FROM NamedCredential
				WHERE DeveloperName = :connection AND NamespacePrefix = NULL
				WITH SYSTEM_MODE
				LIMIT 1
			]) {
				found = named.Endpoint;
			}
			endpoints.put(connection, found);
		}
		return endpoints.get(connection);
	}

	private static Map<String, String> endpoints = new Map<String, String>();

	// ---------------------------------------------------------------------------------------
	// The Webhook card: addresses, token, hourly cap (R-CR3, R-CR10)
	// ---------------------------------------------------------------------------------------

	/** The recipe's Webhook card, for Connector viewers and admins. */
	public static View view(Id recipeId) {
		ConnectorRecipes.requireViewer();
		Connector_Recipe__c row = recipe(recipeId);
		View result = new View();
		result.hasToken = String.isNotBlank(row.Webhook_Token_Hash__c);
		result.hourlyCap = hourlyCap(row);
		for (SiteInfo site : sites()) {
			if (site.url != null) {
				result.addresses.add(site.url + RECEIVER_PATH);
			}
		}
		return result;
	}

	/**
	 * A new token for the recipe, replacing any earlier one: 256 random bits as 64 hexadecimal
	 * characters, returned this once and stored only as its hash.
	 */
	public static View newToken(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		String token = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
		Database.update(
			new Connector_Recipe__c(Id = row.Id, Webhook_Token_Hash__c = hashOf(token)),
			AccessLevel.USER_MODE
		);
		View result = view(row.Id);
		result.token = token;
		return result;
	}

	/** Saves Webhook Hourly Cap, 1 to 5,000. */
	public static View saveCap(Id recipeId, Integer cap) {
		ConnectorConnections.requireManager();
		if (cap == null || cap < 1 || cap > 5000) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Webhook_ErrorCap'));
		}
		Connector_Recipe__c row = recipe(recipeId);
		Database.update(new Connector_Recipe__c(Id = row.Id, Webhook_Hourly_Cap__c = cap), AccessLevel.USER_MODE);
		return view(row.Id);
	}

	private static Connector_Recipe__c recipe(Id recipeId) {
		List<Connector_Recipe__c> rows = [
			SELECT Id, Webhook_Token_Hash__c, Webhook_Hourly_Cap__c
			FROM Connector_Recipe__c
			WHERE Id = :recipeId
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty()) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Recipe_ErrorGone'));
		}
		return rows[0];
	}

	// ---------------------------------------------------------------------------------------
	// Sites and guest access (Health Check)
	// ---------------------------------------------------------------------------------------

	/**
	 * The active Salesforce Sites with their secure addresses. Experience Cloud sites are left
	 * out (ADR-0013). Setup records, read in system mode so a viewer without View Setup sees the
	 * addresses.
	 */
	public static List<SiteInfo> sites() {
		if (testSites != null) {
			return testSites;
		}
		List<Site> rows = [
			SELECT Id, MasterLabel, GuestUserId
			FROM Site
			WHERE Status = 'Active' AND SiteType = 'Visualforce'
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
			LIMIT 50
		];
		Map<String, String> urls = new Map<String, String>();
		Set<String> ids = new Set<String>();
		for (Site row : rows) {
			ids.add(String.valueOf(row.Id).left(15));
			ids.add(String.valueOf(row.Id));
		}
		if (!rows.isEmpty()) {
			for (SiteDetail detail : [
				SELECT DurableId, SecureUrl
				FROM SiteDetail
				WHERE DurableId IN :ids
				WITH SYSTEM_MODE
			]) {
				urls.put(detail.DurableId.left(15), detail.SecureUrl);
			}
		}
		List<SiteInfo> found = new List<SiteInfo>();
		for (Site row : rows) {
			SiteInfo info = new SiteInfo();
			info.name = row.MasterLabel;
			info.guestUserId = row.GuestUserId;
			String url = urls.get(String.valueOf(row.Id).left(15));
			info.url = url == null ? null : url.removeEnd('/');
			found.add(info);
		}
		return found;
	}

	/**
	 * Health Check, while any published recipe receives webhooks: no active Site (warning), and
	 * Sites whose guest user lacks the receiver's permission set (warning, with a fix).
	 */
	public static List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		if (
			[
				SELECT COUNT()
				FROM Connector_Recipe__c
				WHERE Trigger_Kind__c = :WEBHOOK AND Status__c != :ConnectorRecipes.DRAFT
				WITH SYSTEM_MODE
				LIMIT 1
			] == 0
		) {
			return found;
		}
		if (sites().isEmpty()) {
			found.add(
				new HealthCheckService.Finding(
					'connector_webhook_no_site',
					BarnHelp.text('Connector', 'Connector_Health_WebhookNoSite_Title'),
					BarnHelp.text('Connector', 'Connector_Health_WebhookNoSite_Detail'),
					HealthCheckService.SEVERITY_WARNING,
					HealthCheckService.CATEGORY_SETTINGS
				)
			);
		}
		List<String> missing = sitesWithoutGuestAccess();
		if (!missing.isEmpty()) {
			found.add(
				new HealthCheckService.Finding(
						FIX_GUEST,
						BarnHelp.text('Connector', 'Connector_Health_WebhookGuest_Title'),
						BarnHelp.text(
							'Connector',
							'Connector_Health_WebhookGuest_Detail',
							new List<Object>{ String.join(missing, ', ') }
						),
						HealthCheckService.SEVERITY_WARNING,
						HealthCheckService.CATEGORY_SETTINGS
					)
					.withFix(
						BarnHelp.text('Connector', 'Connector_Health_WebhookGuest_Fix'),
						HealthCheckService.FIX_ACTION_PREFIX + FIX_GUEST
					)
			);
		}
		return found;
	}

	/** The names of active Sites whose guest user lacks the receiver's permission set. */
	public static List<String> sitesWithoutGuestAccess() {
		Set<Id> guests = new Set<Id>();
		for (SiteInfo site : sites()) {
			if (site.guestUserId != null) {
				guests.add(site.guestUserId);
			}
		}
		Set<Id> granted = new Set<Id>();
		for (PermissionSetAssignment row : [
			SELECT AssigneeId
			FROM PermissionSetAssignment
			WHERE PermissionSet.Name = :GUEST_SET AND AssigneeId IN :guests
			WITH SYSTEM_MODE
		]) {
			granted.add(row.AssigneeId);
		}
		List<String> names = new List<String>();
		for (SiteInfo site : sites()) {
			if (site.guestUserId != null && !granted.contains(site.guestUserId)) {
				names.add(site.name);
			}
		}
		return names;
	}

	/** The fix: assigns the receiver's permission set to the named Sites' guest users, as the viewer. */
	public static String grantGuestAccess(List<String> scope) {
		Set<String> names = new Set<String>(scope == null ? new List<String>() : scope);
		PermissionSet guestSet = SetupObjectSelector.permissionSet(GUEST_SET);
		List<PermissionSetAssignment> added = new List<PermissionSetAssignment>();
		for (SiteInfo site : sites()) {
			if (guestSet != null && names.contains(site.name) && site.guestUserId != null) {
				added.add(new PermissionSetAssignment(AssigneeId = site.guestUserId, PermissionSetId = guestSet.Id));
			}
		}
		insert as user added;
		return BarnHelp.text(
			'Connector',
			'Connector_Health_WebhookGuest_Done',
			new List<Object>{ String.join(new List<String>(names), ', ') }
		);
	}

	private static String text(Object value) {
		return ConnectorRecipeDocument.textOf(value);
	}
}
