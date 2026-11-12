/**
 * BarnCRM's roles get the LWC Builder sets (ADR-0203 lwc builder module, decision 9): BarnCRM
 * Admin holders LWC Builder Admin, Team Member LWC Builder Staff and Read Only LWC Builder Read
 * Only, at install, at Turn on and with the hourly access check.
 */
@IsTest(testFor='ApexClass:LwcBuilderAccessSync')
private class LwcBuilderAccessSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Map<String, Id> people() {
		Map<String, Id> ids = new Map<String, Id>{
			'Outsider' => TestUsers.standardUser('Outsider').Id
		};
		Map<String, String> groupByName = new Map<String, String>{
			'Member' => 'Program_Staff',
			'Reader' => 'Read_Only',
			'Boss' => 'BarnCRM_Admin_Group'
		};
		List<PermissionSetAssignment> roles = new List<PermissionSetAssignment>();
		for (String name : groupByName.keySet()) {
			Id userId = TestUsers.standardUser(name).Id;
			ids.put(name, userId);
			roles.add(
				new PermissionSetAssignment(
					AssigneeId = userId,
					PermissionSetGroupId = TestDataFactory.prepareRoleGroup(groupByName.get(name))
						.Id
				)
			);
		}
		insert roles;
		return ids;
	}

	private static Set<String> setsOf(Id userId) {
		Set<String> names = new Set<String>();
		for (PermissionSetAssignment row : [
			SELECT PermissionSet.Name
			FROM PermissionSetAssignment
			WHERE AssigneeId = :userId AND PermissionSet.Name LIKE 'LWC_Builder_%'
			WITH SYSTEM_MODE
		]) {
			names.add(row.PermissionSet.Name);
		}
		return names;
	}

	@IsTest
	static void givesEachRoleItsLwcBuilderSet() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			Boolean more = LwcBuilderAccessSync.syncOnce();
			Boolean again = LwcBuilderAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isFalse(again, 'And a second pass finds nothing to give');
			Map<String, String> expected = new Map<String, String>{
				'Member' => 'LWC_Builder_Staff',
				'Reader' => 'LWC_Builder_Read_Only',
				'Boss' => LwcBuilderAccessSync.ADMIN_SET
			};
			for (String name : expected.keySet()) {
				Assert.areEqual(
					new Set<String>{ expected.get(name) },
					setsOf(ids.get(name)),
					name + ' gets their role\'s set and no other'
				);
			}
			Assert.isTrue(setsOf(ids.get('Outsider')).isEmpty(), 'No role, no set');
		}
	}

	@IsTest
	static void theHourlyAccessCheckQueuesTheSync() {
		System.runAs(TestUsers.admin()) {
			Map<String, Id> ids = people();

			Test.startTest();
			ModuleAccessSyncs.requestAll();
			Test.stopTest();

			Assert.isTrue(
				setsOf(ids.get('Member')).contains('LWC_Builder_Staff'),
				'Someone given a role since the install gets the set within the hour'
			);
		}
	}
}
