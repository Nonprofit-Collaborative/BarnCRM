/**
 * The Merge Records area (C-62): the view lists only merges of BarnCRM objects, undo works on
 * one merge, and someone without Manage BarnCRM Settings is refused.
 */
@IsTest(testFor='ApexClass:GenericMergeController, ApexClass:AutoMergeController')
private class GenericMergeControllerTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.admin();
		TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' });
	}

	private static Import_Template__c mapping(String name) {
		Import_Template__c template = ImportTestDataFactory.template(
			ImportTestDataFactory.donorMapping(),
			ImportTemplateService.RULE_EMAIL
		);
		template.Name = name;
		update template;
		return template;
	}

	@IsTest
	static void listsAndUndoesOneMerge() {
		System.runAs(TestUsers.admin()) {
			BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
			settings.Generic_Merge_Enabled__c = true;
			HouseholdTestDataFactory.save(settings);
			Import_Template__c keep = mapping('Gifts 2025');
			Import_Template__c other = mapping('Gifts 2025 copy');
			String objectName = Import_Template__c.SObjectType.getDescribe(
					SObjectDescribeOptions.DEFERRED
				)
				.getName();
			GenericMergeController.mergeRecords(objectName, keep.Id, other.Id, new List<String>());

			Test.startTest();
			GenericMergeController.PanelView view = GenericMergeController.getView();
			Assert.isTrue(view.enabled, 'Merge Records is on');
			Assert.areEqual(1, view.merges.size(), 'The merge is listed');
			Assert.isTrue(view.merges[0].canUndo, 'And can be undone');
			Assert.areEqual(
				0,
				AutoMergeController.getView().runs.size(),
				'Auto-merge lists only people merges'
			);
			view = GenericMergeController.undo(view.merges[0].journalId);
			Test.stopTest();

			Assert.areEqual(AutoMergeService.UNDONE, view.merges[0].status, 'Undone');
			Assert.isFalse(view.merges[0].canUndo, 'Nothing left to undo');
		}
	}

	@IsTest
	static void refusesSomeoneWhoCannotManageSettings() {
		User staff = TestUsers.withPermissionSets(new List<String>{ 'BarnCRM_Staff' });
		System.runAs(staff) {
			Test.startTest();
			try {
				GenericMergeController.getView();
				Assert.fail('Merge Records needs Manage BarnCRM Settings');
			} catch (AuraHandledException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Told why');
			}
			Test.stopTest();
		}
	}
}
