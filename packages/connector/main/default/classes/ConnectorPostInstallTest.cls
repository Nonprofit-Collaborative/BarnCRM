/**
 * Dana installs BarnCRM Connector and can open Super Connector straight away: she holds BarnCRM
 * Connector Admin, it is never given twice, and no connection or key is created for her.
 */
@IsTest(testFor='ApexClass:ConnectorPostInstall')
private class ConnectorPostInstallTest {
	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :ConnectorConnections.ADMIN_SET
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theInstallerGetsTheAdminSetOnceAndNothingElseIsCreated() {
		System.runAs(TestUsers.admin()) {
			Id installer = TestDataFactory.createUser('Installer', new List<String>()).Id;

			Test.startTest();
			Test.testInstall(new ConnectorPostInstall(), null);
			new ConnectorPostInstall().runSetup(installer);
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(installer), 'The installer holds BarnCRM Connector Admin');
			Assert.isNull(ConnectorConnections.accessSet(), 'No Connections set until a connection exists');
		}
	}
}
