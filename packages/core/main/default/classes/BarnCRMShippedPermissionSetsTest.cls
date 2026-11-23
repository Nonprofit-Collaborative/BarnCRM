/**
 * The list of permission sets BarnCRM ships (C-65, ADR-0156). scripts/ci/check-shipped-permission-sets.py
 * keeps the list equal to the package directories; this checks it against the org the tests run in,
 * where Core's own sets are always present.
 */
@IsTest(testFor='ApexClass:BarnCRMShippedPermissionSets')
private class BarnCRMShippedPermissionSetsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void theListNamesCoresOwnPermissionSets() {
		System.runAs(TestUsers.admin()) {
			Assert.isFalse(BarnCRMShippedPermissionSets.NAMES.isEmpty(), 'The list is not empty');
			for (String name : new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Staff', 'BarnCRM_Read_Only' }) {
				Assert.isTrue(BarnCRMShippedPermissionSets.NAMES.contains(name), name + ' is on the list');
			}
		}
	}

	@IsTest
	static void coresInstalledSetsAreOnTheList() {
		// The org may also hold sets an earlier build left behind, so only the list's own names
		// are looked up: Core's administrator set is always installed where these tests run.
		System.runAs(TestUsers.admin()) {
			Set<String> installed = new Set<String>();
			for (PermissionSet permissionSet : [
				SELECT Name
				FROM PermissionSet
				WHERE Name IN :BarnCRMShippedPermissionSets.NAMES AND IsOwnedByProfile = FALSE
				WITH SYSTEM_MODE
			]) {
				installed.add(permissionSet.Name);
			}
			Assert.isTrue(
				installed.contains(TestUsers.CORE_ADMIN),
				'Core\'s administrator set is installed and listed'
			);
		}
	}

	@IsTest
	static void everyNameIsAValidApiName() {
		System.runAs(TestUsers.admin()) {
			for (String name : BarnCRMShippedPermissionSets.NAMES) {
				Assert.isTrue(Pattern.matches('[A-Za-z][A-Za-z0-9_]*', name), 'Not an API name: ' + name);
			}
		}
	}
}
