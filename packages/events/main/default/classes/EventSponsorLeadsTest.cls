/**
 * Acme's rep Rosa scans badges at the community conference booth: Ana shares her details and
 * becomes a lead, Ben does not and nothing about him is kept, a second scan of Ana is Already
 * Scanned, a stranger's code is Not Found, booth staff scan for Acme too, and someone with no
 * sponsorship is refused. Staff download only the leads (EV-28, R-SLD1, R-SLD2).
 */
@IsTest(
	testFor='ApexClass:EventOperationsHandler, ApexTrigger:SponsorLeadTrigger, ApexClass:EventSponsorsController'
)
private class EventSponsorLeadsTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Contact person(String first, String last) {
		Contact record = new Contact(
			FirstName = first,
			LastName = last,
			Email = first.toLowerCase() + '@example.org'
		);
		insert as user record;
		return record;
	}

	private static Event_Attendee__c attend(Event__c event, Contact who, Boolean shares) {
		Event_Registration__c registration = new Event_Registration__c(
			Event__c = event.Id,
			Contact__c = who.Id,
			Status__c = 'Registered',
			Source__c = 'Staff'
		);
		insert as user registration;
		Event_Attendee__c row = new Event_Attendee__c(
			Event_Registration__c = registration.Id,
			Contact__c = who.Id,
			Status__c = 'Registered',
			Badge_Title__c = 'Director',
			Badge_Company__c = 'Food Bank',
			Share_With_Sponsors__c = shares
		);
		insert as user row;
		return row;
	}

	private static Sponsor_Lead__c scan(Contact scanner, String code) {
		return new Sponsor_Lead__c(Scanned_By__c = scanner.Id, Badge_Code__c = code);
	}

	@IsTest
	static void aScanBecomesALeadOnlyWhenTheAttendeeShares() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(10);
			Event__c event = new Event__c(
				Name = 'Community Dreamin',
				Status__c = 'Open',
				Format__c = 'In Person',
				Start__c = start,
				End__c = start.addHours(8)
			);
			insert as user event;
			Contact rosa = person('Rosa', 'Acme');
			Contact sam = person('Sam', 'Booth');
			Event_Sponsor__c acme = new Event_Sponsor__c(
				Event__c = event.Id,
				Name = 'Acme',
				Status__c = 'Confirmed',
				Contact__c = rosa.Id
			);
			insert as user acme;
			Event_Attendee__c ana = attend(event, person('Ana', 'Garcia'), true);
			Event_Attendee__c ben = attend(event, person('Ben', 'Okafor'), false);
			Event_Attendee__c samRow = attend(event, sam, false);
			update as user new Event_Attendee__c(Id = samRow.Id, Sponsor__c = acme.Id);

			Test.startTest();
			List<Sponsor_Lead__c> scans = new List<Sponsor_Lead__c>{
				scan(rosa, ana.Id),
				scan(rosa, ben.Id),
				scan(sam, ana.Id),
				scan(rosa, 'not-a-badge')
			};
			insert as user scans;
			Database.SaveResult stranger = Database.insert(
				scan(person('Lee', 'Nobody'), ana.Id),
				false
			);
			EventSponsorsController.Leads export = EventSponsorsController.getLeads(acme.Id);
			Test.stopTest();

			Map<Id, Sponsor_Lead__c> saved = new Map<Id, Sponsor_Lead__c>(
				[
					SELECT
						Status__c,
						Event_Sponsor__c,
						Event_Attendee__c,
						Badge_Code__c,
						Lead_Name__c,
						Lead_Email__c,
						Lead_Title__c,
						Lead_Company__c
					FROM Sponsor_Lead__c
				]
			);
			Sponsor_Lead__c lead = saved.get(scans[0].Id);
			Assert.areEqual('Lead', lead.Status__c, 'Ana shares (R-SLD2)');
			Assert.areEqual(acme.Id, lead.Event_Sponsor__c, 'On Rosa sponsorship (R-SLD1)');
			Assert.areEqual('Ana Garcia', lead.Lead_Name__c, 'Name copied');
			Assert.areEqual('ana@example.org', lead.Lead_Email__c, 'Email copied');
			Assert.areEqual('Director', lead.Lead_Title__c, 'Title copied');
			Assert.areEqual('Food Bank', lead.Lead_Company__c, 'Company copied');
			Sponsor_Lead__c hidden = saved.get(scans[1].Id);
			Assert.areEqual('Not Shared', hidden.Status__c, 'Ben does not share');
			Assert.isNull(hidden.Event_Attendee__c, 'No link to Ben');
			Assert.isNull(hidden.Lead_Name__c, 'Nothing about Ben');
			Assert.isNull(hidden.Badge_Code__c, 'Not even his code');
			Assert.areEqual(
				'Already Scanned',
				saved.get(scans[2].Id).Status__c,
				'Once per sponsor'
			);
			Assert.areEqual(
				acme.Id,
				saved.get(scans[2].Id).Event_Sponsor__c,
				'Booth staff scan for Acme'
			);
			Assert.areEqual('Not Found', saved.get(scans[3].Id).Status__c, 'Not a badge');
			Assert.isFalse(stranger.isSuccess(), 'No sponsorship, no scan');
			Assert.areEqual(1, export.rows.size(), 'Only the lead is exported');
			Assert.areEqual(
				7,
				export.columns.size(),
				'Name, email, title, company, interest, notes, date'
			);
		}
	}
}
