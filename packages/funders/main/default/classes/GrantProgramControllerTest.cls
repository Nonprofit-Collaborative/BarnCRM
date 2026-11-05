/**
 * The Program card's server side (F-01, R-GN4): what it shows with and without the Programs
 * module, a program that has gone, saving and clearing, and refusing what is not a program.
 */
@IsTest(testFor='ApexClass:GrantProgramController')
private class GrantProgramControllerTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWithInstalledModules();
	}

	private static Grant__c grant() {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		Grant__c grant = GrantTestData.grant('Literacy', funder.Id, GrantService.STAGE_PROSPECT);
		insert grant;
		return grant;
	}

	private static String storedProgram(Id grantId) {
		return [SELECT Program_Id__c FROM Grant__c WHERE Id = :grantId WITH SYSTEM_MODE]
		.Program_Id__c;
	}

	@IsTest
	static void theCardOffersTheProgramsAndSavesTheChoice() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = grant();
			Schema.SObjectType programType = NamespaceUtil.packagedObjectType('Program__c');

			Test.startTest();
			GrantProgramController.ProgramCard card = GrantProgramController.getProgram(grant.Id);
			if (programType == null) {
				Test.stopTest();
				Assert.isFalse(card.available, 'Without Programs there is nothing to choose');
				Assert.isFalse(card.canEdit, 'And nothing to save');
				return;
			}
			SObject program = programType.newSObject();
			program.put('Name', 'Tutoring');
			insert program;
			GrantProgramController.setProgram(grant.Id, String.valueOf(program.Id));
			GrantProgramController.ProgramCard chosen = GrantProgramController.getProgram(grant.Id);
			Test.stopTest();

			Assert.isTrue(card.available, 'Programs can be chosen');
			Assert.isTrue(card.canEdit, 'By the admin');
			Assert.isNull(card.programId, 'None yet');
			Assert.areEqual(String.valueOf(program.Id), chosen.programId, 'Saved');
			Assert.areEqual('Tutoring', chosen.programName, 'By name');
			Assert.isFalse(chosen.missing, 'It is there');
			Assert.areEqual(1, chosen.options.size(), 'The one program is offered');
			Assert.areEqual('Tutoring', chosen.options[0].label, 'Labelled by name');

			delete program;
			GrantProgramController.ProgramCard gone = GrantProgramController.getProgram(grant.Id);
			Assert.isTrue(gone.missing, 'A deleted program is shown as gone');
		}
	}

	@IsTest
	static void clearingWorksAndAnythingButAProgramIsRefused() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = grant();

			Test.startTest();
			GrantProgramController.setProgram(grant.Id, '');
			String refusal;
			try {
				GrantProgramController.setProgram(grant.Id, grant.Id);
			} catch (AuraHandledException e) {
				refusal = e.getMessage();
			}
			Test.stopTest();

			Assert.isNull(storedProgram(grant.Id), 'Cleared');
			Assert.areEqual(Label.Funders_Grant_BadProgram, refusal, 'A grant is not a program');
		}
	}

	@IsTest
	static void aGrantThePersonCannotSeeGivesAnEmptyCard() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Grant__c grant = grant();
			Id gone = grant.Id;
			delete grant;

			Test.startTest();
			GrantProgramController.ProgramCard card = GrantProgramController.getProgram(gone);
			Test.stopTest();

			Assert.isFalse(card.available, 'Nothing to show');
			Assert.isNull(card.programId, 'No program');
		}
	}
}
