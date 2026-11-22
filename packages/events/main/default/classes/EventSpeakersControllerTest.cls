/**
 * Dana lines up the community conference's speakers: Ana Garcia keynotes and moderates a panel,
 * a second add of Ana is refused, and removing a speaker takes their sessions with them
 * (EV-05, R-ESP1 to R-ESP3, R-SSP1 to R-SSP3).
 */
@IsTest(
	testFor='ApexClass:EventSpeakersController, ApexClass:EventKeyHandler, ApexTrigger:EventSpeakerTrigger, ApexTrigger:SessionSpeakerTrigger'
)
private class EventSpeakersControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private static Event__c conference(String name) {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = name,
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user record;
		return record;
	}

	private static Event_Session__c session(Event__c event, String name) {
		Event_Session__c record = new Event_Session__c(Event__c = event.Id, Name = name);
		insert as user record;
		return record;
	}

	private static Contact person() {
		Contact record = TestDataFactory.person(new Contact(FirstName = 'Ana', LastName = 'Garcia'));
		insert as user record;
		return record;
	}

	/** Adds a speaker as the tab does, through Lightning Data Service (ADR-0093). */
	private static Id addSpeaker(Id eventId, Id contactId) {
		Event_Speaker__c record = new Event_Speaker__c(Event__c = eventId, Contact__c = contactId);
		insert as user record;
		return record.Id;
	}

	/** Puts a speaker in a session as the tab does, through Lightning Data Service. */
	private static void assign(Id sessionId, Id speakerId, String role) {
		insert as user new Session_Speaker__c(
			Event_Session__c = sessionId,
			Event_Speaker__c = speakerId,
			Role__c = role
		);
	}

	@IsTest
	static void addsAPersonAsASpeakerNamedAfterThem() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Contact ana = person();

			Test.startTest();
			addSpeaker(event.Id, ana.Id);
			EventSpeakersController.Speakers result = EventSpeakersController.getSpeakers(event.Id);
			Test.stopTest();

			Assert.areEqual(1, result.speakers.size(), 'One speaker');
			Assert.areEqual('Ana Garcia', result.speakers[0].name, 'Named after the person');
			Assert.areEqual(ana.Id, result.speakers[0].contactId, 'Linked to the person');
			Assert.areEqual('Invited', result.speakers[0].status, 'Invited by default');
			Assert.isTrue(result.canAdd && result.canAssign, 'Staff may add and assign');
			Assert.isFalse(result.roles.isEmpty(), 'Roles to choose from');
			Assert.areEqual(0, result.speakers[0].checklistDone, 'Nothing ticked yet');
		}
	}

	@IsTest
	static void countsTheSpeakerChecklist() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Id speakerId = addSpeaker(event.Id, person().Id);
			update as user new Event_Speaker__c(
				Id = speakerId,
				Agreement_Signed__c = true,
				Dry_Run_Done__c = true,
				Headshot_URL__c = 'https://example.org/ana.jpg'
			);

			Test.startTest();
			EventSpeakersController.Speakers result = EventSpeakersController.getSpeakers(event.Id);
			Test.stopTest();

			Assert.areEqual(2, result.speakers[0].checklistDone, 'Two of three ticked (EV-25)');
		}
	}

	@IsTest
	static void refusesTheSamePersonTwiceAtOneEvent() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Contact ana = person();
			addSpeaker(event.Id, ana.Id);

			Test.startTest();
			Boolean refused = false;
			try {
				addSpeaker(event.Id, ana.Id);
			} catch (DmlException e) {
				refused = true;
			}
			Id other = addSpeaker(conference('Second Event').Id, ana.Id);
			Test.stopTest();

			Assert.isTrue(refused, 'A second add of the same person is refused');
			Assert.isNotNull(other, 'The same person may speak at another event');
		}
	}

	@IsTest
	static void assignsASpeakerToASessionOnce() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Event_Session__c keynote = session(event, 'Keynote');
			Id speakerId = addSpeaker(event.Id, person().Id);

			Test.startTest();
			assign(keynote.Id, speakerId, 'Speaker');
			Boolean refused = false;
			try {
				assign(keynote.Id, speakerId, 'Moderator');
			} catch (DmlException e) {
				refused = true;
			}
			EventSpeakersController.Speakers result = EventSpeakersController.getSpeakers(event.Id);
			Test.stopTest();

			Assert.isTrue(refused, 'The same speaker twice in a session is refused');
			Assert.areEqual(1, result.speakers[0].assignments.size(), 'One assignment');
			Assert.areEqual('Keynote', result.speakers[0].assignments[0].sessionName, 'In the keynote');
			Assert.areEqual('Speaker', result.speakers[0].assignments[0].role, 'With the role');
			Assert.areEqual(1, result.sessions.size(), 'The event sessions to choose from');
		}
	}

	@IsTest
	static void refusesASpeakerFromAnotherEvent() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Event_Session__c keynote = session(event, 'Keynote');
			Id otherSpeaker = addSpeaker(conference('Second Event').Id, person().Id);

			Test.startTest();
			Boolean refused = false;
			try {
				assign(keynote.Id, otherSpeaker, 'Speaker');
			} catch (DmlException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.isTrue(refused, 'A speaker from another event is refused');
			Assert.areEqual(0, [SELECT COUNT() FROM Session_Speaker__c], 'Nothing saved');
		}
	}

	@IsTest
	static void removingASpeakerRemovesTheirAssignments() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Event_Session__c keynote = session(event, 'Keynote');
			Id speakerId = addSpeaker(event.Id, person().Id);
			assign(keynote.Id, speakerId, 'Speaker');

			Test.startTest();
			EventSpeakersController.removeSpeaker(speakerId);
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Event_Speaker__c], 'Speaker removed');
			Assert.areEqual(0, [SELECT COUNT() FROM Session_Speaker__c], 'Assignments removed');
			Assert.areEqual(1, [SELECT COUNT() FROM Event_Session__c], 'The session stays');
		}
	}
}
