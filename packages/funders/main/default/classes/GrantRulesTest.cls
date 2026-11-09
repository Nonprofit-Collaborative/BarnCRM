/**
 * The grant rules (canonical model 29ZH): stage dates are stamped and a typed date is kept
 * (R-GN3), the program is a program's record identifier in full (R-GN4), amounts are not negative
 * and the award period runs forward (R-GN2), and a funder with grants is kept (R-GN5).
 */
@IsTest(testFor='ApexClass:GrantService, ApexClass:GrantRulesHandler, ApexClass:GrantDatesHandler')
private class GrantRulesTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.adminWithInstalledModules();
	}

	private static Grant__c reread(Id grantId) {
		return [
			SELECT Stage__c, Submitted_Date__c, Decision_Date__c, Program_Id__c
			FROM Grant__c
			WHERE Id = :grantId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void stageDatesAreStampedAndATypedDateIsKept() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = GrantTestData.funder('Lakeside Foundation');
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				funder.Id,
				GrantService.STAGE_PROSPECT
			);
			Grant__c typed = GrantTestData.grant('Arts', funder.Id, GrantService.STAGE_APPLIED);
			typed.Submitted_Date__c = Date.today().addDays(-10);
			insert new List<Grant__c>{ grant, typed };
			Date today = Date.today();

			Test.startTest();
			Assert.isNull(reread(grant.Id).Submitted_Date__c, 'A prospect has no submitted date');
			grant.Stage__c = GrantService.STAGE_APPLIED;
			update grant;
			Assert.areEqual(today, reread(grant.Id).Submitted_Date__c, 'Applied stamps today');
			grant.Stage__c = GrantService.STAGE_AWARDED;
			update grant;
			Test.stopTest();

			Grant__c awarded = reread(grant.Id);
			Assert.areEqual(today, awarded.Decision_Date__c, 'Awarded stamps the decision date');
			Assert.areEqual(today, awarded.Submitted_Date__c, 'The submitted date stays');
			Assert.areEqual(
				today.addDays(-10),
				reread(typed.Id).Submitted_Date__c,
				'A typed date is kept'
			);
		}
	}

	@IsTest
	static void textThatIsNotARecordIdIsRefused() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = GrantTestData.funder('Lakeside Foundation');
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				funder.Id,
				GrantService.STAGE_PROSPECT
			);
			grant.Program_Id__c = 'tutoring';

			Test.startTest();
			Database.SaveResult saved = Database.insert(grant, false);
			Test.stopTest();

			Assert.isFalse(saved.isSuccess(), 'Not a record identifier');
			Assert.areEqual(Label.Funders_Grant_BadProgram, saved.getErrors()[0].getMessage());
		}
	}

	@IsTest
	static void theProgramIsStoredInFullAndMustBeAProgram() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Account funder = GrantTestData.funder('Lakeside Foundation');
			Schema.SObjectType programType = NamespaceUtil.packagedObjectType('Program__c');
			Grant__c wrongKind = GrantTestData.grant(
				'Arts',
				funder.Id,
				GrantService.STAGE_PROSPECT
			);
			wrongKind.Program_Id__c = funder.Id;

			Test.startTest();
			Database.SaveResult refused = Database.insert(wrongKind, false);
			Test.stopTest();

			if (programType == null) {
				// Without Programs any record identifier is kept, in full.
				Assert.isTrue(refused.isSuccess(), 'Nothing to check against without Programs');
				Assert.areEqual(String.valueOf(funder.Id), reread(wrongKind.Id).Program_Id__c);
				return;
			}
			Assert.isFalse(refused.isSuccess(), 'An organization is not a program');
			SObject program = programType.newSObject();
			program.put('Name', 'Tutoring');
			insert program;
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				funder.Id,
				GrantService.STAGE_PROSPECT
			);
			grant.Program_Id__c = String.valueOf(program.Id).left(15);
			insert grant;
			Assert.areEqual(
				String.valueOf(program.Id),
				reread(grant.Id).Program_Id__c,
				'The 15-character form is stored as 18'
			);
			Assert.areEqual('Tutoring', GrantService.programName(reread(grant.Id).Program_Id__c));
			Assert.isTrue(GrantService.programsAvailable(), 'Programs can be chosen');
			Assert.areEqual(1, GrantService.programs().size(), 'The one program is offered');
		}
	}

	@IsTest
	static void setProgramNamesAndClearsTheProgram() {
		System.runAs(TestUsers.adminWithInstalledModules()) {
			Account funder = GrantTestData.funder('Lakeside Foundation');
			Grant__c grant = GrantTestData.grant(
				'Literacy',
				funder.Id,
				GrantService.STAGE_PROSPECT
			);
			insert grant;

			Test.startTest();
			GrantService.setProgram(grant.Id, null);
			String refusal;
			try {
				GrantService.setProgram(grant.Id, funder.Id);
			} catch (GrantService.GrantException e) {
				refusal = e.getMessage();
			}
			Test.stopTest();

			Assert.isNull(reread(grant.Id).Program_Id__c, 'Cleared');
			Assert.areEqual(Label.Funders_Grant_BadProgram, refusal, 'An organization is refused');
		}
	}

	@IsTest
	static void amountsAndAwardPeriodMakeSense() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = GrantTestData.funder('Lakeside Foundation');
			Grant__c negative = GrantTestData.grant('A', funder.Id, GrantService.STAGE_PROSPECT);
			negative.Amount_Requested__c = -1;
			Grant__c backwards = GrantTestData.grant('B', funder.Id, GrantService.STAGE_AWARDED);
			backwards.Award_Start_Date__c = Date.today();
			backwards.Award_End_Date__c = Date.today().addDays(-1);

			Test.startTest();
			List<Database.SaveResult> saved = Database.insert(
				new List<Grant__c>{ negative, backwards },
				false
			);
			Test.stopTest();

			Assert.isFalse(saved[0].isSuccess(), 'A negative amount is refused');
			Assert.isFalse(saved[1].isSuccess(), 'An award period ending before it starts');
		}
	}

	@IsTest
	static void aFunderWithGrantsIsKept() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account funder = GrantTestData.funder('Lakeside Foundation');
			insert GrantTestData.grant('Literacy', funder.Id, GrantService.STAGE_PROSPECT);

			Test.startTest();
			Database.DeleteResult deleted = Database.delete(funder, false);
			Test.stopTest();

			Assert.isFalse(deleted.isSuccess(), 'The platform refuses (Restrict)');
			Assert.isTrue(GrantService.OPEN_STAGES.contains(GrantService.STAGE_APPLIED));
			Assert.isFalse(GrantService.OPEN_STAGES.contains(GrantService.STAGE_DECLINED));
		}
	}
}
