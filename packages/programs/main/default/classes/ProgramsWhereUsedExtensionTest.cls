/**
 * Programs' part of Where Used (C-59): a program whose eligibility rules read an enrollment field
 * is found by that field and links to the program, another field finds nothing, and Core finds
 * this extension by name.
 */
@IsTest(testFor='ApexClass:ProgramsWhereUsedExtension')
private class ProgramsWhereUsedExtensionTest {
	private static final String ADMIN = 'Programs_Admin';
	private static final String RULES =
		'{"version": 1, "defaultResult": "Review", "rules": [{"id": "r1", "all": [' +
		'{"field": "Referral_Source__c", "operator": "equals", "value": "Self"}],' +
		' "result": "Eligible", "reason": "Self referred"}]}';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN);
	}

	@IsTest
	static void aProgramIsFoundByTheFieldItsRulesRead() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Program__c screened = new Program__c(Name = 'Pantry', Eligibility_Rules__c = RULES);
			Program__c open = new Program__c(Name = 'Open Door');
			insert as system new List<Program__c>{ screened, open };
			ProgramsWhereUsedExtension extension = new ProgramsWhereUsedExtension();

			Test.startTest();
			List<WhereUsedService.Reference> source = extension.references(
				WhereUsedService.target('Enrollment__c', 'Referral_Source__c')
			);
			List<WhereUsedService.Reference> other = extension.references(
				WhereUsedService.target('Enrollment__c', 'Intake_Date__c')
			);
			List<WhereUsedService.Reference> wholeObject = extension.references(
				WhereUsedService.target('Enrollment__c', null)
			);
			Test.stopTest();

			Assert.areEqual(1, source.size(), 'Only the program whose rules read it.');
			Assert.areEqual('Pantry', source[0].getName());
			Assert.areEqual(
				new List<String>{
					Schema.SObjectType.Program__c.fields.Eligibility_Rules__c.getLabel()
				},
				source[0].getParts()
			);
			Assert.areEqual(System.Label.Core_WhereUsed_BreaksModuleRecord, source[0].getBreaks());
			Assert.areEqual('/lightning/r/' + screened.Id + '/view', source[0].editUrl);
			Assert.isTrue(other.isEmpty(), 'A field no rule reads is not listed.');
			Assert.isTrue(wholeObject.isEmpty(), 'The module\'s own object is not reported.');
			Assert.isInstanceOfType(
				WhereUsedExtensions.findAll().get('ProgramsWhereUsedExtension'),
				ProgramsWhereUsedExtension.class
			);
		}
	}

	@IsTest
	static void unreadableRulesNameNothing() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			WhereUsedService.Target target = WhereUsedService.target(
				'Enrollment__c',
				'Referral_Source__c'
			);
			Assert.isFalse(ProgramsWhereUsedExtension.rulesName(target, 'not json'));
			Assert.isFalse(
				ProgramsWhereUsedExtension.rulesName(target, '{"rules": [1, {"all": [2]}]}')
			);
			Assert.isTrue(ProgramsWhereUsedExtension.rulesName(target, RULES));
		}
	}
}
