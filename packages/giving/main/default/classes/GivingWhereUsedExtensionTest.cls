/**
 * Giving's part of Where Used (C-59): an import mapping column that loads a gift field is found
 * by that field, a people column is left to Core, and Core finds this extension by name.
 */
@IsTest(testFor='ApexClass:GivingWhereUsedExtension')
private class GivingWhereUsedExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	@IsTest
	static void aGiftColumnIsFoundByItsField() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			insert as system new Import_Template__c(
				Name = 'Gift File',
				Template_Key__c = 'where_used_gift_file',
				Column_Mapping_JSON__c = '{"version":1,"columns":[{"source":"Amount","target":"Gift.Amount__c"},{"source":"Mail","target":"Contact1.Email"}],"defaults":[{"target":"Gift.Type__c","value":"Check"}]}',
				Default_Values_JSON__c = '{"version":1,"defaults":[]}',
				Person_Mode__c = ImportTemplateService.PERSON_MODE_CONTACTS,
				Is_Package_Default__c = false,
				Active__c = true
			);
			GivingWhereUsedExtension extension = new GivingWhereUsedExtension();

			Test.startTest();
			List<WhereUsedService.Reference> amount = extension.references(
				WhereUsedService.target('Gift__c', 'Amount__c')
			);
			List<WhereUsedService.Reference> type = extension.references(
				WhereUsedService.target('Gift__c', 'Type__c')
			);
			List<WhereUsedService.Reference> email = extension.references(
				WhereUsedService.target('Contact', 'Email')
			);
			Test.stopTest();

			Assert.areEqual(1, amount.size());
			Assert.areEqual('Gift File', amount[0].getName());
			Assert.areEqual(
				new List<String>{
					String.format(
						System.Label.Core_WhereUsed_PartColumn,
						new List<Object>{ 'Amount' }
					)
				},
				amount[0].getParts()
			);
			Assert.areEqual(
				new List<String>{ System.Label.Core_WhereUsed_PartDefault },
				type[0].getParts(),
				'A default value names the field too.'
			);
			Assert.isTrue(email.isEmpty(), 'People columns are Core\'s to read.');
			Assert.isInstanceOfType(
				WhereUsedExtensions.findAll().get('GivingWhereUsedExtension'),
				GivingWhereUsedExtension.class
			);
		}
	}

	@IsTest
	static void theDonorLevelSourceIsFoundOnPeopleAndOrganizations() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			String source = DonorLevelService.sourceField();
			String other = source == 'Largest_Gift__c' ? 'Total_Giving__c' : 'Largest_Gift__c';

			List<WhereUsedService.Reference> onContact = GivingWhereUsedExtension.settingReferences(
				WhereUsedService.target('Contact', source)
			);
			List<WhereUsedService.Reference> onAccount = GivingWhereUsedExtension.settingReferences(
				WhereUsedService.target('Account', source)
			);
			List<WhereUsedService.Reference> notChosen = GivingWhereUsedExtension.settingReferences(
				WhereUsedService.target('Contact', other)
			);

			Assert.areEqual(1, onContact.size());
			Assert.areEqual(1, onAccount.size());
			Assert.areEqual(
				Schema.Giving_Settings__c.Donor_Level_Source_Field__c.getDescribe().getLabel(),
				onContact[0].getName()
			);
			Assert.areEqual(
				System.Label.Core_WhereUsed_BreaksSettingValue,
				onContact[0].getBreaks()
			);
			Assert.isTrue(notChosen.isEmpty(), 'A total the levels do not run on finds nothing.');
		}
	}
}
