/**
 * Grant payments (F-05, R-GP1 to R-GP3): the received date fills itself in and a typed date is
 * kept; the received automation has its switch row; the Award Schedule card builds a schedule
 * once, refuses rows that do not fit the award, and marks a payment received; a reader can do
 * neither; payments go with their grant.
 */
@IsTest(
	testFor='ApexClass:GrantPaymentService, ApexClass:GrantPaymentReceivedHandler, ApexClass:GrantScheduleController'
)
private class GrantPaymentTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.standardUserWith(
			'Gpayreader',
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
		);
	}

	private static final Date START = Date.newInstance(2027, 1, 1);
	private static final Date FINISH = Date.newInstance(2028, 12, 31);

	/** An awarded grant of 25,000 for 2027 and 2028. */
	private static Grant__c award() {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		Grant__c grant = GrantTestData.grant('Literacy', funder.Id, GrantService.STAGE_AWARDED);
		grant.Amount_Awarded__c = 25000;
		grant.Award_Start_Date__c = START;
		grant.Award_End_Date__c = FINISH;
		insert grant;
		return grant;
	}

	private static String rows(List<Object> pairs) {
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (Integer i = 0; i < pairs.size(); i += 2) {
			out.add(new Map<String, Object>{ 'dueDate' => pairs[i], 'amount' => pairs[i + 1] });
		}
		return JSON.serialize(out);
	}

	private static String refusalOf(Id grantId, String paymentsJson) {
		try {
			GrantScheduleController.saveSchedule(grantId, 'Once', paymentsJson);
		} catch (AuraHandledException e) {
			return e.getMessage();
		}
		return null;
	}

	@IsTest
	static void theReceivedDateIsFilledInAndATypedOneKept() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Grant__c grant = award();
			Grant_Payment__c expected = new Grant_Payment__c(
				Grant__c = grant.Id,
				Due_Date__c = START,
				Amount__c = 100,
				Status__c = GrantPaymentService.STATUS_EXPECTED
			);
			Grant_Payment__c typed = new Grant_Payment__c(
				Grant__c = grant.Id,
				Due_Date__c = START,
				Amount__c = 100,
				Status__c = GrantPaymentService.STATUS_RECEIVED,
				Received_Date__c = START.addDays(2)
			);

			Test.startTest();
			insert new List<Grant_Payment__c>{ expected, typed };
			Date beforeReceiving = [
				SELECT Received_Date__c
				FROM Grant_Payment__c
				WHERE Id = :expected.Id
			]
			.Received_Date__c;
			update new Grant_Payment__c(
				Id = expected.Id,
				Status__c = GrantPaymentService.STATUS_RECEIVED
			);
			Test.stopTest();

			Map<Id, Grant_Payment__c> saved = new Map<Id, Grant_Payment__c>(
				[SELECT Status__c, Received_Date__c FROM Grant_Payment__c]
			);
			Assert.isNull(beforeReceiving, 'Nothing while expected');
			Assert.areEqual(today, saved.get(expected.Id).Received_Date__c, 'Stamped');
			Assert.areEqual(START.addDays(2), saved.get(typed.Id).Received_Date__c, 'Kept');
		}
	}

	@IsTest
	static void theReceivedAutomationHasItsSwitchRow() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			List<Automation_Registry__mdt> rows = [
				SELECT Handler_Class__c, Always_Runs__c, Module__c
				FROM Automation_Registry__mdt
				WHERE DeveloperName = 'Grant_Payment_Received'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, rows.size(), 'The row ships');
			Assert.areEqual('GrantPaymentReceivedHandler', rows[0].Handler_Class__c, 'Named');
			Assert.isFalse(rows[0].Always_Runs__c, 'Switchable');
			Assert.areEqual('Funders', rows[0].Module__c, 'The module owns it');
		}
	}

	@IsTest
	static void aScheduleIsBuiltOnceAndAPaymentMarkedReceived() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Grant__c grant = award();

			Test.startTest();
			GrantScheduleController.Schedule before = GrantScheduleController.getSchedule(grant.Id);
			GrantScheduleController.saveSchedule(
				grant.Id,
				'Annual',
				rows(new List<Object>{ '2027-01-01', 12500, '2028-01-01', 12500 })
			);
			GrantScheduleController.Schedule built = GrantScheduleController.getSchedule(grant.Id);
			String again = refusalOf(grant.Id, rows(new List<Object>{ '2027-01-01', 25000 }));
			GrantScheduleController.markReceived(built.payments[0].id);
			Test.stopTest();

			GrantScheduleController.Schedule after = GrantScheduleController.getSchedule(grant.Id);
			Assert.isTrue(before.canBuild, 'An award with no payments can be built');
			Assert.isTrue(before.canMarkReceived, 'The admin can mark payments');
			Assert.areEqual(25000, before.amountAwarded, 'With its amount');
			Assert.areEqual(START, before.startDate, 'And period');
			Assert.areEqual(0, before.payments.size(), 'Nothing yet');
			Assert.isFalse(built.canBuild, 'Built once');
			Assert.areEqual(2, built.payments.size(), 'Two payments');
			Assert.areEqual(START, built.payments[0].dueDate, 'In date order');
			Assert.areEqual(25000, built.amountScheduled, 'All of it scheduled');
			Assert.areEqual(Label.Funders_Schedule_CannotBuild, again, 'Not twice');
			Assert.areEqual('Annual', built.frequency, 'The frequency is kept on the grant');
			Assert.areEqual(5, before.frequencies.size(), 'Five frequencies to choose from');
			Assert.isNotNull(before.fieldLabels.get('dueDate'), 'Headings from field labels');
			Assert.areEqual(
				GrantPaymentService.STATUS_RECEIVED,
				after.payments[0].status,
				'Marked'
			);
			Assert.areEqual(Date.today(), after.payments[0].receivedDate, 'Dated today');
			Assert.areEqual(12500, after.amountReceived, 'Counted received');
		}
	}

	@IsTest
	static void rowsThatDoNotFitTheAwardAreRefused() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Grant__c grant = award();
			Grant__c applied = GrantTestData.grant(
				'Applied',
				grant.Funder__c,
				GrantService.STAGE_APPLIED
			);
			insert applied;

			Test.startTest();
			String shortTotal = refusalOf(grant.Id, rows(new List<Object>{ '2027-01-01', 100 }));
			String outside = refusalOf(grant.Id, rows(new List<Object>{ '2029-01-01', 25000 }));
			String zero = refusalOf(
				grant.Id,
				rows(new List<Object>{ '2027-01-01', 25000, '2027-06-01', 0 })
			);
			String empty = refusalOf(grant.Id, '[]');
			String unreadable = refusalOf(grant.Id, 'not json');
			String notAwarded = refusalOf(
				applied.Id,
				rows(new List<Object>{ '2027-01-01', 25000 })
			);
			Test.stopTest();

			Assert.areEqual(Label.Funders_Schedule_ErrorRows, shortTotal, 'Must add up');
			Assert.areEqual(Label.Funders_Schedule_ErrorRows, outside, 'Within the period');
			Assert.areEqual(Label.Funders_Schedule_ErrorRows, zero, 'Above zero');
			Assert.areEqual(Label.Funders_Schedule_ErrorRows, empty, 'Something to save');
			Assert.areEqual(Label.Funders_Schedule_ErrorRows, unreadable, 'Readable');
			Assert.areEqual(Label.Funders_Schedule_CannotBuild, notAwarded, 'Awarded only');
			Assert.isFalse(
				GrantScheduleController.getSchedule(applied.Id).canBuild,
				'Not offered before the award'
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Grant_Payment__c], 'Nothing saved');
		}
	}

	@IsTest
	static void aReaderCannotBuildOrMarkAndPaymentsGoWithTheirGrant() {
		Grant__c grant;
		Grant_Payment__c payment;
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			grant = award();
			payment = new Grant_Payment__c(
				Grant__c = grant.Id,
				Due_Date__c = START,
				Amount__c = 5,
				Status__c = GrantPaymentService.STATUS_EXPECTED
			);
			insert payment;
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Gpayreader' WITH SYSTEM_MODE LIMIT 1];
		String markRefusal;
		String saveRefusal;
		GrantScheduleController.Schedule seen;
		System.runAs(reader) {
			Test.startTest();
			try {
				GrantScheduleController.markReceived(payment.Id);
			} catch (AuraHandledException e) {
				markRefusal = e.getMessage();
			}
			saveRefusal = refusalOf(grant.Id, rows(new List<Object>{ '2027-01-01', 25000 }));
			seen = GrantScheduleController.getSchedule(grant.Id);
			Test.stopTest();
		}
		Assert.areEqual(Label.Funders_Pipeline_ErrorNoPermission, markRefusal, 'Cannot mark');
		Assert.areEqual(Label.Funders_Pipeline_ErrorNoPermission, saveRefusal, 'Cannot build');
		Assert.areEqual(1, seen.payments.size(), 'Reads the schedule');
		Assert.isFalse(seen.canMarkReceived, 'Mark Received not offered');
		Assert.isFalse(seen.canBuild, 'Build not offered');
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			delete grant;
		}
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Grant_Payment__c WITH SYSTEM_MODE],
			'Deleted with the grant'
		);
	}
}
