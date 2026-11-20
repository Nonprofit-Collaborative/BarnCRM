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
		@AuraEnabled
		public ConnectorConnections.ConnectionsPage page;
	}

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
	 * Creates the External Credential, the Named Credential and, except for a Secret URL, the
	 * principal's key, then the principal access (F12). The server makes the name (F2).
	 */
	@AuraEnabled
	public static Result createConnection(
		String label,
		String authKind,
		String baseUrl,
		String headerName,
		String userName,
		String secret
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
			String url = ConnectorConnections.checkedUrl(kind == ConnectorConnections.SECRET_URL ? secret : baseUrl);
			if (kind != ConnectorConnections.SECRET_URL && String.isBlank(secret)) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Error_KeyRequired')
				);
			}
			if (kind == ConnectorConnections.BASIC && String.isBlank(userName)) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Error_UserRequired')
				);
			}
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
			if (kind != ConnectorConnections.SECRET_URL) {
				ConnectApi.CredentialInput credential = ConnectorConnections.credentialInput(name, kind);
				if (kind == ConnectorConnections.BASIC) {
					credential.credentials.put(
						ConnectorConnections.USER_PARAMETER,
						ConnectorConnections.plainValue(userName.trim())
					);
				}
				ConnectApi.CredentialValueInput key = new ConnectApi.CredentialValueInput();
				key.value = secret;
				key.encrypted = true;
				credential.credentials.put(ConnectorConnections.SECRET_PARAMETER.get(kind), key);
				if (org.fake) {
					org.record(credential, false);
				} else {
					ConnectApi.NamedCredentials.createCredential(credential);
				}
			}
		} catch (ConnectorConnections.ConnectorException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception failure) {
			String detail = String.valueOf(failure.getMessage());
			if (String.isNotBlank(secret)) {
				detail = detail.replace(secret, '****');
				for (String part : secret.split('[^A-Za-z0-9]')) {
					detail = part.length() >= 6 ? detail.replace(part, '****') : detail;
				}
			}
			ConnectorConnections.logRedacted(CONTEXT + '.createConnection', failure.getTypeName(), detail);
			undo(name, externalMade, namedMade);
			throw UserErrors.message(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'));
		}
		Result result = new Result();
		try {
			result.outcome = ConnectorConnections.grantAccess(name) ? 'created' : 'createdAccessMissing';
			result.page = ConnectorConnections.page();
		} catch (Exception failure) {
			throw shown(failure, 'createConnection');
		}
		return result;
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
			String detail = String.valueOf(failure.getMessage());
			if (String.isNotBlank(secret)) {
				detail = detail.replace(secret, '****');
				for (String part : secret.split('[^A-Za-z0-9]')) {
					detail = part.length() >= 6 ? detail.replace(part, '****') : detail;
				}
			}
			ConnectorConnections.logRedacted(CONTEXT + '.replaceKey', failure.getTypeName(), detail);
			throw UserErrors.message(BarnHelp.text('Connector', 'Connector_Error_SaveFailed'));
		}
		Result result = new Result();
		try {
			ConnectorConnections.journalKeyReplaced(pair);
			result.outcome = 'replaced';
			result.page = ConnectorConnections.page();
		} catch (Exception failure) {
			throw shown(failure, 'replaceKey');
		}
		return result;
	}

	/**
	 * One GET of the base URL through the connection, as the person checking. Before it: callouts
	 * must be on (the Setup step) and the person must hold the Connections set; giving it is a
	 * setup write, after which a callout may not follow, so the page asks to check again.
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
				HttpRequest request = new HttpRequest();
				request.setEndpoint('callout:' + pair.name);
				request.setMethod('GET');
				request.setTimeout(30000);
				result.status = new Http().send(request).getStatusCode();
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

	/** Removes the key and keeps the connection (R-CN8). */
	@AuraEnabled
	public static Result disconnect(String name) {
		try {
			ConnectorConnections.requireWriter();
			ConnectorOrg.Pair pair = ConnectorConnections.owned(name);
			if (pair.principal != ConnectorConnections.SECRET_URL && pair.keyStored) {
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

	/** A refusal written for a person as it is; anything else as Core's unexpected error, logged. */
	private static AuraHandledException shown(Exception failure, String method) {
		if (failure instanceof ConnectorConnections.ConnectorException) {
			return UserErrors.message(failure.getMessage());
		}
		return UserErrors.wrap(failure, CONTEXT + '.' + method, true);
	}
}
