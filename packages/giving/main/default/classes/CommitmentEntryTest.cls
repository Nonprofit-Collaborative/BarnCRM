/**
 * Tests for the New Commitment screen's surface and the shared pledge builder it and the Ask
 * Pipeline use (people-giving-11).
 */
@IsTest(testFor='ApexClass:CommitmentEntryController, ApexClass:CommitmentEntry')
private class CommitmentEntryTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Staff');
	}

	private static User staff() {
		return TestUsers.adminWith('Giving_Staff');
	}

	private static Contact donor() {
		Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
		insert person;
		return person;
	}

	private static CommitmentEntryController.EntryInput pledgeInput(Id donorId) {
		CommitmentEntryController.EntryInput input = new CommitmentEntryController.EntryInput();
		input.kind = 'Pledge';
		input.donorContactId = donorId;
		input.total = 1000;
		input.payments = 3;
		input.frequency = 'Monthly';
		input.startDate = Date.newInstance(2027, 1, 15);
		return input;
	}

	@IsTest
	static void savesAPledgeEnteredAsATotal() {
		System.runAs(staff()) {
			Contact person = donor();

			Test.startTest();
			CommitmentEntryController.SaveResult result = CommitmentEntryController.save(
				pledgeInput(person.Id)
			);
			Test.stopTest();

			Assert.isTrue(result.success, 'The pledge saves: ' + result.error);
			Commitment__c saved = [
				SELECT Type__c, Expected_Total__c, Amount__c, Installments_Planned__c
				FROM Commitment__c
				WHERE Id = :result.commitmentId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Pledge', saved.Type__c, 'It is a pledge.');
			Assert.areEqual(1000, saved.Expected_Total__c, 'The total is what was entered.');
			Assert.areEqual(333.33, saved.Amount__c, 'Each payment is the total divided evenly.');
			Assert.areEqual(3, saved.Installments_Planned__c, 'Three payments are planned.');
			List<Installment__c> schedule = [
				SELECT Expected_Amount__c
				FROM Installment__c
				WHERE Commitment__c = :result.commitmentId
				WITH SYSTEM_MODE
				ORDER BY Sequence__c
			];
			Assert.areEqual(3, schedule.size(), 'The triggers made the three payments.');
			Assert.areEqual(
				333.34,
				schedule[2].Expected_Amount__c,
				'The last payment takes up the rounding.'
			);
		}
	}

	@IsTest
	static void countsPaymentsUpToALastPaymentDate() {
		System.runAs(staff()) {
			CommitmentEntryController.EntryInput input = pledgeInput(donor().Id);
			input.payments = null;
			input.lastPaymentDate = Date.newInstance(2027, 12, 15);

			Test.startTest();
			CommitmentController.SchedulePreview preview = CommitmentEntryController.preview(input);
			Test.stopTest();

			Assert.areEqual(12, preview.count, 'January to December, monthly, is twelve payments.');
			Assert.areEqual(1000, preview.expectedTotal, 'The preview totals the pledge.');
			Assert.areEqual(0, [SELECT COUNT() FROM Commitment__c], 'A preview saves nothing.');
		}
	}

	@IsTest
	static void refusesALastPaymentDateBeforeTheFirst() {
		System.runAs(staff()) {
			CommitmentEntryController.EntryInput input = pledgeInput(donor().Id);
			input.payments = null;
			input.lastPaymentDate = Date.newInstance(2026, 12, 15);

			CommitmentEntryController.SaveResult result = CommitmentEntryController.save(input);

			Assert.isFalse(result.success, 'Nothing is saved.');
			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_CommitmentNew_ErrorLastDate'),
				result.error,
				'The person is told the dates are the wrong way round.'
			);
		}
	}

	@IsTest
	static void savesARecurringGiftWithNoTotal() {
		System.runAs(staff()) {
			CommitmentEntryController.EntryInput input = new CommitmentEntryController.EntryInput();
			input.kind = 'Recurring';
			input.donorContactId = donor().Id;
			input.amount = 25;
			input.frequency = 'Monthly';
			input.startDate = Date.today();

			CommitmentEntryController.SaveResult result = CommitmentEntryController.save(input);

			Assert.isTrue(result.success, 'The recurring gift saves: ' + result.error);
			Commitment__c saved = [
				SELECT Type__c, Expected_Total__c, Amount__c
				FROM Commitment__c
				WHERE Id = :result.commitmentId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Recurring', saved.Type__c, 'It is a recurring gift.');
			Assert.isNull(saved.Expected_Total__c, 'A recurring gift has no total.');
			Assert.areEqual(25, saved.Amount__c, 'The amount each time is what was entered.');
		}
	}

	@IsTest
	static void asksForOneDonor() {
		System.runAs(staff()) {
			CommitmentEntryController.EntryInput none = pledgeInput(null);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_CommitmentNew_ErrorNoDonor'),
				CommitmentEntryController.save(none).error,
				'A commitment needs a donor.'
			);

			Account organization = new Account(Name = 'Harbor Foundation');
			insert organization;
			CommitmentEntryController.EntryInput both = pledgeInput(donor().Id);
			both.donorAccountId = organization.Id;
			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_CommitmentNew_ErrorTwoDonors'),
				CommitmentEntryController.save(both).error,
				'A commitment has one donor, not two.'
			);
		}
	}

	@IsTest
	static void previewsNothingUntilTheEntriesAreComplete() {
		System.runAs(staff()) {
			CommitmentEntryController.EntryInput input = pledgeInput(donor().Id);
			input.total = null;

			Assert.isNull(
				CommitmentEntryController.preview(input),
				'An incomplete pledge has no preview yet.'
			);
			Assert.areEqual(
				BarnHelp.text('Giving', 'Giving_Ask_ErrorAmount'),
				CommitmentEntryController.save(input).error,
				'Saving it asks for the total, as Record a Pledge does.'
			);
		}
	}

	@IsTest
	static void startsWithTheDonorOfThePageItCameFrom() {
		System.runAs(staff()) {
			Contact person = donor();

			CommitmentEntryController.Defaults defaults = CommitmentEntryController.getDefaults(
				person.Id
			);

			Assert.isTrue(defaults.canCreate, 'Giving Staff may create commitments.');
			Assert.areEqual(String.valueOf(person.Id), defaults.donorId, 'The donor is prefilled.');
			Assert.areEqual('person', defaults.donorKind, 'A contact is a person.');
			Assert.isFalse(defaults.frequencies.isEmpty(), 'The frequencies are offered.');
			Assert.areEqual('Monthly', defaults.defaultFrequency, 'Monthly is the default.');
			Assert.isNull(
				CommitmentEntryController.getDefaults('not an id').donorId,
				'Anything else prefills nothing.'
			);
		}
	}

	@IsTest
	static void countsPaymentsOnTheScheduleDates() {
		System.runAs(staff()) {
			assertPaymentCounts();
		}
	}

	private static void assertPaymentCounts() {
		Date first = Date.newInstance(2027, 1, 31);
		Assert.areEqual(
			4,
			CommitmentEntry.paymentsThrough('Quarterly', first, Date.newInstance(2027, 12, 31)),
			'Quarterly from January to December is four payments.'
		);
		Assert.areEqual(
			1,
			CommitmentEntry.paymentsThrough('Weekly', first, first),
			'The same first and last date is one payment.'
		);
		Assert.isNull(
			CommitmentEntry.paymentsThrough('Weekly', first, first.addDays(-1)),
			'A last date before the first counts nothing.'
		);
		Assert.isNotNull(
			CommitmentEntry.recurringProblem(null, 'Monthly', first),
			'A recurring gift needs an amount.'
		);
		Assert.isNotNull(
			CommitmentEntry.recurringProblem(10, null, first),
			'A recurring gift needs a frequency.'
		);
	}
}
