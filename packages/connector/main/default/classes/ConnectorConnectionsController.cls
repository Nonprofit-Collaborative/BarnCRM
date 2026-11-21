/**
 * The Connections section of Super Connector (CN-01; canonical model 29CN1; security review F1
 * to F12). Thin: the rules live in `ConnectorConnections`. Granted only by BarnCRM Connector
 * Admin, never by a guest or user-level set, and exposed by no Visualforce page or REST
 * resource (F3).
 *
 * A key (or a Secret URL) arrives as the `secret` parameter of `createConnection` or
 * `replaceKey` and goes straight into the `ConnectApi` input in that one method (F8), written
 * synchronously as the person saving it (F3), encrypted (F6). No method returns it, logs it,
 * stores it or hands it on: a failure is logged with every occurrence of it replaced by `****`
 * and the person sees a fixed message (F7). Nothing here is cacheable (F10).
 */
public with sharing class ConnectorConnectionsController {
	private static final String CONTEXT = 'ConnectorConnectionsController';

	/** What a write or a check did, in words the page shows. */
	public class Result {
		@AuraEnabled
		public String outcome;
		@AuraEnabled
		public Integer status;
		/** The account a check call's answer names, when the app gives one (F11). */
		@AuraEnabled
		public String account;
		/** The new connection's name, after a create. */
		@AuraEnabled
		public String name;
		@AuraEnabled
		public ConnectorConnections.ConnectionsPage page;
	}

	/** Where an answer may name the signed-in account, in order. */
	private static final List<String> ACCOUNT_KEYS = new List<String>{
		'account_name',
		'accountName',
		'login',
		'username',
		'email',
		'account',
		'name',
		'company'
	};

	@AuraEnabled
	public static ConnectorConnections.ConnectionsPage getConnections() {
		try {
			ConnectorConnections.requireManager();
			return ConnectorConnections.page();
		} catch (Exception failure) {
			throw shown(failure, 'getConnections');
		}
	}

	/**
	 * Creates the External Credential, the Named Credential and the principal access (F12). The
	 * server makes the name (F2). `secretUrl` is a Secret URL connection's address, its only key;
	 * any other kind's key follows in `saveFirstKey`, a call of its own, because Salesforce
	 * refuses a key for a principal made in the same transaction (barn-platform, 2026-11-21).
	 */
	@AuraEnabled
	public static Result createConnection(
		String label,
		String authKind,
		String baseUrl,
		String headerName,
		String secretUrl
	) {
		String name;
		Boolean externalMade = false;
		Boolean namedMade = false;
		try {
			ConnectorConnections.requireWriter();
			String kind = ConnectorConnections.checkedKind(authKind);
			String checkedLabel = ConnectorConnections.checkedLabel(label);
			String header = kind == ConnectorConnections.API_KEY
				? ConnectorConnections.checkedHeaderName(headerName)
				: null;
			String url = ConnectorConnections.checkedUrl(kind == ConnectorConnections.SECRET_URL ? secretUrl : baseUrl);
			ConnectorOrg org = ConnectorConnections.store();
			name = ConnectorConnections.newName();
			org.createExternal(ConnectorConnections.externalInput(name, checkedLabel, kind));
			externalMade = true;
			ConnectApi.NamedCredentialInput named = ConnectorConnections.namedInput(name, checkedLabel, kind, header);
			named.calloutUrl = url;
			if (org.fake) {
				org.record(named, false);
			} else {
				ConnectApi.NamedCredentials.createNamedCredential(named);
			}
			namedMade = true;
		} catch (ConnectorConnections.ConnectorException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception failure) {
			ConnectorConnections.logRedacted(
				CONTEXT + '.createConnection',
				failure.getTypeName(),
				redacted(failure.getMessage(), secretUrl)
			);
			undo(name, externalMade, namedMade);
			throw UserErrors.message(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'));
		}
		Result result = new Result();
		result.name = name;
		try {
			result.outcome = ConnectorConnections.grantAccess(name) ? 'created' : 'createdAccessMissing';
			result.page = ConnectorConnections.page();
		} catch (Exception failure) {
			throw shown(failure, 'createConnection');
		}
		return result;
	}

	/**
	 * Writes the first key of a connection just created (any kind but Secret URL). When it is
	 * refused the connection is taken away, so no connection without a key is left (F7, F8).
	 */
	@AuraEnabled
	public static Result saveFirstKey(String name, String userName, String secret) {
		ConnectorOrg.Pair pair;
		try {
			ConnectorConnections.requireWriter();
			pair = ConnectorConnections.owned(name);
			if (pair.principal == ConnectorConnections.SECRET_URL || pair.keyStored) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Error_NotOurs')
				);
			}
		} catch (ConnectorConnections.ConnectorException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception failure) {
			throw shown(failure, 'saveFirstKey');
		}
		try {
			ConnectApi.CredentialInput credential = keyInput(pair, userName, secret);
			ConnectorOrg org = ConnectorConnections.store();
			if (org.fake) {
				org.record(credential, false);
			} else {
				ConnectApi.NamedCredentials.createCredential(credential);
			}
		} catch (ConnectorConnections.ConnectorException refused) {
			undo(pair.name, true, true);
			throw UserErrors.message(refused.getMessage());
		} catch (Exception failure) {
			ConnectorConnections.logRedacted(
				CONTEXT + '.saveFirstKey',
				failure.getTypeName(),
				redacted(failure.getMessage(), secret)
			);
			undo(pair.name, true, true);
			throw UserErrors.message(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'));
		}
		Result result = new Result();
		result.name = pair.name;
		result.outcome = 'keySaved';
		try {
			result.page = ConnectorConnections.page();
		} catch (Exception failure) {
			throw shown(failure, 'saveFirstKey');
		}
		return result;
	}

	/**
	 * The principal's key input for a connection that is not a Secret URL: the key encrypted and
	 * Basic's user name plain (F6). Refuses a blank key or a blank Basic user name.
	 */
	private static ConnectApi.CredentialInput keyInput(ConnectorOrg.Pair pair, String userName, String secret) {
		if (String.isBlank(secret)) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Error_KeyRequired')
			);
		}
		ConnectApi.CredentialInput credential = ConnectorConnections.credentialInput(pair.name, pair.principal);
		if (pair.principal == ConnectorConnections.BASIC) {
			if (String.isBlank(userName)) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Error_UserRequired')
				);
			}
			credential.credentials.put(
				ConnectorConnections.USER_PARAMETER,
				ConnectorConnections.plainValue(userName.trim())
			);
		}
		ConnectApi.CredentialValueInput key = new ConnectApi.CredentialValueInput();
		key.value = secret;
		key.encrypted = true;
		credential.credentials.put(ConnectorConnections.SECRET_PARAMETER.get(pair.principal), key);
		return credential;
	}

	/**
	 * Writes a new key over the old one (or a new Secret URL on the same host, F4), then one
	 * Admin Journal row (F11). The name must be BarnCRM's own (F2) before anything is written.
	 */
	@AuraEnabled
	public static Result replaceKey(String name, String userName, String secret) {
		ConnectorOrg.Pair pair;
		try {
			ConnectorConnections.requireWriter();
			pair = ConnectorConnections.owned(name);
			ConnectorOrg org = ConnectorConnections.store();
			if (pair.principal == ConnectorConnections.SECRET_URL) {
				String url = ConnectorConnections.checkedUrl(secret);
				if (!ConnectorConnections.sameHost(pair.url, url)) {
					throw new ConnectorConnections.ConnectorException(
						BarnHelp.text('Connector', 'Connector_Error_HostChanged')
					);
				}
				ConnectApi.NamedCredentialInput named = ConnectorConnections.namedInput(
					pair.name,
					pair.label,
					pair.principal,
					null
				);
				named.calloutUrl = url;
				if (org.fake) {
					org.record(named, true);
				} else {
					ConnectApi.NamedCredentials.updateNamedCredential(pair.name, named);
				}
			} else {
				ConnectApi.CredentialInput credential = keyInput(pair, userName, secret);
				if (org.fake) {
					org.record(credential, pair.keyStored);
				} else if (pair.keyStored) {
					ConnectApi.NamedCredentials.updateCredential(credential);
				} else {
					ConnectApi.NamedCredentials.createCredential(credential);
				}
			}
		} catch (ConnectorConnections.ConnectorException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception failure) {
			ConnectorConnections.logRedacted(
				CONTEXT + '.replaceKey',
				failure.getTypeName(),
				redacted(failure.getMessage(), secret)
			);
			throw UserErrors.message(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'));
		}
		Result result = new Result();
		try {
			if (pair.principal == ConnectorConnections.SECRET_URL) {
				// A Named Credential write is a setup write: the journal row follows in a job.
				ConnectorConnections.journalKeyReplacedLater(pair);
			} else {
				ConnectorConnections.journalKeyReplaced(pair);
			}
			result.outcome = 'replaced';
			result.page = ConnectorConnections.page();
		} catch (Exception failure) {
			throw shown(failure, 'replaceKey');
		}
		return result;
	}

	/**
	 * Keeps a template's check path with a connection just created (R-CN9, e1). A call of its
	 * own: the create writes permission sets, and a record write may not share that transaction.
	 */
	@AuraEnabled
	public static void saveCheckPath(String name, String checkPath) {
		try {
			ConnectorConnections.saveCheckPath(name, checkPath);
		} catch (Exception failure) {
			throw shown(failure, 'saveCheckPath');
		}
	}

	/**
	 * One GET through the connection, as the person checking: of the template's check path when
	 * the connection has one (R-CN9), else of the base URL. A 2xx answer that names the account
	 * shows it (F11). Before it: callouts must be on (the Setup step) and the person must hold
	 * the Connections set; giving it is a setup write, after which a callout may not follow, so
	 * the page asks to check again.
	 */
	@AuraEnabled
	public static Result checkConnection(String name) {
		Result result = new Result();
		try {
			ConnectorConnections.requireManager();
			ConnectorOrg.Pair pair = ConnectorConnections.owned(name);
			if (!pair.calloutsEnabled) {
				result.outcome = 'calloutsOff';
			} else if (!ConnectorConnections.holdsAccessSet()) {
				result.outcome = ConnectorConnections.grantAccess(pair.name) ? 'accessAdded' : 'accessMissing';
			} else {
				String path = ConnectorConnections.checkPathOf(pair.name);
				HttpRequest request = new HttpRequest();
				request.setEndpoint('callout:' + pair.name + (String.isBlank(path) ? '' : path));
				request.setMethod('GET');
				request.setTimeout(30000);
				HttpResponse response = new Http().send(request);
				result.status = response.getStatusCode();
				result.account = result.status >= 200 && result.status < 300 ? accountOf(response.getBody()) : null;
				result.outcome = 'answered';
			}
		} catch (ConnectorConnections.ConnectorException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (CalloutException unreachable) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Connector',
					'Connector_Log_Unreachable',
					new List<Object>{ name, unreachable.getTypeName() }
				),
				CONTEXT + '.checkConnection',
				ErrorLogger.SEVERITY_WARNING
			);
			result.outcome = 'unreachable';
		} catch (Exception failure) {
			throw shown(failure, 'checkConnection');
		}
		result.page = ConnectorConnections.page();
		return result;
	}

	/**
	 * Removes the key and keeps the connection (R-CN8). A Secret URL has no key apart from its
	 * address, so it is refused: replace or delete it instead.
	 */
	@AuraEnabled
	public static Result disconnect(String name) {
		try {
			ConnectorConnections.requireWriter();
			ConnectorOrg.Pair pair = ConnectorConnections.owned(name);
			if (pair.principal == ConnectorConnections.SECRET_URL) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Error_DisconnectSecretUrl')
				);
			}
			if (pair.keyStored) {
				ConnectorConnections.store().deleteKey(pair.name, pair.principal);
			}
			Result result = new Result();
			result.outcome = 'disconnected';
			result.page = ConnectorConnections.page();
			return result;
		} catch (Exception failure) {
			throw shown(failure, 'disconnect');
		}
	}

	/** Removes both credentials and the key, unless a recipe names the connection (R-CN8). */
	@AuraEnabled
	public static Result deleteConnection(String name) {
		try {
			ConnectorConnections.requireWriter();
			ConnectorOrg.Pair pair = ConnectorConnections.owned(name);
			if (ConnectorRecipes.connectionInUse(pair.name)) {
				throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Error_InUse'));
			}
			ConnectorConnections.store().remove(pair.name, true);
			ConnectorConnections.forget(pair.name);
			Result result = new Result();
			result.outcome = 'deleted';
			result.page = ConnectorConnections.page();
			return result;
		} catch (Exception failure) {
			throw shown(failure, 'deleteConnection');
		}
	}

	/**
	 * Best effort: takes away what a failed create made, so no half connection is left; if that
	 * fails too, the Error Log names the credentials to delete in Setup.
	 */
	private static void undo(String name, Boolean externalMade, Boolean namedMade) {
		if (!externalMade) {
			return;
		}
		try {
			ConnectorConnections.store().remove(name, namedMade);
		} catch (Exception leftOver) {
			ErrorLogger.logMessage(
				BarnHelp.text('Connector', 'Connector_Log_UndoFailed', new List<Object>{ name }),
				CONTEXT + '.undo',
				ErrorLogger.SEVERITY_WARNING
			);
		}
	}

	/**
	 * The account a check answer names (F11): the first text, 80 characters at most, under a
	 * key such as `account_name`, `login` or `email`, at the top of a JSON object or inside its
	 * `account`, `user` or `data` object. Null when the answer names none.
	 */
	@TestVisible
	private static String accountOf(String body) {
		if (String.isBlank(body) || body.length() > 100000) {
			return null;
		}
		Object parsed;
		try {
			parsed = JSON.deserializeUntyped(body);
		} catch (Exception notJson) {
			return null;
		}
		if (!(parsed instanceof Map<String, Object>)) {
			return null;
		}
		Map<String, Object> top = (Map<String, Object>) parsed;
		List<Map<String, Object>> places = new List<Map<String, Object>>{ top };
		for (String nested : new List<String>{ 'account', 'user', 'data' }) {
			if (top.get(nested) instanceof Map<String, Object>) {
				places.add((Map<String, Object>) top.get(nested));
			}
		}
		for (Map<String, Object> place : places) {
			for (String key : ACCOUNT_KEYS) {
				Object value = place.get(key);
				if (value instanceof String && String.isNotBlank((String) value)) {
					return ((String) value).trim().left(80);
				}
			}
		}
		return null;
	}

	/**
	 * The failure text with the secret, and each run of 6 or more letters and digits in it,
	 * replaced by `****` (F7). The secret passes through and is not kept (F8).
	 */
	private static String redacted(String message, String secret) {
		String detail = String.valueOf(message);
		if (String.isNotBlank(secret)) {
			detail = detail.replace(secret, '****');
			for (String part : secret.split('[^A-Za-z0-9]')) {
				detail = part.length() >= 6 ? detail.replace(part, '****') : detail;
			}
		}
		return detail;
	}

	/** A refusal written for a person as it is; anything else as Core's unexpected error, logged. */
	private static AuraHandledException shown(Exception failure, String method) {
		if (failure instanceof ConnectorConnections.ConnectorException) {
			return UserErrors.message(failure.getMessage());
		}
		return UserErrors.wrap(failure, CONTEXT + '.' + method, true);
	}
}
