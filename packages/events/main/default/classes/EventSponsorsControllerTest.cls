/**
 * Dana lines up the community conference's sponsors: a Gold level with a checklist, a sponsor
 * added at that level starts with the checklist and the level's amount, a second add of the same
 * organization is refused, deliverables move to Done, and a linked record that cannot be labelled
 * shows nothing (EV-09, R-SP1 to R-SP4).
 */
@IsTest(testFor='ApexClass:EventSponsorsController, ApexClass:SponsorDeliverableTemplate')
private class EventSponsorsControllerTest {
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

	private static Sponsorship_Level__c gold(Event__c event) {
		Sponsorship_Level__c level = new Sponsorship_Level__c(
			Event__c = event.Id,
			Name = 'Gold',
			Amount__c = 5000,
			Benefits__c = 'Booth and four passes',
			Deliverables__c = 'Logo for the program\nBooth\nPasses\nThank you post'
		);
		insert as user level;
		return level;
	}

	private static Account organization(String name) {
		Account record = TestDataFactory.organization(new Account(Name = name));
		insert as user record;
		return record;
	}

	@IsTest
	static void addsASponsorWithTheLevelsAmountAndChecklist() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Sponsorship_Level__c level = gold(event);
			Account acme = organization('Acme Software');

			Test.startTest();
			Id sponsorId = EventSponsorsController.addSponsor(event.Id, acme.Id, level.Id);
			EventSponsorsController.Sponsors result = EventSponsorsController.getSponsors(event.Id);
			Test.stopTest();

			Assert.areEqual(1, result.levels.size(), 'One level');
			Assert.areEqual(1, result.levels[0].sponsorCount, 'It has one sponsor');
			Assert.areEqual(1, result.sponsors.size(), 'One sponsor');
			EventSponsorsController.SponsorRow sponsor = result.sponsors[0];
			Assert.areEqual(sponsorId, sponsor.id, 'The new sponsor');
			Assert.areEqual('Acme Software', sponsor.name, 'Named after the organization');
			Assert.areEqual('Prospect', sponsor.status, 'Prospect by default');
			Assert.areEqual(5000, sponsor.amount, 'The level amount');
			Assert.areEqual('Gold', sponsor.levelName, 'At the level');
			Assert.areEqual(4, sponsor.deliverables.size(), 'The level checklist');
			Map<String, EventSponsorsController.DeliverableRow> byName = new Map<String, EventSponsorsController.DeliverableRow>();
			for (EventSponsorsController.DeliverableRow item : sponsor.deliverables) {
				byName.put(item.name, item);
			}
			Assert.areEqual(
				'Logo',
				byName.get('Logo for the program').type,
				'Typed from the first word'
			);
			Assert.areEqual('Other', byName.get('Thank you post').type, 'Anything else is Other');
			Assert.areEqual('Pending', byName.get('Booth').status, 'Pending to start');
			Assert.isTrue(
				result.canAddSponsor && result.canAddLevel && result.canEdit,
				'Staff may act'
			);
			Assert.isFalse(result.deliverableStatuses.isEmpty(), 'Statuses to choose from');
			Assert.isFalse(result.deliverableTypes.isEmpty(), 'Types to choose from');
		}
	}

	@IsTest
	static void refusesTheSameOrganizationTwiceAndALevelOfAnotherEvent() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Event__c other = conference('Second Event');
			Account acme = organization('Acme Software');
			EventSponsorsController.addSponsor(event.Id, acme.Id, null);

			Test.startTest();
			Boolean duplicate = false;
			Boolean wrongEvent = false;
			try {
				EventSponsorsController.addSponsor(event.Id, acme.Id, null);
			} catch (AuraHandledException e) {
				duplicate = true;
			}
			try {
				EventSponsorsController.addSponsor(
					event.Id,
					organization('Beta Org').Id,
					gold(other).Id
				);
			} catch (AuraHandledException e) {
				wrongEvent = true;
			}
			Id elsewhere = EventSponsorsController.addSponsor(other.Id, acme.Id, null);
			Test.stopTest();

			Assert.isTrue(duplicate, 'The same organization twice is refused');
			Assert.isTrue(wrongEvent, 'A level of another event is refused');
			Assert.isNotNull(elsewhere, 'The same organization may sponsor another event');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Event_Sponsor__c WHERE Account__r.Name = 'Beta Org'],
				'Nothing saved for the refused add'
			);
		}
	}

	@IsTest
	static void movesDeliverablesThroughTheirStatuses() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Id sponsorId = EventSponsorsController.addSponsor(
				event.Id,
				organization('Acme Software').Id,
				gold(event).Id
			);

			Test.startTest();
			Id logo = EventSponsorsController.getSponsors(event.Id).sponsors[0].deliverables[0].id;
			EventSponsorsController.setDeliverableStatus(logo, 'Done');
			EventSponsorsController.addDeliverable(sponsorId, 'Banner at the entrance', 'Other');
			Boolean refused = false;
			try {
				EventSponsorsController.addDeliverable(sponsorId, '  ', 'Other');
			} catch (AuraHandledException e) {
				refused = true;
			}
			Sponsor_Deliverable__c banner = [
				SELECT Type__c
				FROM Sponsor_Deliverable__c
				WHERE Name = 'Banner at the entrance'
			];
			Event_Sponsor__c sponsor = [
				SELECT Deliverables_Total__c, Deliverables_Done__c
				FROM Event_Sponsor__c
				WHERE Id = :sponsorId
			];
			Test.stopTest();

			Assert.isTrue(refused, 'An item needs a name');
			Assert.areEqual('Other', banner.Type__c, 'Typed as given');
			Assert.areEqual(5, sponsor.Deliverables_Total__c, 'Four from the level and one added');
			Assert.areEqual(1, sponsor.Deliverables_Done__c, 'One done');
		}
	}

	@IsTest
	static void aLinkedRecordThatCannotBeLabelledShowsNoLabel() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Id sponsorId = EventSponsorsController.addSponsor(
				event.Id,
				organization('Acme Software').Id,
				null
			);
			update as user new Event_Sponsor__c(
				Id = sponsorId,
				Linked_Record_Id__c = organization('Some Other Record').Id
			);

			Test.startTest();
			EventSponsorsController.Sponsors result = EventSponsorsController.getSponsors(event.Id);
			Test.stopTest();

			Assert.isNotNull(result.sponsors[0].linkedRecordId, 'The identifier is kept');
			Assert.isNull(result.sponsors[0].linkedLabel, 'An unsupported record has no label');
		}
	}

	@IsTest
	static void removingASponsorRemovesItsChecklist() {
		System.runAs(staff()) {
			Event__c event = conference('Community Dreamin');
			Id sponsorId = EventSponsorsController.addSponsor(
				event.Id,
				organization('Acme Software').Id,
				gold(event).Id
			);

			Test.startTest();
			EventSponsorsController.removeSponsor(sponsorId);
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Event_Sponsor__c], 'Sponsor removed');
			Assert.areEqual(0, [SELECT COUNT() FROM Sponsor_Deliverable__c], 'Checklist removed');
			Assert.areEqual(1, [SELECT COUNT() FROM Sponsorship_Level__c], 'The level stays');
		}
	}
}
