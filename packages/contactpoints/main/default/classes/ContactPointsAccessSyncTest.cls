/**
 * BarnCRM Admin holders get Contact Point Sync Admin (ADR-NEXT contact point sync module,
 * decision 12), at install, at Turn on and with the hourly access check; nobody else does.
 */
@IsTest(testFor='ApexClass:ContactPointsAccessSync')
private class ContactPointsAccessSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
		TestUsers.standardUser('Boss');
	}

	private static Integer adminSetsHeldBy(Id userId) {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name = :ContactPointsAccessSync.ADMIN_SET
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void givesBarnCrmAdminsTheSetAndNobodyElse() {
		System.runAs(TestUsers.admin()) {
			Id boss = TestUsers.standardUser('Boss').Id;
			insert new PermissionSetAssignment(
				AssigneeId = boss,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('BarnCRM_Admin_Group').Id
			);
			Id member = TestUsers.standardUser('Member').Id;
			insert new PermissionSetAssignment(
				AssigneeId = member,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('Program_Staff').Id
			);

			Test.startTest();
			Boolean more = ContactPointsAccessSync.syncOnce();
			Boolean again = ContactPointsAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isFalse(again, 'And a second pass finds nothing to give');
			Assert.areEqual(1, adminSetsHeldBy(boss), 'The BarnCRM Admin role holds the set');
			Assert.areEqual(0, adminSetsHeldBy(member), 'Staff need nothing: the copy is upkeep');
		}
	}

	@IsTest
	static void theHourlyAccessCheckQueuesTheSync() {
		System.runAs(TestUsers.admin()) {
			Id boss = TestUsers.standardUser('Boss').Id;
			insert new PermissionSetAssignment(
				AssigneeId = boss,
				PermissionSetGroupId = TestDataFactory.prepareRoleGroup('BarnCRM_Admin_Group').Id
			);

			Test.startTest();
			ModuleAccessSyncs.requestAll();
			Test.stopTest();

			Assert.areEqual(1, adminSetsHeldBy(boss), 'Given within the hour');
		}
	}
}
