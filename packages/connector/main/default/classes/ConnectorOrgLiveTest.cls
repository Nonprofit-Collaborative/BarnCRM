/**
 * The credential list and reads of `ConnectorOrg` against the org's real credential store. `ConnectApi`
 * answers nothing in a data-siloed test, so this class alone sees all data. It only reads: it creates,
 * changes and removes no credential, and holds to what any org must answer, since the credentials an
 * org holds vary.
 */
@IsTest(SeeAllData=true testFor='ApexClass:ConnectorOrg')
private class ConnectorOrgLiveTest {
	@IsTest
	static void theRealStoreOffersOnlyThePrefixedCredentialsOfTheOrgItself() {
		ConnectorOrg org = new ConnectorOrg();

		Test.startTest();
		Map<String, String> labels = org.labelsByName();
		Test.stopTest();

		Assert.isNotNull(labels, 'A list, empty or not.');
		Assert.isTrue(labels.size() <= 50, 'At most 50.');
		for (String name : labels.keySet()) {
			Assert.isTrue(name.startsWith(ConnectorConnections.PREFIX), 'Only BarnConn_ credentials: ' + name);
		}
	}

	@IsTest
	static void aCredentialPairIsReadOrLeftOutNeverHalfRead() {
		ConnectorOrg org = new ConnectorOrg();
		List<String> names = new List<String>{ 'BarnConn_Rest_NoSuchCredential' };
		for (NamedCredential held : [SELECT DeveloperName FROM NamedCredential LIMIT 3]) {
			names.add(held.DeveloperName);
		}

		Test.startTest();
		for (String name : names) {
			ConnectorOrg.Pair pair = org.read(name, 'Label ' + name);
			if (pair != null) {
				Assert.areEqual(name, pair.name);
				Assert.areEqual('Label ' + name, pair.label);
				Assert.isNotNull(pair.keyStored, 'The key flag is always answered.');
			}
		}
		Test.stopTest();

		Assert.isNull(org.read(names[0], 'Missing'), 'A credential that is not there is not shown.');
	}
}
