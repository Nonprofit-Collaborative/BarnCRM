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
