/**
 * Tests for BarnCRMPermissions: the settings permission is held by BarnCRM Admin and not by
 * staff, so every page that asks it gets the same answer.
 */
@IsTest(testFor='ApexClass:BarnCRMPermissions')
private class BarnCRMPermissionsTest {
	@TestSetup
	static void createStaffUser() {
		TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' });
	}

	@IsTest
	static void anAdministratorMayManageSettings() {
		System.runAs(TestUsers.admin()) {
			Assert.isTrue(
				BarnCRMPermissions.canManageSettings(),
				'BarnCRM Admin carries the Manage BarnCRM Settings permission'
			);
		}
	}

	@IsTest
	static void staffMayNotManageSettings() {
		System.runAs(TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' })) {
			Assert.isFalse(
				BarnCRMPermissions.canManageSettings(),
				'BarnCRM Staff works with records but does not configure the app'
			);
		}
	}

	@IsTest
	static void aSaveWithoutThePermissionIsRefusedOutsideTheInstall() {
		System.runAs(TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' })) {
			Assert.isFalse(BarnCRMPermissions.isInstallRunning(), 'No install is running in a normal request');
			Assert.isFalse(BarnCRMPermissions.canSaveSettings(), 'Staff cannot save settings');
			try {
				SettingsService.saveSystemValue('Household_Name_Pattern__c', 'The {LastName} Refused Family');
				Assert.fail('A save without the permission must be refused');
			} catch (SettingsWriter.PermissionException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_Settings_PermissionRequiredError'),
					refused.getMessage(),
					'The refusal names the permission to ask for'
				);
			}
		}
	}

	@IsTest
	static void aSaveWithoutThePermissionIsAllowedWhileTheInstallRuns() {
		System.runAs(TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' })) {
			BarnCRMPermissions.enterInstall();
			Assert.isTrue(BarnCRMPermissions.canSaveSettings(), 'The install handler may save');
			BarnCRMPermissions.leaveInstall();
			Assert.isFalse(BarnCRMPermissions.canSaveSettings(), 'The allowance ends with the install');
			Assert.isFalse(BarnCRMPermissions.isInstallRunning(), 'The flag is off again');
		}
	}
}
