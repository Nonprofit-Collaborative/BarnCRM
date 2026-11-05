/**
 * QA-F2: a checkbox that ships on and was added in an upgrade is turned on once in an org that
 * saved its settings before it existed, and stays as the administrator leaves it afterwards.
 * Core's own settings stand in for any package's (custom settings are visible to tests).
 */
@IsTest(testFor='ApexClass:ShippedDefaultUpgrades, ApexClass:CorePostInstall')
private class ShippedDefaultUpgradesTest {
	private static final List<Schema.SObjectField> ADDED = new List<Schema.SObjectField>{
		BarnCRM_Settings__c.Error_Digest_Include_Admin_Summary__c
	};

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	/** An org that saved its settings before the field existed: the field reads false. */
	private static void savedBeforeTheField(String marker) {
		delete [SELECT Id FROM BarnCRM_Settings__c];
		insert as system new BarnCRM_Settings__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Error_Digest_Include_Admin_Summary__c = false,
			Shipped_Defaults_Applied__c = marker
		);
		SettingsService.clearCaches();
	}

	private static BarnCRM_Settings__c stored() {
		return [
			SELECT Error_Digest_Include_Admin_Summary__c, Shipped_Defaults_Applied__c
			FROM BarnCRM_Settings__c
			WHERE SetupOwnerId = :UserInfo.getOrganizationId()
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void turnsTheSettingOnOnceAndKeepsTheAdministratorsChoice() {
		System.runAs(TestUsers.admin()) {
			savedBeforeTheField(null);

			ShippedDefaultUpgrades.apply('Core', BarnCRM_Settings__c.SObjectType, ADDED);
			Assert.isTrue(stored().Error_Digest_Include_Admin_Summary__c, 'turned on once');
			Assert.areEqual('core:1', stored().Shipped_Defaults_Applied__c, 'marked as applied');

			update as system new BarnCRM_Settings__c(
				Id = stored().Id,
				Error_Digest_Include_Admin_Summary__c = false
			);
			SettingsService.clearCaches();
			ShippedDefaultUpgrades.apply('Core', BarnCRM_Settings__c.SObjectType, ADDED);
			Assert.isFalse(
				stored().Error_Digest_Include_Admin_Summary__c,
				'an administrator who turned it off afterwards keeps it off'
			);
		}
	}

	@IsTest
	static void keepsOtherPackagesCountsAndSkipsWhatWasApplied() {
		System.runAs(TestUsers.admin()) {
			savedBeforeTheField('giving:1');
			ShippedDefaultUpgrades.apply('Core', BarnCRM_Settings__c.SObjectType, ADDED);
			Assert.areEqual('core:1,giving:1', stored().Shipped_Defaults_Applied__c);

			savedBeforeTheField('core:1');
			ShippedDefaultUpgrades.apply('Core', BarnCRM_Settings__c.SObjectType, ADDED);
			Assert.isFalse(
				stored().Error_Digest_Include_Admin_Summary__c,
				'an entry the marker counts is never applied again'
			);
		}
	}

	@IsTest
	static void anOrgThatNeverSavedIsOnlyMarked() {
		System.runAs(TestUsers.admin()) {
			delete [SELECT Id FROM BarnCRM_Settings__c];
			SettingsService.clearCaches();
			ShippedDefaultUpgrades.apply('Core', BarnCRM_Settings__c.SObjectType, ADDED);
			Assert.areEqual('core:1', stored().Shipped_Defaults_Applied__c);
			Assert.isTrue(
				stored().Error_Digest_Include_Admin_Summary__c,
				'the first save carries the shipped default'
			);
		}
	}

	@IsTest
	static void aFailureIsLoggedNotThrown() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			ShippedDefaultUpgrades.apply(null, BarnCRM_Settings__c.SObjectType, ADDED);
			Test.stopTest();
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = :ShippedDefaultUpgrades.CONTEXT
					WITH SYSTEM_MODE
				]
			);
		}
	}

	@IsTest
	static void corePostInstallAppliesCoresList() {
		System.runAs(TestUsers.admin()) {
			savedBeforeTheField(null);
			CorePostInstall.runAsSourceDeploy();
			Assert.isTrue(stored().Error_Digest_Include_Admin_Summary__c);
			Assert.areEqual(
				'core:' + CorePostInstall.SHIPPED_ON_ADDED_IN_UPGRADES.size(),
				stored().Shipped_Defaults_Applied__c
			);
		}
	}
}
