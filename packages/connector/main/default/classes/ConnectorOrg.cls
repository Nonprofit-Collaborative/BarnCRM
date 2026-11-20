/**
 * The org's credential store as BarnCRM Connector reads it (CN-01, canonical model 29CN1): the
 * `BarnConn_` External and Named Credentials, their principals and the "BarnCRM Connections"
 * permission set's principal access. Nothing here takes or returns a key: every key write is
 * made inline in `ConnectorConnectionsController` (review F8), which asks `fake` whether to call
 * `ConnectApi` or record the input for a test.
 *
 * Tests replace the instance (`ConnectorConnections.org`) with a subclass, since a test cannot
 * create a Named Credential.
 */
public virtual with sharing class ConnectorOrg {
	/** True only in a test's subclass: key writes are recorded instead of sent to `ConnectApi`. */
	public Boolean fake = false;

	/** What one credential pair holds, names and status only. */
	public class Pair {
		public String name;
		public String label;
		/** The principal's name, which is the auth kind (R-CN2). */
		public String principal;
		/** The Named Credential's URL. Server side only: never returned to the browser (F5). */
		public String url;
		public Boolean linked = false;
		public Boolean calloutsEnabled = false;
		public Boolean keyStored = false;
	}

	/** The org's own `BarnConn_` External Credential names and labels, at most 50. */
	public virtual Map<String, String> labelsByName() {
		Map<String, String> found = new Map<String, String>();
		for (
			ConnectApi.ExternalCredential row : ConnectApi.NamedCredentials.getExternalCredentials().externalCredentials
		) {
			if (
				found.size() < 50 &&
				row.developerName != null &&
				row.developerName.startsWith(ConnectorConnections.PREFIX) &&
				String.isBlank(row.createdByNamespace)
			) {
				found.put(row.developerName, row.masterLabel);
			}
		}
		return found;
	}

	/** The pair's status from `ConnectApi`, or null when either credential cannot be read. */
	public virtual Pair read(String name, String label) {
		try {
			Pair pair = new Pair();
			pair.name = name;
			pair.label = label;
			ConnectApi.NamedCredential named = ConnectApi.NamedCredentials.getNamedCredential(name);
			pair.url = named.calloutUrl;
			pair.calloutsEnabled = String.valueOf(named.calloutStatus) == 'Enabled';
			for (ConnectApi.ExternalCredential link : named.externalCredentials) {
				pair.linked = pair.linked || link.developerName == name;
			}
			ConnectApi.ExternalCredential external = ConnectApi.NamedCredentials.getExternalCredential(name);
			for (ConnectApi.ExternalCredentialPrincipal principal : external.principals) {
				pair.principal = principal.principalName;
				pair.keyStored = String.valueOf(principal.authenticationStatus) == 'Configured';
			}
			return pair;
		} catch (Exception unreadable) {
			return null;
		}
	}

	/**
	 * The Ids of the `BarnConn_` principals by credential name: the Id `ConnectApi` gives a named
	 * principal, which is the setup entity a permission set's principal access names.
	 */
	public virtual Map<String, Id> principalIds() {
		Map<String, Id> found = new Map<String, Id>();
		for (String name : labelsByName().keySet()) {
			try {
				ConnectApi.ExternalCredential external = ConnectApi.NamedCredentials.getExternalCredential(name);
				for (ConnectApi.ExternalCredentialPrincipal principal : external.principals) {
					if (String.isNotBlank(principal.id)) {
						found.put(name, Id.valueOf(principal.id));
					}
				}
			} catch (Exception unreadable) {
				continue;
			}
		}
		return found;
	}

	/** The setup entities the permission set gives access to, by Id. */
	public virtual Set<Id> grantedEntities(Id permissionSetId) {
		Set<Id> found = new Set<Id>();
		for (SetupEntityAccess row : [
			SELECT SetupEntityId
			FROM SetupEntityAccess
			WHERE ParentId = :permissionSetId
			WITH SYSTEM_MODE
			LIMIT 1000
		]) {
			found.add(row.SetupEntityId);
		}
		return found;
	}

	/** Adds the principal to the permission set (R-CN7); throws when Salesforce refuses it. */
	public virtual void grant(Id permissionSetId, Id principalId) {
		Database.insert(
			new SetupEntityAccess(ParentId = permissionSetId, SetupEntityId = principalId),
			AccessLevel.SYSTEM_MODE
		);
	}

	/** Creates the External Credential (Custom protocol, one named principal); no key. */
	public virtual void createExternal(ConnectApi.ExternalCredentialInput input) {
		ConnectApi.NamedCredentials.createExternalCredential(input);
	}

	/** Removes the principal's key; the connection stays (Disconnect, R-CN8). */
	public virtual void deleteKey(String name, String principal) {
		ConnectApi.NamedCredentials.deleteCredential(
			name,
			principal,
			ConnectApi.CredentialPrincipalType.NamedPrincipal
		);
	}

	/**
	 * Removes both credentials (Delete, R-CN8) where Apex can, and answers whether it did. The
	 * `ConnectApi.NamedCredentials` BarnCRM compiles against (API 67.0, as the offline compile
	 * check knows it) has no delete for a Named or External Credential, so this answers false
	 * and the page shows the Setup step. Once an org test confirms a delete method, it goes here
	 * and nothing else changes.
	 */
	public virtual Boolean remove(String name) {
		return false;
	}

	/** Records a key write in a test; never called when `fake` is false. */
	public virtual void record(ConnectApi.CredentialInput input, Boolean isUpdate) {
		throw new ConnectorConnections.ConnectorException('Not a test');
	}

	/** Records a Named Credential write in a test; never called when `fake` is false. */
	public virtual void record(ConnectApi.NamedCredentialInput input, Boolean isUpdate) {
		throw new ConnectorConnections.ConnectorException('Not a test');
	}
}
