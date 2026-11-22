/**
 * The backup destination (BK-10, D-221; canonical model R-CN11 and R-SQ17; ADR-NEXT automatic
 * backups). Core's `OffPlatformDestination`, found through the Connector catalog row's
 * `Extensions__c`, so Core names no Connector class. One connection at most holds Backup
 * Settings in its Connector Connection row: a method, a path with `{file}` and fixed headers
 * that hold no secret. Each file is one request to `callout:<connection>`, so the key stays in
 * the Named and External Credential (ADR-0229); nothing secret is stored here. The connection may
 * sign with a key, an AWS Signature Version 4 key pair or OAuth 2.0 (R-CN12): Salesforce adds the
 * sign-in to each callout either way.
 *
 * Storage services name the file in different places (R-CN11): in the path (WebDAV, S3, Azure,
 * OneDrive), in a fixed header such as Dropbox's `Dropbox-API-Arg` JSON, or in Google Drive's
 * multipart metadata. `{file}` may stand in any of these; in a header or the metadata it is
 * written JSON-escaped. A path may end in a fixed query from a short list (`uploadType`), never
 * one that could carry a signature.
 *
 * The rows are read and written in system mode (they hold no key); saving needs the key-writing
 * permissions (R-CN3).
 */
@NamespaceAccessible
public with sharing class ConnectorBackupDestination implements OffPlatformDestination {
	/** The key Core stores for this destination on a set or an archive. */
	public static final String KEY = 'offPlatform';
	public static final String FILE_SLOT = '{file}';
	public static final Set<String> METHODS = new Set<String>{ 'PUT', 'POST' };
	public static final Integer MAX_HEADERS = 5;
	/** The query names a backup path may end with (Google Drive's upload kind): never a signature. */
	public static final Set<String> QUERY_NAMES = new Set<String>{ 'uploadType', 'supportsAllDrives' };
	private static final Pattern QUERY_VALUE = Pattern.compile('[A-Za-z0-9_-]{1,40}');
	private static final Integer MAX_METADATA = 1000;
	private static final Integer TIMEOUT = 120000;

	/** One fixed request header: never a key (F1). */
	public class Header {
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String value;

		public Header(String name, String value) {
			this.name = name;
			this.value = value;
		}
	}

	/** What Backup Settings hold. */
	public class Settings {
		@AuraEnabled
		public String method;
		@AuraEnabled
		public String path;
		@AuraEnabled
		public List<Header> headers = new List<Header>();
		/**
		 * A JSON object sent before the file as a `multipart/related` request (Google Drive's
		 * multipart upload), such as `{"name":"{file}","parents":["folder id"]}`; else blank.
		 */
		@AuraEnabled
		public String metadata;
	}

	/** The Backup Destination part of the Connections section. */
	public class Setup {
		@AuraEnabled
		public Boolean canWrite;
		/** The destination connection's name, or null when none is set. */
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Settings settings;
		/** Null when the person can send now; otherwise why not. */
		@AuraEnabled
		public String note;
	}

	@NamespaceAccessible
	public ConnectorBackupDestination() {
		return;
	}

	public String key() {
		return KEY;
	}

	public String notReady() {
		if (currentRow() == null) {
			return BarnHelp.text('Connector', 'Connector_Backup_NotSet');
		}
		if (!ConnectorConnections.holdsAccessSet()) {
			return BarnHelp.text('Connector', 'Connector_Backup_NoAccess');
		}
		return null;
	}

	/**
	 * One request, no DML. The settings are checked again before sending, so a row changed
	 * outside the page cannot send a merge field, a query or a sign-in header.
	 */
	public String send(String fileName, Blob body) {
		Connector_Connection__c row = currentRow();
		if (row == null) {
			return BarnHelp.text('Connector', 'Connector_Backup_NotSet');
		}
		Settings settings;
		try {
			// The name only: reading the credential through ConnectApi needs Setup permissions
			// the nightly run's user may not hold. The row was written by a key writer (R-CN11).
			if (!row.Name.startsWith(ConnectorConnections.PREFIX) || !Pattern.matches('[A-Za-z0-9_]{1,80}', row.Name)) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Error_NotOurs')
				);
			}
			Settings stored = parse(row.Backup_JSON__c);
			settings = checked(stored.method, stored.path, stored.headers, stored.metadata);
		} catch (ConnectorConnections.ConnectorException refused) {
			return refused.getMessage();
		}
		HttpRequest request = request(row.Name, settings, fileName, body);
		request.setTimeout(TIMEOUT);
		try {
			Integer status = new Http().send(request).getStatusCode();
			return status >= 200 &&
				status < 300
				? null
				: BarnHelp.text('Connector', 'Connector_Backup_Refused', new List<Object>{ status });
		} catch (CalloutException unreachable) {
			return BarnHelp.text(
				'Connector',
				'Connector_Backup_Unreachable',
				new List<Object>{ unreachable.getTypeName() }
			);
		}
	}

	/**
	 * The request for one file: `{file}` URL-encoded in the path and JSON-escaped in a header or
	 * the metadata. `text/csv` unless a header names another Content-Type (Dropbox asks for
	 * `application/octet-stream`); with metadata, a `multipart/related` body of the metadata and
	 * then the file.
	 */
	@TestVisible
	private static HttpRequest request(String connection, Settings settings, String fileName, Blob body) {
		HttpRequest result = new HttpRequest();
		result.setEndpoint('callout:' + connection + settings.path.replace(FILE_SLOT, encoded(fileName)));
		result.setMethod(settings.method);
		String inJson = jsonText(fileName);
		String contentType = 'text/csv';
		for (Header header : settings.headers) {
			if (header.name.equalsIgnoreCase('Content-Type')) {
				contentType = header.value;
			} else {
				result.setHeader(header.name, header.value.replace(FILE_SLOT, inJson));
			}
		}
		if (String.isBlank(settings.metadata)) {
			result.setHeader('Content-Type', contentType);
			result.setBodyAsBlob(body);
			return result;
		}
		String boundary = 'barncrm' + EncodingUtil.convertToHex(Crypto.generateAesKey(128));
		result.setHeader('Content-Type', 'multipart/related; boundary=' + boundary);
		result.setBody(
			'--' +
				boundary +
				'\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n' +
				settings.metadata.replace(FILE_SLOT, inJson) +
				'\r\n--' +
				boundary +
				'\r\nContent-Type: ' +
				contentType +
				'\r\n\r\n' +
				body.toString() +
				'\r\n--' +
				boundary +
				'--'
		);
		return result;
	}

	/**
	 * The file name inside a JSON string, quotes and backslashes escaped and anything outside
	 * printable ASCII written as `\\uXXXX`, so a header value stays ASCII (Dropbox's rule).
	 */
	@TestVisible
	private static String jsonText(String value) {
		String quoted = JSON.serialize(value == null ? '' : value);
		String escaped = quoted.substring(1, quoted.length() - 1);
		String result = '';
		for (Integer at = 0; at < escaped.length(); at++) {
			Integer code = escaped.charAt(at);
			// A UTF-16 unit each, so a character outside the basic plane becomes its surrogate pair.
			result += code >= 32 && code < 127 ? escaped.substring(at, at + 1) : '\\u' + hex4(code);
		}
		return result;
	}

	private static String hex4(Integer code) {
		String digits = '0123456789abcdef';
		String result = '';
		for (Integer shift = 12; shift >= 0; shift -= 4) {
			Integer nibble = (code >> shift) & 15;
			result += digits.substring(nibble, nibble + 1);
		}
		return result;
	}

	// ---------------------------------------------------------------------------------------
	// Setting it (R-CN11)
	// ---------------------------------------------------------------------------------------

	public static Setup setup() {
		ConnectorConnections.requireManager();
		Setup result = new Setup();
		result.canWrite = ConnectorConnections.canWrite();
		Connector_Connection__c row = currentRow();
		if (row != null) {
			result.name = row.Name;
			result.settings = parse(row.Backup_JSON__c);
		}
		result.note = new ConnectorBackupDestination().notReady();
		return result;
	}

	/** Makes this connection the backup destination, clearing it from any other. */
	public static void save(String name, String method, String path, String headerLines, String metadata) {
		ConnectorConnections.requireWriter();
		ConnectorOrg.Pair pair = ConnectorConnections.owned(name);
		Settings settings = checked(method, path, headersOf(headerLines), metadata);
		List<Connector_Connection__c> changed = new List<Connector_Connection__c>();
		Connector_Connection__c target;
		for (Connector_Connection__c row : rowsWithSettingsOr(pair.name)) {
			if (row.Name == pair.name) {
				target = row;
			} else {
				row.Backup_JSON__c = null;
				changed.add(row);
			}
		}
		target = target == null ? new Connector_Connection__c(Name = pair.name) : target;
		target.Backup_JSON__c = JSON.serialize(settings);
		Database.update(changed, AccessLevel.SYSTEM_MODE);
		Database.upsert(target, AccessLevel.SYSTEM_MODE);
	}

	/** No connection is the backup destination any more. */
	public static void stop() {
		ConnectorConnections.requireWriter();
		List<Connector_Connection__c> rows = rowsWithSettingsOr(null);
		for (Connector_Connection__c row : rows) {
			row.Backup_JSON__c = null;
		}
		Database.update(rows, AccessLevel.SYSTEM_MODE);
	}

	public static Settings checked(String method, String path, List<Header> headers) {
		return checked(method, path, headers, null);
	}

	/**
	 * The settings, or a refusal for a person: PUT or POST; a path that follows the check path's
	 * rules (R-CN9) with `{file}` at most once and at most a fixed query from `QUERY_NAMES`; at
	 * most five headers a recipe may set (F1), none that looks like a sign-in header, each value
	 * at most 255 characters with no `{!`, CR or LF; metadata, when given, one JSON object of at
	 * most 1,000 characters with no `{!`. `{file}` appears at least once in the path, a header or
	 * the metadata, so each file has a name of its own.
	 */
	public static Settings checked(String method, String path, List<Header> headers, String metadata) {
		Settings result = new Settings();
		result.method = String.isBlank(method) ? '' : method.trim().toUpperCase();
		if (!METHODS.contains(result.method)) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Backup_ErrorMethod')
			);
		}
		result.path = String.isBlank(path) ? '' : path.trim();
		String rest = result.path.substringBefore('?').replace(FILE_SLOT, 'x');
		if (
			result.path.countMatches(FILE_SLOT) > 1 ||
			rest.contains('{') ||
			rest.contains('}') ||
			ConnectorRecipeDocument.pathProblem(rest) ||
			(result.path.contains('?') && !queryOk(result.path.substringAfter('?')))
		) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Backup_ErrorPath'));
		}
		result.metadata = metadataChecked(metadata);
		Integer slots =
			result.path.countMatches(FILE_SLOT) +
			(result.metadata == null ? 0 : result.metadata.countMatches(FILE_SLOT));
		List<Header> given = headers == null ? new List<Header>() : headers;
		if (given.size() > MAX_HEADERS) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Backup_ErrorHeader')
			);
		}
		for (Header header : given) {
			String name = String.isBlank(header.name) ? '' : header.name.trim();
			String value = header.value == null ? '' : header.value.trim();
			if (
				!ConnectorRecipeDocument.headerNameOk(name) ||
				ConnectorRecipeDocument.SIGN_IN_HEADER.matcher(name).matches() ||
				String.isBlank(value) ||
				value.length() > 255 ||
				ConnectorRecipeDocument.unsafeValue(value)
			) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Backup_ErrorHeader')
				);
			}
			result.headers.add(new Header(name, value));
			slots += value.countMatches(FILE_SLOT);
		}
		if (slots == 0) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Backup_ErrorPath'));
		}
		return result;
	}

	/** `name=value` pairs joined by `&`, each name from `QUERY_NAMES`, each value plain (F4). */
	private static Boolean queryOk(String query) {
		if (String.isBlank(query)) {
			return false;
		}
		for (String pair : query.split('&')) {
			if (
				!QUERY_NAMES.contains(pair.substringBefore('=')) ||
				!QUERY_VALUE.matcher(pair.substringAfter('=')).matches()
			) {
				return false;
			}
		}
		return true;
	}

	/** Blank, or one JSON object with no `{!`, at most 1,000 characters; refused otherwise. */
	private static String metadataChecked(String metadata) {
		if (String.isBlank(metadata)) {
			return null;
		}
		String text = metadata.trim();
		Boolean isObject;
		try {
			isObject = JSON.deserializeUntyped(text.replace(FILE_SLOT, 'x')) instanceof Map<String, Object>;
		} catch (Exception unreadable) {
			isObject = false;
		}
		if (!isObject || text.length() > MAX_METADATA || text.contains('{!')) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Backup_ErrorMetadata')
			);
		}
		return text;
	}

	/** Header lines as the page sends them: `Name: value`, one a line, blank lines skipped. */
	@TestVisible
	private static List<Header> headersOf(String lines) {
		List<Header> result = new List<Header>();
		for (String line : String.isBlank(lines) ? new List<String>() : lines.split('\n')) {
			if (String.isBlank(line)) {
				continue;
			}
			if (!line.contains(':')) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Backup_ErrorHeader')
				);
			}
			result.add(new Header(line.substringBefore(':'), line.substringAfter(':').removeEnd('\r')));
		}
		return result;
	}

	private static Settings parse(String stored) {
		try {
			Settings result = (Settings) JSON.deserialize(stored, Settings.class);
			if (result.headers == null) {
				result.headers = new List<Header>();
			}
			return result;
		} catch (Exception unreadable) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Backup_ErrorPath'));
		}
	}

	/** The destination's row, or null when no connection is the backup destination. */
	private static Connector_Connection__c currentRow() {
		List<Connector_Connection__c> rows = rowsWithSettingsOr(null);
		return rows.isEmpty() ? null : rows[0];
	}

	private static List<Connector_Connection__c> rowsWithSettingsOr(String name) {
		List<Connector_Connection__c> result = new List<Connector_Connection__c>();
		for (Connector_Connection__c row : [
			SELECT Id, Name, Backup_JSON__c
			FROM Connector_Connection__c
			WITH SYSTEM_MODE
			ORDER BY LastModifiedDate DESC
			LIMIT 200
		]) {
			if (row.Name == name || String.isNotBlank(row.Backup_JSON__c)) {
				result.add(row);
			}
		}
		return result;
	}

	/** URL-encoded for a path (F4): `%20` for a space, so nothing can end the segment. */
	private static String encoded(String value) {
		return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
	}
}
