/**
 * BarnCRM Connector connections (CN-01; canonical model 29CN1, R-CN1 to R-CN8; design
 * `integration-hub-design.md` Section 3.5; security review F1 to F12). Everything about a
 * connection except its key: who may write, the server-made names, the URL and header rules,
 * the ownership check before any `ConnectApi` call, the "BarnCRM Connections" permission set,
 * the Admin Journal row of a replaced key and the redacted log. The key itself passes only
 * through `ConnectorConnectionsController` (F8).
 */
public with sharing class ConnectorConnections {
	public static final String MODULE = 'Connector';
	public static final String PREFIX = 'BarnConn_';
	/** The built-in Generic REST connector's key in a connection name. */
	public static final String REST = 'rest';
	public static final String MANAGE_PERMISSION = 'Manage_BarnCRM_Connector';
	public static final String ADMIN_SET = 'Connector_Admin';
	/** The unpackaged permission set holding each connection's principal access (F12). */
	public static final String ACCESS_SET = 'BarnCRM_Connections';
	public static final String ACCESS_SET_LABEL = 'BarnCRM Connections';

	/** The built-in auth kinds; each is also its principal's name (R-CN2). */
	public static final String API_KEY = 'ApiKeyHeader';
	public static final String BEARER = 'BearerToken';
	public static final String BASIC = 'BasicAuth';
	public static final String SECRET_URL = 'SecretUrl';
	/**
	 * Amazon Web Services: the External Credential uses Salesforce's AWS Signature Version 4
	 * protocol, so Salesforce signs each callout with the stored key pair and Apex never sees it.
	 */
	public static final String AWS = 'AwsSigV4';
	/** The kinds New Connection makes. */
	public static final Set<String> KINDS = new Set<String>{ API_KEY, BEARER, BASIC, SECRET_URL, AWS };
	/**
	 * An OAuth 2.0 connection an administrator makes in Setup (an Auth Provider, then an External
	 * Credential and Named Credential both named `BarnConn_...`, principal `OAuth`): Salesforce
	 * holds and refreshes the tokens. BarnCRM uses it and never writes its credential.
	 */
	public static final String OAUTH = 'OAuth';
	/** Every kind BarnCRM lists and uses. */
	public static final Set<String> KNOWN_KINDS = new Set<String>{ API_KEY, BEARER, BASIC, SECRET_URL, AWS, OAUTH };
	/** The principal parameter that holds each kind's secret; Basic's user name is not one. */
	public static final Map<String, String> SECRET_PARAMETER = new Map<String, String>{
		API_KEY => 'Key',
		BEARER => 'Token',
		BASIC => 'Password',
		AWS => 'awsSecretAccessKey'
	};
	public static final String USER_PARAMETER = 'UserName';
	/** The access key ID of an AWS key pair: not a secret, written plain like Basic's user name. */
	public static final String AWS_KEY_ID_PARAMETER = 'awsAccessKeyId';
	/** `service.region.amazonaws.com`, optionally after a bucket: the service and region signed for. */
	private static final Pattern AWS_HOST = Pattern.compile(
		'^(?:[a-z0-9][a-z0-9-]*\\.)?([a-z0-9]+)\\.([a-z]{2}(?:-gov)?-[a-z]+-[0-9])\\.amazonaws\\.com$'
	);

	private static final String JOURNAL_KIND = 'Connection';
	private static final String JOURNAL_STATUS = 'Key Replaced';
	private static final Set<String> RESERVED_HEADERS = new Set<String>{
		'authorization',
		'host',
		'cookie',
		'content-length',
		'transfer-encoding'
	};

	/** The org's credential store; tests put a fake in its place. */
	@TestVisible
	private static ConnectorOrg org = new ConnectorOrg();

	/** Set by tests: whether the user holds Manage Named Credentials or Customize Application. */
	@TestVisible
	private static Boolean credentialPermissionOverride;

	/** A refusal written for a person: shown as it is. */
	public class ConnectorException extends Exception {
	}

	/** One connection as the browser sees it: names and status, never a key or a secret URL. */
	public class Connection {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String authKind;
		@AuraEnabled
		public String host;
		/** The last four characters of a Secret URL, for telling two apart (F5); else blank. */
		@AuraEnabled
		public String lastFour;
		@AuraEnabled
		public Boolean calloutsEnabled;
		@AuraEnabled
		public Boolean keyStored;
		@AuraEnabled
		public Boolean accessGranted;
	}

	/** The Connections section. */
	public class ConnectionsPage {
		@AuraEnabled
		public Boolean canWrite;
		@AuraEnabled
		public List<Connection> connections = new List<Connection>();
	}

	public static ConnectorOrg store() {
		return org;
	}

	// ---------------------------------------------------------------------------------------
	// Who may do what (F3)
	// ---------------------------------------------------------------------------------------

	public static Boolean canManage() {
		return FeatureManagement.checkPermission(MANAGE_PERMISSION);
	}

	public static void requireManager() {
		if (!canManage()) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NoManage'));
		}
	}

	/** Manage BarnCRM Connector and Manage Named Credentials or Customize Application (F3). */
	public static void requireWriter() {
		requireManager();
		if (!holdsCredentialPermission()) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NoCredentialPermission'));
		}
	}

	public static Boolean canWrite() {
		return canManage() && holdsCredentialPermission();
	}

	/**
	 * Whether a permission set of the running user grants Manage Named Credentials or Customize
	 * Application. The query text is fixed; the Manage Named Credentials column is named only
	 * when this org's PermissionSet has it, so an org without it still compiles and asks for
	 * Customize Application.
	 */
	@TestVisible
	private static Boolean holdsCredentialPermission() {
		if (credentialPermissionOverride != null) {
			return credentialPermissionOverride;
		}
		Boolean namedColumn = Schema.SObjectType.PermissionSet.fields.getMap()
			.containsKey('permissionsmanagenamedcredentials');
		String query =
			'SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND (' +
			(namedColumn ? 'PermissionSet.PermissionsManageNamedCredentials = TRUE OR ' : '') +
			'PermissionSet.PermissionsCustomizeApplication = TRUE)';
		return Database.countQueryWithBinds(
				query,
				new Map<String, Object>{ 'userId' => UserInfo.getUserId() },
				AccessLevel.SYSTEM_MODE
			) > 0;
	}

	// ---------------------------------------------------------------------------------------
	// Names and input rules (F2, F4, R-CN1, R-CN4)
	// ---------------------------------------------------------------------------------------

	/** `BarnConn_rest_` and six random letters and digits; never from the browser (F2). */
	public static String newName() {
		String letters = 'abcdefghijklmnopqrstuvwxyz0123456789';
		String suffix = '';
		while (suffix.length() < 6) {
			Integer at = Math.mod(Math.abs(Crypto.getRandomInteger()), letters.length());
			suffix += letters.substring(at, at + 1);
		}
		return PREFIX + REST + '_' + suffix;
	}

	public static String checkedLabel(String label) {
		String trimmed = label == null ? '' : label.trim();
		if (trimmed.length() < 1 || trimmed.length() > 80 || trimmed.contains('{!')) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_Label'));
		}
		return trimmed;
	}

	public static String checkedKind(String kind) {
		if (!KINDS.contains(kind)) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_Kind'));
		}
		return kind;
	}

	/**
	 * An `https` address with a host and no user information, query, fragment, spaces or `{!`
	 * (F1, F4). Returns it without a trailing slash.
	 */
	public static String checkedUrl(String value) {
		String text = value == null ? '' : value.trim();
		Url parsed;
		try {
			parsed = String.isBlank(text) || text.length() > 1000 ? null : new Url(text);
		} catch (Exception malformed) {
			parsed = null;
		}
		if (
			parsed == null ||
			parsed.getProtocol() != 'https' ||
			String.isBlank(parsed.getHost()) ||
			String.isNotBlank(parsed.getUserInfo()) ||
			String.isNotBlank(parsed.getQuery()) ||
			String.isNotBlank(parsed.getRef()) ||
			!text.toLowerCase().startsWith('https://') ||
			text.contains('{!') ||
			text.contains('\\') ||
			Pattern.matches('.*\\s.*', text)
		) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_Url'));
		}
		return text.removeEnd('/');
	}

	/** Letters, digits and hyphens, at most 64, never a header Salesforce or the auth kind sets. */
	public static String checkedHeaderName(String value) {
		String text = value == null ? '' : value.trim();
		if (!Pattern.matches('[A-Za-z0-9-]{1,64}', text) || RESERVED_HEADERS.contains(text.toLowerCase())) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_HeaderName'));
		}
		return text;
	}

	/** Same scheme, host (ignoring capitals) and port (F4: a host never moves). */
	public static Boolean sameHost(String first, String second) {
		try {
			Url a = new Url(first);
			Url b = new Url(second);
			return a.getProtocol() == b.getProtocol() &&
				a.getHost().toLowerCase() == b.getHost().toLowerCase() &&
				port(a) == port(b);
		} catch (Exception malformed) {
			return false;
		}
	}

	private static Integer port(Url address) {
		return address.getPort() == -1 ? address.getDefaultPort() : address.getPort();
	}

	/** The host of an address, or blank. */
	public static String hostOf(String address) {
		try {
			return new Url(address).getHost().toLowerCase();
		} catch (Exception malformed) {
			return '';
		}
	}

	// ---------------------------------------------------------------------------------------
	// The credentials as ConnectApi inputs, without any key (R-CN2, F1)
	// ---------------------------------------------------------------------------------------

	public static ConnectApi.ExternalCredentialInput externalInput(String name, String label, String kind) {
		return externalInput(name, label, kind, null);
	}

	/**
	 * The External Credential with one named principal. An AWS connection uses the AWS Signature
	 * Version 4 protocol with the service and region its address names (`awsScope`); every other
	 * kind the Custom protocol.
	 */
	public static ConnectApi.ExternalCredentialInput externalInput(String name, String label, String kind, String url) {
		ConnectApi.ExternalCredentialPrincipalInput principal = new ConnectApi.ExternalCredentialPrincipalInput();
		principal.principalName = kind;
		principal.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
		principal.sequenceNumber = 1;
		ConnectApi.ExternalCredentialInput input = new ConnectApi.ExternalCredentialInput();
		input.developerName = name;
		input.masterLabel = label;
		input.authenticationProtocol = protocolOf(kind);
		input.principals = new List<ConnectApi.ExternalCredentialPrincipalInput>{ principal };
		if (kind == AWS) {
			List<String> scope = awsScope(url);
			input.parameters = new List<ConnectApi.ExternalCredentialParameterInput>{
				authParameter('AwsService', scope[0]),
				authParameter('AwsRegion', scope[1])
			};
		}
		return input;
	}

	private static ConnectApi.CredentialAuthenticationProtocol protocolOf(String kind) {
		return kind == AWS
			? ConnectApi.CredentialAuthenticationProtocol.AwsSv4
			: ConnectApi.CredentialAuthenticationProtocol.Custom;
	}

	/** One External Credential authentication parameter (not a secret). */
	private static ConnectApi.ExternalCredentialParameterInput authParameter(String name, String value) {
		ConnectApi.ExternalCredentialParameterInput parameter = new ConnectApi.ExternalCredentialParameterInput();
		parameter.parameterName = name;
		parameter.parameterValue = value;
		parameter.parameterType = ConnectApi.ExternalCredentialParameterType.AuthParameter;
		return parameter;
	}

	/**
	 * The service and region an AWS address signs for, from its host: `s3` and `us-east-1` for
	 * `https://my-bucket.s3.us-east-1.amazonaws.com`. Refuses any other host, so a key pair is
	 * only ever signed for an Amazon Web Services address.
	 */
	public static List<String> awsScope(String url) {
		Matcher found = AWS_HOST.matcher(hostOf(url));
		if (!found.matches()) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_AwsUrl'));
		}
		return new List<String>{ found.group(1), found.group(2) };
	}

	/**
	 * The Named Credential linked to the External Credential of the same name, with its auth
	 * header from the kind alone (F1): formulas in the body always off, in headers only when the
	 * kind has a header. The caller sets the URL.
	 */
	public static ConnectApi.NamedCredentialInput namedInput(String name, String label, String kind, String header) {
		ConnectApi.ExternalCredentialInput link = new ConnectApi.ExternalCredentialInput();
		link.developerName = name;
		ConnectApi.NamedCredentialCalloutOptionsInput options = new ConnectApi.NamedCredentialCalloutOptionsInput();
		options.allowMergeFieldsInBody = false;
		// AWS: Salesforce writes the signed Authorization header itself; no formula is needed.
		Boolean formulaHeader = kind != SECRET_URL && kind != AWS;
		options.allowMergeFieldsInHeader = formulaHeader;
		options.generateAuthorizationHeader = kind == AWS;
		ConnectApi.NamedCredentialInput input = new ConnectApi.NamedCredentialInput();
		input.developerName = name;
		input.masterLabel = label;
		input.type = ConnectApi.NamedCredentialType.SecuredEndpoint;
		input.externalCredentials = new List<ConnectApi.ExternalCredentialInput>{ link };
		input.calloutOptions = options;
		input.customHeaders = new List<ConnectApi.CredentialCustomHeaderInput>();
		if (formulaHeader) {
			ConnectApi.CredentialCustomHeaderInput auth = new ConnectApi.CredentialCustomHeaderInput();
			auth.sequenceNumber = 1;
			auth.headerName = kind == API_KEY ? header : 'Authorization';
			auth.headerValue = headerTemplate(name, kind);
			input.customHeaders.add(auth);
		}
		return input;
	}

	/** The only place a `{!` is written (F1): the kind's header formula, from server names only. */
	@TestVisible
	private static String headerTemplate(String name, String kind) {
		String credential = '$Credential.' + name + '.';
		if (kind == API_KEY) {
			return '{!' + credential + 'Key}';
		}
		if (kind == BEARER) {
			return '{!\'Bearer \' & ' + credential + 'Token}';
		}
		return '{!\'Basic \' & BASE64ENCODE(BLOB(' + credential + 'UserName & \':\' & ' + credential + 'Password))}';
	}

	/** The credential input for the kind's principal, without values. */
	public static ConnectApi.CredentialInput credentialInput(String name, String kind) {
		ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
		input.externalCredential = name;
		input.principalName = kind;
		input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
		input.authenticationProtocol = protocolOf(kind);
		input.credentials = new Map<String, ConnectApi.CredentialValueInput>();
		return input;
	}

	/** A non-secret value (Basic's user name), written unencrypted (F6). */
	public static ConnectApi.CredentialValueInput plainValue(String value) {
		ConnectApi.CredentialValueInput input = new ConnectApi.CredentialValueInput();
		input.value = value;
		input.encrypted = false;
		return input;
	}

	// ---------------------------------------------------------------------------------------
	// Reading connections (F2, F5, F6)
	// ---------------------------------------------------------------------------------------

	public static ConnectionsPage page() {
		ConnectionsPage result = new ConnectionsPage();
		result.canWrite = canWrite();
		Set<Id> granted = grantedPrincipals();
		Map<String, String> labels = org.labelsByName();
		for (String name : labels.keySet()) {
			ConnectorOrg.Pair pair = org.read(name, labels.get(name));
			if (pair != null && pair.linked && KNOWN_KINDS.contains(pair.principal)) {
				result.connections.add(shown(pair, pair.principalId != null && granted.contains(pair.principalId)));
			}
		}
		return result;
	}

	/**
	 * The path Check Connection asks for (R-CN9): the check path of the template the connection
	 * was made from, or null for the base URL. Read in system mode: the row holds no key.
	 */
	public static String checkPathOf(String name) {
		for (Connector_Connection__c row : [
			SELECT Check_Path__c
			FROM Connector_Connection__c
			WHERE Name = :name
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return row.Check_Path__c;
		}
		return null;
	}

	/**
	 * Keeps a template's check path with the connection (R-CN9). Its own call after the create,
	 * since that one writes permission sets and a record write may not share it.
	 */
	public static void saveCheckPath(String name, String path) {
		requireWriter();
		ConnectorOrg.Pair pair = owned(name);
		String checked = String.isBlank(path) ? null : path.trim();
		if (
			checked != null &&
			(checked.length() > 255 ||
			checked.contains('{') ||
			ConnectorRecipeDocument.pathProblem(checked))
		) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_CheckPath'));
		}
		List<Connector_Connection__c> rows = [
			SELECT Id
			FROM Connector_Connection__c
			WHERE Name = :pair.name
			WITH SYSTEM_MODE
			LIMIT 1
		];
		Connector_Connection__c row = rows.isEmpty() ? new Connector_Connection__c(Name = pair.name) : rows[0];
		row.Check_Path__c = checked;
		Database.upsert(row, AccessLevel.SYSTEM_MODE);
	}

	/** Removes what was kept beside a deleted connection (R-CN9). */
	public static void forget(String name) {
		Database.delete(
			[SELECT Id FROM Connector_Connection__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 10],
			AccessLevel.SYSTEM_MODE
		);
	}

	/** The principal Ids of every `BarnConn_` connection, one read each. */
	public static Set<Id> principalIds() {
		Set<Id> found = new Set<Id>();
		Map<String, String> labels = org.labelsByName();
		for (String name : labels.keySet()) {
			ConnectorOrg.Pair pair = org.read(name, labels.get(name));
			if (pair != null && pair.principalId != null) {
				found.add(pair.principalId);
			}
		}
		return found;
	}

	/** Names and status only: the URL becomes a host, a Secret URL its host and last four. */
	@TestVisible
	private static Connection shown(ConnectorOrg.Pair pair, Boolean accessGranted) {
		Connection row = new Connection();
		row.name = pair.name;
		row.label = pair.label;
		row.authKind = pair.principal;
		row.host = hostOf(pair.url);
		row.lastFour = pair.principal == SECRET_URL && pair.url != null ? pair.url.right(4) : '';
		row.calloutsEnabled = pair.calloutsEnabled == true;
		row.keyStored = pair.principal == SECRET_URL || pair.keyStored == true;
		row.accessGranted = accessGranted == true;
		return row;
	}

	/**
	 * The connection by name, only when it is BarnCRM's own (F2, R-CN1): `BarnConn_`, an External
	 * Credential of this org without a namespace, linked to the Named Credential of the same
	 * name, with a built-in principal. Anything else is refused before any write.
	 */
	public static ConnectorOrg.Pair owned(String name) {
		if (String.isBlank(name) || !name.startsWith(PREFIX) || !Pattern.matches('[A-Za-z0-9_]{1,80}', name)) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NotOurs'));
		}
		Map<String, String> labels = org.labelsByName();
		ConnectorOrg.Pair pair = labels.containsKey(name) ? org.read(name, labels.get(name)) : null;
		if (pair == null || !pair.linked || !KNOWN_KINDS.contains(pair.principal)) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NotOurs'));
		}
		return pair;
	}

	/**
	 * Refuses a key write to a connection made in Setup (OAuth): Salesforce holds its tokens, and
	 * the administrator signs in again from Setup instead (R-CN12).
	 */
	public static void refuseSetupMade(ConnectorOrg.Pair pair) {
		if (pair.principal == OAUTH) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_SetupMade'));
		}
	}

	/** Whether the Connections set already gives the connection's principal (R-CN7). */
	public static Boolean principalGranted(ConnectorOrg.Pair pair) {
		return pair.principalId != null && grantedPrincipals().contains(pair.principalId);
	}

	// ---------------------------------------------------------------------------------------
	// The "BarnCRM Connections" permission set (F12, R-CN7)
	// ---------------------------------------------------------------------------------------

	public static PermissionSet accessSet() {
		for (PermissionSet row : [
			SELECT Id
			FROM PermissionSet
			WHERE Name = :ACCESS_SET AND NamespacePrefix = NULL AND IsOwnedByProfile = FALSE
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return row;
		}
		return null;
	}

	/** The Connections set's Id, creating it once (R-CN7). */
	public static Id ensureAccessSet() {
		PermissionSet target = accessSet();
		if (target == null) {
			target = new PermissionSet(Name = ACCESS_SET, Label = ACCESS_SET_LABEL);
			target.Description = BarnHelp.text('Connector', 'Connector_AccessSet_Description');
			Database.insert(target, AccessLevel.SYSTEM_MODE);
		}
		return target.Id;
	}

	private static Set<Id> grantedPrincipals() {
		PermissionSet existing = accessSet();
		return existing == null ? new Set<Id>() : org.grantedEntities(existing.Id);
	}

	/** Whether the running user holds the packaged BarnCRM Connector Admin set. */
	public static Boolean holdsAdminSet() {
		return holds(UserInfo.getUserId(), ADMIN_SET, NamespaceUtil.namespacePrefix());
	}

	public static Boolean holdsAccessSet() {
		return holds(UserInfo.getUserId(), ACCESS_SET, null);
	}

	/** Whether the user holds the named permission set (`namespace` null for an org's own). */
	public static Boolean holds(Id userId, String setName, String namespace) {
		return [
				SELECT COUNT()
				FROM PermissionSetAssignment
				WHERE
					AssigneeId = :userId
					AND PermissionSet.Name = :setName
					AND PermissionSet.NamespacePrefix = :namespace
				WITH SYSTEM_MODE
			] > 0;
	}

	/**
	 * Gives the running user, who must hold BarnCRM Connector Admin, the Connections set, creating
	 * it once, and adds the connection's principal to it. User Ids never come from the browser.
	 * Returns false when Salesforce refused the principal access, so the page shows the Setup
	 * step instead (design Section 3.11, check 8).
	 */
	public static Boolean grantAccess(String name) {
		if (!holdsAdminSet()) {
			throw new ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NoManage'));
		}
		PermissionSet target = new PermissionSet(Id = ensureAccessSet());
		if (!holdsAccessSet()) {
			Database.insert(
				new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = target.Id),
				AccessLevel.SYSTEM_MODE
			);
		}
		ConnectorOrg.Pair pair = org.read(name, null);
		Id principal = pair == null ? null : pair.principalId;
		if (principal == null) {
			return false;
		}
		if (org.grantedEntities(target.Id).contains(principal)) {
			return true;
		}
		try {
			org.grant(target.Id, principal);
			return true;
		} catch (Exception refused) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Connector',
					'Connector_Log_AccessRefused',
					new List<Object>{ name, refused.getTypeName() }
				),
				'ConnectorConnections.grantAccess',
				ErrorLogger.SEVERITY_WARNING
			);
			return false;
		}
	}

	// ---------------------------------------------------------------------------------------
	// Audit and logging (F7, F11)
	// ---------------------------------------------------------------------------------------

	/** One Admin Journal row per replaced key: who and when, never the key (R-CN6). */
	public static void journalKeyReplaced(ConnectorOrg.Pair pair) {
		Database.insert(
			new Merge_Journal__c(
				Kind__c = JOURNAL_KIND,
				Status__c = JOURNAL_STATUS,
				Message__c = pair.label + ' (' + pair.name + ')'
			),
			AccessLevel.SYSTEM_MODE
		);
	}

	/**
	 * The same row from a job, for a write a record may not follow in its transaction (a Secret
	 * URL's Named Credential update, a setup write; barn-platform, 2026-11-21).
	 */
	public static void journalKeyReplacedLater(ConnectorOrg.Pair pair) {
		AsyncStarter.queue(new JournalJob(pair.name, pair.label), 'ConnectorConnections.journalKeyReplacedLater');
	}

	/** Writes one key-replaced Admin Journal row: names only, never the key. */
	public with sharing class JournalJob implements Queueable {
		private String name;
		private String label;

		public JournalJob(String name, String label) {
			this.name = name;
			this.label = label;
		}

		public void execute(QueueableContext context) {
			ConnectorOrg.Pair pair = new ConnectorOrg.Pair();
			pair.name = name;
			pair.label = label;
			journalKeyReplaced(pair);
		}
	}

	/** Labels of connections whose key was replaced in the last days given, newest first. */
	public static List<String> keysReplacedSince(Integer days) {
		DateTime since = DateTime.now().addDays(-days);
		List<String> found = new List<String>();
		for (Merge_Journal__c row : [
			SELECT Message__c
			FROM Merge_Journal__c
			WHERE Kind__c = :JOURNAL_KIND AND Status__c = :JOURNAL_STATUS AND CreatedDate >= :since
			WITH SYSTEM_MODE
			ORDER BY CreatedDate DESC
			LIMIT 20
		]) {
			found.add(row.Message__c);
		}
		return found;
	}

	/**
	 * Logs a failed credential write: a fixed message, the exception type and its message with
	 * every secret already replaced by `****` by the caller (F7). Never the raw exception.
	 */
	public static void logRedacted(String context, String typeName, String redactedDetail) {
		ErrorLogger.logMessage(
			BarnHelp.text('Connector', 'Connector_Log_WriteFailed', new List<Object>{ typeName, redactedDetail }),
			context,
			ErrorLogger.SEVERITY_ERROR
		);
	}
}
