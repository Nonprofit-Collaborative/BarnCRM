/**
 * The real credential store reads and writes of BarnCRM Connector (CN-01, canonical model 29CN1).
 * A test cannot create a Named Credential, so these run `ConnectorOrg` itself against names the org
 * does not hold: every read answers "nothing" and every write is refused, which is what the
 * controller's fake replaces in the other tests. The permission set principal access is real.
 */
@IsTest(testFor='ApexClass:ConnectorOrg')
private class ConnectorOrgTest {
	private static final String MISSING = 'BarnConn_Rest_NoSuchCredential';

	@IsTest
	static void aCredentialThatCannotBeReadIsNullNotAnError() {
		Test.startTest();
		ConnectorOrg.Pair pair = new ConnectorOrg().read(MISSING, 'Missing');
		Test.stopTest();

		Assert.isNull(pair, 'A pair whose credentials are not there is not shown.');
	}

	@IsTest
	static void anUnknownCredentialCannotBeChangedOrRemoved() {
		ConnectorOrg org = new ConnectorOrg();
		Integer refused = 0;

		Test.startTest();
		try {
			org.deleteKey(MISSING, 'Key');
		} catch (Exception unknown) {
			refused++;
		}
		try {
			org.remove(MISSING, true);
		} catch (Exception unknown) {
			refused++;
		}
		try {
			org.remove(MISSING, false);
		} catch (Exception unknown) {
			refused++;
		}
		try {
			org.createExternal(new ConnectApi.ExternalCredentialInput());
		} catch (Exception incomplete) {
			refused++;
		}
		Test.stopTest();

		Assert.areEqual(4, refused, 'Each write to a credential that is not there is refused.');
	}

	@IsTest
	static void theBaseStoreRecordsNothingAndSaysSo() {
		ConnectorOrg org = new ConnectorOrg();
		Assert.isFalse(org.fake, 'The real store never fakes a write.');
		String keyMessage;
		String namedMessage;
		try {
			org.record(new ConnectApi.CredentialInput(), true);
		} catch (ConnectorConnections.ConnectorException refused) {
			keyMessage = refused.getMessage();
		}
		try {
			org.record(new ConnectApi.NamedCredentialInput(), false);
		} catch (ConnectorConnections.ConnectorException refused) {
			namedMessage = refused.getMessage();
		}
		Assert.areEqual('Not a test', keyMessage);
		Assert.areEqual('Not a test', namedMessage);
	}

	private static ConnectApi.ExternalCredential external(String developerName, String namespace) {
		ConnectApi.ExternalCredential row = new ConnectApi.ExternalCredential();
		row.developerName = developerName;
		row.masterLabel = 'Label ' + developerName;
		row.createdByNamespace = namespace;
		row.principals = new List<ConnectApi.ExternalCredentialPrincipal>();
		return row;
	}

	private static ConnectApi.NamedCredential named(String linkedTo, Boolean enabled) {
		ConnectApi.NamedCredential row = new ConnectApi.NamedCredential();
		row.calloutUrl = 'https://api.example.org';
		row.calloutStatus = enabled ? ConnectApi.CalloutStatus.Enabled : ConnectApi.CalloutStatus.Disabled;
		row.externalCredentials = new List<ConnectApi.ExternalCredential>{ external(linkedTo, null) };
		return row;
	}

	private static ConnectApi.ExternalCredentialPrincipal principal(
		String principalName,
		ConnectApi.CredentialAuthenticationStatus status
	) {
		ConnectApi.ExternalCredentialPrincipal row = new ConnectApi.ExternalCredentialPrincipal();
		row.principalName = principalName;
		row.authenticationStatus = status;
		row.id = UserInfo.getUserId();
		return row;
	}

	@IsTest
	static void onlyTheOrgsOwnPrefixedCredentialsAreListedAtMostFifty() {
		List<ConnectApi.ExternalCredential> rows = new List<ConnectApi.ExternalCredential>{
			external('BarnConn_Rest_Mine', null),
			external('BarnConn_Rest_Packaged', 'other'),
			external('Someone_Else', null),
			external(null, null)
		};
		for (Integer i = 0; i < 60; i++) {
			rows.add(external('BarnConn_Rest_Many' + i, null));
		}

		Test.startTest();
		Map<String, String> found = ConnectorOrg.labelsFrom(rows);
		Test.stopTest();

		Assert.areEqual(50, found.size(), 'At most 50.');
		Assert.areEqual('Label BarnConn_Rest_Mine', found.get('BarnConn_Rest_Mine'));
		Assert.isFalse(found.containsKey('BarnConn_Rest_Packaged'), 'A package\'s credential is not offered.');
		Assert.isFalse(found.containsKey('Someone_Else'), 'Only the prefix.');
	}

	@IsTest
	static void aConfiguredPairReadsItsAddressLinkAndKeyStatus() {
		ConnectApi.ExternalCredential held = external(MISSING, null);
		held.principals.add(
			principal(ConnectorConnections.SECRET_URL, ConnectApi.CredentialAuthenticationStatus.Configured)
		);

		Test.startTest();
		ConnectorOrg.Pair pair = ConnectorOrg.pairFrom(MISSING, 'Mine', named(MISSING, true), held);
		Test.stopTest();

		Assert.areEqual(MISSING, pair.name);
		Assert.areEqual('Mine', pair.label);
		Assert.areEqual('https://api.example.org', pair.url, 'Kept server side.');
		Assert.isTrue(pair.calloutsEnabled);
		Assert.isTrue(pair.linked, 'The Named Credential points at its own External Credential.');
		Assert.isTrue(pair.keyStored);
		Assert.areEqual(ConnectorConnections.SECRET_URL, pair.principal);
		Assert.areEqual(UserInfo.getUserId(), pair.principalId);
	}

	@IsTest
	static void aCustomPrincipalWhoseKeyCannotBeAskedForReadsAsNoKey() {
		ConnectApi.ExternalCredential held = external(MISSING, null);
		held.principals.add(principal('Key', ConnectApi.CredentialAuthenticationStatus.Unknown));

		Test.startTest();
		ConnectorOrg.Pair pair = ConnectorOrg.pairFrom(MISSING, 'Mine', named('Another', false), held);
		Test.stopTest();

		Assert.isFalse(pair.calloutsEnabled);
		Assert.isFalse(pair.linked, 'Linked to another External Credential.');
		Assert.isFalse(pair.keyStored, 'Salesforce will not say, so no key is claimed.');
		Assert.areEqual('Key', pair.principal);
	}

	@IsTest
	static void principalAccessIsGrantedToAPermissionSetAndReadBack() {
		ConnectorOrg org = new ConnectorOrg();
		PermissionSet target = new PermissionSet(Name = 'Connector_Org_Test', Label = 'Connector Org Test');
		insert as system target;
		Id apexClass = [SELECT Id FROM ApexClass WHERE Name = 'ConnectorOrg' WITH SYSTEM_MODE LIMIT 1].Id;

		Test.startTest();
		Set<Id> before = org.grantedEntities(target.Id);
		org.grant(target.Id, apexClass);
		Set<Id> after = org.grantedEntities(target.Id);
		Test.stopTest();

		Assert.isTrue(before.isEmpty(), 'A new set holds nothing.');
		Assert.areEqual(new Set<Id>{ apexClass }, after);
	}
}
