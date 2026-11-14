/**
 * Ana signs in to the speaker portal, starts a proposal for an open event and withdraws it
 * (PB-07). The actions act only for the verified person, start one proposal per event, and
 * leave a decided proposal alone.
 */
@IsTest(testFor='ApexClass:EventsPortalExtension')
private class EventsPortalExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private static Event__c event(String status, Integer startsInDays) {
		Datetime start = Datetime.now().addDays(startsInDays);
		Event__c record = new Event__c(
			Name = 'Community Dreamin',
			Status__c = status,
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user record;
		return record;
	}

	private static Contact person(String lastName) {
		Contact record = TestDataFactory.person(
			new Contact(FirstName = 'Ana', LastName = lastName)
		);
		insert as user record;
		return record;
	}

	private static List<Speaker_Application__c> applicationsOf(Id eventId) {
		return [
			SELECT Id, Name, Contact__c, Status__c
			FROM Speaker_Application__c
			WHERE Event__c = :eventId
		];
	}

	@IsTest
	static void coreFindsBothActionsByName() {
		System.runAs(staff()) {
			Assert.isTrue(
				PortalActionExtensions.forAction(
					'Events.ApplyToSpeak'
				) instanceof EventsPortalExtension,
				'Apply is offered'
			);
			Assert.isTrue(
				PortalActionExtensions.forAction(
					'Events.WithdrawProposal'
				) instanceof EventsPortalExtension,
				'Withdraw is offered'
			);
		}
	}

	@IsTest
	static void startsOneProposalPerEventAndAllowsANewOneAfterWithdrawing() {
		System.runAs(staff()) {
			Contact ana = person('Speaker');
			Event__c open = event('Open', 30);
			EventsPortalExtension extension = new EventsPortalExtension();

			Test.startTest();
			String started = extension.run(EventsPortalExtension.APPLY, ana.Id, open.Id);
			String again = extension.run(EventsPortalExtension.APPLY, ana.Id, open.Id);
			List<Speaker_Application__c> first = applicationsOf(open.Id);
			String withdrawn = extension.run(EventsPortalExtension.WITHDRAW, ana.Id, first[0].Id);
			String twice = extension.run(EventsPortalExtension.WITHDRAW, ana.Id, first[0].Id);
			extension.run(EventsPortalExtension.APPLY, ana.Id, open.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_Applied'), started);
			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_AlreadyApplied'), again);
			Assert.areEqual(1, first.size(), 'One proposal, never two');
			Assert.areEqual('Submitted', first[0].Status__c);
			Assert.areEqual(ana.Id, first[0].Contact__c, 'For the verified person');
			Assert.isTrue(first[0].Name.contains('Community Dreamin'), 'Titled for the event');
			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_Withdrawn'), withdrawn);
			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_CannotWithdraw'), twice);
			Assert.areEqual(2, applicationsOf(open.Id).size(), 'A new proposal after withdrawing');
		}
	}

	@IsTest
	static void refusesAnEventThatIsNotOpenOrIsOver() {
		System.runAs(staff()) {
			Contact ana = person('Speaker');
			Event__c draft = event('Draft', 30);
			Event__c over = event('Open', -10);
			EventsPortalExtension extension = new EventsPortalExtension();

			Test.startTest();
			String draftMessage = extension.run(EventsPortalExtension.APPLY, ana.Id, draft.Id);
			String overMessage = extension.run(EventsPortalExtension.APPLY, ana.Id, over.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_EventClosed'), draftMessage);
			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_EventClosed'), overMessage);
			Assert.isTrue(applicationsOf(draft.Id).isEmpty(), 'Nothing for a draft event');
			Assert.isTrue(applicationsOf(over.Id).isEmpty(), 'Nothing for a past event');
		}
	}

	@IsTest
	static void aPersonWithdrawsOnlyTheirOwnUndecidedProposal() {
		System.runAs(staff()) {
			Contact ana = person('Speaker');
			Contact ben = person('Other');
			Event__c open = event('Open', 30);
			Speaker_Application__c decided = new Speaker_Application__c(
				Event__c = open.Id,
				Contact__c = ana.Id,
				Name = 'Accepted talk',
				Status__c = 'Accepted'
			);
			insert as user decided;
			EventsPortalExtension extension = new EventsPortalExtension();

			Test.startTest();
			String message = extension.run(EventsPortalExtension.WITHDRAW, ana.Id, decided.Id);
			try {
				extension.run(EventsPortalExtension.WITHDRAW, ben.Id, decided.Id);
				Assert.fail('Another person cannot withdraw it');
			} catch (System.QueryException refused) {
				Assert.isNotNull(refused.getMessage(), 'Refused');
			}
			try {
				extension.run('Events.Nope', ana.Id, decided.Id);
				Assert.fail('An unknown action is refused');
			} catch (System.IllegalArgumentException refused) {
				Assert.isNotNull(refused.getMessage(), 'Refused');
			}
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Events', 'Events_Portal_CannotWithdraw'), message);
			Assert.areEqual('Accepted', applicationsOf(open.Id)[0].Status__c, 'Left alone');
		}
	}
}
