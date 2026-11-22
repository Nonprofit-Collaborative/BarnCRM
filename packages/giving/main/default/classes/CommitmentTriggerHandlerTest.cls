/**
 * Tests for the record-level rules on Commitment__c and Installment__c: the household is
 * derived from the donor, a schedule change rebuilds the unpaid payments, and a commitment
 * or a payment that has been paid cannot be deleted.
 */
@IsTest(testFor='ApexClass:CommitmentTriggerHandler')
private class CommitmentTriggerHandlerTest {
	/**
	 * A gift saves only when there is a default fund to allocate it to (R-GA2).
	 */
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
		}
	}

	private static Contact donor() {
		Contact person = TestDataFactory.person(new Contact(FirstName = 'Sarah', LastName = 'Nguyen'));
		insert person;
		return person;
	}

	private static Commitment__c pledgeFor(Id donorId) {
		return new Commitment__c(
			Type__c = 'Pledge',
			Status__c = 'Active',
			Donor_Contact__c = donorId,
			Amount__c = 100,
			Frequency__c = 'Monthly',
			Start_Date__c = Date.today(),
			Expected_Total__c = 300,
			Installments_Planned__c = 3
		);
	}

	@IsTest
	static void derivesTheHouseholdFromTheDonor() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c pledge = pledgeFor(person.Id);

			Test.startTest();
			new CommitmentTriggerHandler().deriveHouseholds(new List<Commitment__c>{ pledge }, null);
			Test.stopTest();

			Contact saved = [SELECT AccountId FROM Contact WHERE Id = :person.Id];
			if (saved.AccountId != null) {
				Assert.areEqual(
					saved.AccountId,
					pledge.Household__c,
					'A commitment is credited to its donor household, exactly as a gift is.'
				);
			} else {
				Assert.areEqual(
					null,
					pledge.Household__c,
					'A donor with no household leaves the household empty rather than guessing.'
				);
			}
		}
	}

	@IsTest
	static void generatesTheScheduleAfterInsert() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c pledge = pledgeFor(person.Id);
			insert pledge;

			Test.startTest();
			new CommitmentTriggerHandler().onAfterInsert(new List<Commitment__c>{ pledge });
			Test.stopTest();

			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Installment__c WHERE Commitment__c = :pledge.Id],
				'Saving a commitment generates its payments without anyone asking.'
			);
		}
	}

	@IsTest
	static void rebuildsTheScheduleWhenTheFrequencyChanges() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c pledge = pledgeFor(person.Id);
			insert pledge;
			CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });

			Map<Id, Commitment__c> oldMap = new Map<Id, Commitment__c>{ pledge.Id => pledge.clone(true, true) };
			pledge.Frequency__c = 'Weekly';
			update pledge;

			Test.startTest();
			new CommitmentTriggerHandler().onAfterUpdate(new List<Commitment__c>{ pledge }, oldMap);
			Test.stopTest();

			List<Installment__c> schedule = [
				SELECT Due_Date__c
				FROM Installment__c
				WHERE Commitment__c = :pledge.Id
				ORDER BY Sequence__c
			];
			Assert.areEqual(
				Date.today().addDays(7),
				schedule[1].Due_Date__c,
				'A weekly schedule puts the second payment a week after the first.'
			);
		}
	}

	@IsTest
	static void blocksDeletingACommitmentThatHasBeenPaid() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c pledge = pledgeFor(person.Id);
			insert pledge;
			CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
			Installment__c first = [
				SELECT Id, Commitment__c, Paid_Amount__c
				FROM Installment__c
				WHERE Commitment__c = :pledge.Id
				ORDER BY Sequence__c
				LIMIT 1
			];
			insert new Gift__c(
				Donor_Contact__c = person.Id,
				Gift_Date__c = Date.today(),
				Amount__c = 100,
				Type__c = 'Check',
				Status__c = 'Received',
				Commitment__c = pledge.Id,
				Installment__c = first.Id
			);

			Boolean blocked = false;
			Test.startTest();
			try {
				delete pledge;
			} catch (DmlException expected) {
				blocked = true;
			}
			Test.stopTest();

			Assert.isTrue(blocked, 'A commitment with a gift against it is history, so it is not deleted.');
		}
	}

	@IsTest
	static void blocksDeletingAnInstallmentThatHasBeenPaid() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c pledge = pledgeFor(person.Id);
			insert pledge;
			CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
			Installment__c first = [
				SELECT Id, Paid_Amount__c
				FROM Installment__c
				WHERE Commitment__c = :pledge.Id
				ORDER BY Sequence__c
				LIMIT 1
			];
			insert new Gift__c(
				Donor_Contact__c = person.Id,
				Gift_Date__c = Date.today(),
				Amount__c = 100,
				Type__c = 'Check',
				Status__c = 'Received',
				Commitment__c = pledge.Id,
				Installment__c = first.Id
			);

			Boolean blocked = false;
			Test.startTest();
			try {
				delete first;
			} catch (DmlException expected) {
				blocked = true;
			}
			Test.stopTest();

			Assert.isTrue(blocked, 'A payment with a gift against it is marked Skipped, never deleted.');
		}
	}

	@IsTest
	static void deletesACommitmentNothingHasBeenPaidAgainst() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c pledge = pledgeFor(person.Id);
			insert pledge;
			CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });

			Test.startTest();
			delete pledge;
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Commitment__c WHERE Id = :pledge.Id],
				'A commitment nobody has paid can still be removed.'
			);
		}
	}

	/**
	 * Two hundred pledges saved at once with an amount and installments but no total each get
	 * the amount times the installments, in the save and again when the total is cleared. A
	 * typed total and a recurring gift are left as they are (R-CM5).
	 */
	@IsTest
	static void fillsTheExpectedTotalOfPledgesSavedWithoutOne() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			List<Commitment__c> pledges = new List<Commitment__c>();
			for (Integer i = 0; i < 200; i++) {
				Commitment__c pledge = pledgeFor(person.Id);
				pledge.Expected_Total__c = null;
				pledges.add(pledge);
			}
			Commitment__c typed = pledgeFor(person.Id);
			typed.Expected_Total__c = 250;
			Commitment__c recurring = pledgeFor(person.Id);
			recurring.Type__c = 'Recurring';
			recurring.Expected_Total__c = null;
			recurring.Installments_Planned__c = null;

			Test.startTest();
			Database.insert(pledges, AccessLevel.USER_MODE);
			insert new List<Commitment__c>{ typed, recurring };
			for (Commitment__c pledge : pledges) {
				pledge.Expected_Total__c = null;
			}
			Database.update(pledges, AccessLevel.USER_MODE);
			Test.stopTest();

			Set<Id> ids = new Map<Id, Commitment__c>(pledges).keySet();
			for (Commitment__c saved : [
				SELECT Expected_Total__c, Balance__c
				FROM Commitment__c
				WHERE Id IN :ids
			]) {
				Assert.areEqual(300, saved.Expected_Total__c, 'Three payments of 100.');
				Assert.areEqual(300, saved.Balance__c, 'Nothing paid yet, so all of it is owed.');
			}
			Assert.areEqual(
				250,
				[SELECT Expected_Total__c FROM Commitment__c WHERE Id = :typed.Id].Expected_Total__c,
				'A total someone typed is theirs.'
			);
			Assert.isNull(
				[SELECT Expected_Total__c FROM Commitment__c WHERE Id = :recurring.Id].Expected_Total__c,
				'A recurring gift has no total.'
			);
		}
	}

	/**
	 * Three payments of 100 toward a total of 200 would leave a last payment of 0, and toward 150
	 * one of -50: both are refused at save with the reason. A total of 200.01 leaves 0.01, the
	 * smallest valid last payment, and saves. Raising a saved pledge's amount to 150 is refused
	 * the same way (D-219, OD-14).
	 */
	@IsTest
	static void refusesAPledgeWhoseLastPaymentWouldBeZeroOrLess() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = donor();
			Commitment__c zero = pledgeFor(person.Id);
			zero.Expected_Total__c = 200;
			Commitment__c negative = pledgeFor(person.Id);
			negative.Expected_Total__c = 150;
			Commitment__c boundary = pledgeFor(person.Id);
			boundary.Expected_Total__c = 200.01;

			Test.startTest();
			List<Database.SaveResult> results = Database.insert(
				new List<Commitment__c>{ zero, negative, boundary },
				false,
				AccessLevel.USER_MODE
			);
			Commitment__c saved = pledgeFor(person.Id);
			insert saved;
			saved.Amount__c = 150;
			Database.SaveResult raised = Database.update(saved, false, AccessLevel.USER_MODE);
			Test.stopTest();

			Decimal zeroLast = 0.00;
			Decimal negativeLast = -50.00;
			Assert.isFalse(results[0].isSuccess(), 'A zero last payment is refused.');
			Assert.areEqual(
				BarnHelp.text(
					'Giving',
					'Giving_Commitment_LastPaymentNotPositive',
					new List<Object>{ zeroLast.format() }
				),
				results[0].getErrors()[0].getMessage(),
				'The error names the last payment and how to fix it.'
			);
			Assert.isFalse(results[1].isSuccess(), 'A negative last payment is refused.');
			Assert.areEqual(
				BarnHelp.text(
					'Giving',
					'Giving_Commitment_LastPaymentNotPositive',
					new List<Object>{ negativeLast.format() }
				),
				results[1].getErrors()[0].getMessage(),
				'The negative amount is named.'
			);
			Assert.isTrue(results[2].isSuccess(), 'A last payment of 0.01 saves.');
			List<Installment__c> plan = CommitmentService.buildSchedule(boundary);
			Assert.areEqual(0.01, plan[2].Expected_Amount__c, 'The last payment absorbs the remainder.');
			Assert.isFalse(raised.isSuccess(), 'Raising the amount past the total is refused on update too.');
		}
	}
}
