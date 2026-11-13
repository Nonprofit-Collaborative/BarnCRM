/**
 * Dana opens the dashboard of a new conference, applies the community conference template once,
 * and cannot apply it a second time (EV-11).
 */
@IsTest(testFor='ApexClass:EventDashboardController')
private class EventDashboardControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private static Event__c conference() {
		Datetime start = Datetime.now().addDays(60);
		Event__c record = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(30)
		);
		insert as user record;
		return record;
	}

	private static String plan(Datetime start) {
		return JSON.serialize(
			new Map<String, Object>{
				'tracks' => new List<Object>{
					new Map<String, Object>{ 'name' => 'Admins', 'sortOrder' => 1 }
				},
				'ticketTypes' => new List<Object>{
					new Map<String, Object>{
						'name' => 'Attendee',
						'price' => 25,
						'sortOrder' => 1
					},
					new Map<String, Object>{
						'name' => 'Speaker',
						'price' => 0,
						'quantity' => 10,
						'sortOrder' => 2
					}
				},
				'sessions' => new List<Object>{
					new Map<String, Object>{
						'name' => 'Admin Talk',
						'sessionType' => 'Talk',
						'room' => 'A',
						'trackName' => 'Admins',
						'startTime' => start.addHours(1),
						'endTime' => start.addHours(2)
					},
					new Map<String, Object>{
						'name' => 'Keynote',
						'sessionType' => 'Keynote',
						'startTime' => start,
						'endTime' => start.addHours(1)
					}
				}
			}
		);
	}

	@IsTest
	static void countsWhatTheEventHasSoFar() {
		System.runAs(staff()) {
			Event__c event = conference();
			EventDashboardController.templatesForTest = '{"templates":[]}';
			EventDashboardController.Dashboard before = EventDashboardController.getDashboard(
				event.Id
			);
			Assert.areEqual(0, before.sessions);
			Assert.areEqual(0, before.speakers);
			Assert.areEqual('Open', before.eventStatus);
			Assert.isTrue(before.canApplyTemplate);
			EventDashboardController.applyPlan(event.Id, plan(event.Start__c));
			EventDashboardController.Dashboard after = EventDashboardController.getDashboard(
				event.Id
			);
			Assert.areEqual(2, after.ticketTypes);
			Assert.areEqual(1, after.tracks);
			Assert.areEqual(2, after.sessions);
			Assert.areEqual('{"templates":[]}', after.templatesJson);
		}
	}

	@IsTest
	static void readsThePackagedTemplatesWhenNoneIsInjected() {
		System.runAs(staff()) {
			Event__c event = conference();
			EventDashboardController.Dashboard result = EventDashboardController.getDashboard(
				event.Id
			);
			Assert.isTrue(
				result.templatesJson.contains('"templates"'),
				'The packaged template file is read'
			);
		}
	}

	@IsTest
	static void countsSpeakersByStatus() {
		System.runAs(staff()) {
			Event__c event = conference();
			Contact ana = new Contact(LastName = 'Garcia');
			Contact sam = new Contact(LastName = 'Lee');
			insert as user new List<Contact>{ ana, sam };
			insert as user new List<Event_Speaker__c>{
				new Event_Speaker__c(
					Event__c = event.Id,
					Contact__c = ana.Id,
					Status__c = 'Confirmed'
				),
				new Event_Speaker__c(
					Event__c = event.Id,
					Contact__c = sam.Id,
					Status__c = 'Invited'
				)
			};
			EventDashboardController.Dashboard result = EventDashboardController.getDashboard(
				event.Id
			);
			Assert.areEqual(2, result.speakers);
			Assert.areEqual(1, result.confirmedSpeakers);
		}
	}

	@IsTest
	static void appliesTheTemplateLinkingSessionsToTheirTracks() {
		System.runAs(staff()) {
			Event__c event = conference();
			Integer added = EventDashboardController.applyPlan(event.Id, plan(event.Start__c));
			Assert.areEqual(2, added);
			Event_Session__c talk = [
				SELECT Track__r.Name, Status__c
				FROM Event_Session__c
				WHERE Name = 'Admin Talk' AND Event__c = :event.Id
			];
			Assert.areEqual('Admins', talk.Track__r.Name);
			Assert.areEqual('Draft', talk.Status__c);
			Event_Session__c keynote = [
				SELECT Track__c
				FROM Event_Session__c
				WHERE Name = 'Keynote' AND Event__c = :event.Id
			];
			Assert.isNull(keynote.Track__c, 'A session with no track named stays in no track');
		}
	}

	@IsTest
	static void refusesToApplyToAnEventThatAlreadyHasAgenda() {
		System.runAs(staff()) {
			Event__c event = conference();
			EventDashboardController.applyPlan(event.Id, plan(event.Start__c));
			try {
				EventDashboardController.applyPlan(event.Id, plan(event.Start__c));
				Assert.fail('A second application is refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					2,
					[SELECT COUNT() FROM Ticket_Type__c WHERE Event__c = :event.Id],
					'Nothing more was added'
				);
			}
		}
	}

	@IsTest
	static void rollsBackWhenASessionBreaksARule() {
		System.runAs(staff()) {
			Event__c event = conference();
			// Ends before it starts: the validation rule refuses it, so the tracks go too. Every
			// list is sent, as the browser's plan always has (JSON leaves a missing list null).
			String bad = JSON.serialize(
				new Map<String, Object>{
					'tracks' => new List<Object>{
						new Map<String, Object>{ 'name' => 'Admins', 'sortOrder' => 1 }
					},
					'ticketTypes' => new List<Object>(),
					'sessions' => new List<Object>{
						new Map<String, Object>{
							'name' => 'Backwards',
							'sessionType' => 'Talk',
							'startTime' => event.Start__c.addHours(2),
							'endTime' => event.Start__c.addHours(1)
						}
					}
				}
			);
			try {
				EventDashboardController.applyPlan(event.Id, bad);
				Assert.fail('A broken plan is refused');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					0,
					[SELECT COUNT() FROM Event_Track__c WHERE Event__c = :event.Id],
					'Rolled back'
				);
				Assert.areNotEqual(
					BarnHelp.text('Events', 'Events_Dashboard_ApplyFailed'),
					refused.getMessage(),
					'The validation rule speaks for itself, not the generic text (D-191)'
				);
			}
		}
	}
}
