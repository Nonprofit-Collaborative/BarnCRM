@IsTest(testFor='ApexClass:ReportSubscriptions, ApexClass:OrgToolingApi')
private class ReportSubscriptionsTest {
	private static final List<String> CONNECTION_ADMIN = new List<String>{
		'BarnCRM_Admin',
		'BarnCRM_Metadata_Admin'
	};
	// 15 characters, so Apex adds the right case suffix and JSON.deserialize accepts it.
	private static final Id REPORT_ID = '00O000000000001';

	private static List<HttpRequest> sent = new List<HttpRequest>();

	/** Answers the notifications API: the person's subscriptions, the limit, and saves. */
	private class AnalyticsMock implements HttpCalloutMock {
		private final String existing;
		private final Integer remaining;
		private final Integer status;

		AnalyticsMock(String existing, Integer remaining, Integer status) {
			this.existing = existing;
			this.remaining = remaining;
			this.status = status;
		}

		public HttpResponse respond(HttpRequest request) {
			sent.add(request);
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			String endpoint = request.getEndpoint();
			if (status >= 300) {
				response.setBody(
					'[{"message":"Session expired","errorCode":"INVALID_SESSION_ID"}]'
				);
			} else if (endpoint.contains('/limits')) {
				response.setBody(
					'{"userLimit":{"max":7,"remaining":' + String.valueOf(remaining) + '}}'
				);
			} else if (request.getMethod() == 'GET') {
				response.setBody(existing);
			} else {
				response.setBody('{"id":"0Au000000000001AAA"}');
			}
			return response;
		}
	}

	@TestSetup
	static void createUsers() {
		TestUsers.withPermissionSets(CONNECTION_ADMIN);
	}

	private static ReportSubscriptions.Choice weekly() {
		ReportSubscriptions.Choice chosen = new ReportSubscriptions.Choice();
		chosen.reportId = REPORT_ID;
		chosen.frequency = 'weekly';
		chosen.weekday = 'mon';
		chosen.hour = 7;
		return chosen;
	}

	@IsTest
	static void viewSaysWhetherThePersonCanSubscribeHere() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			ImportNewFieldService.systemPermissionOverride = true;
			ImportNewFieldService.connectedOverride = true;
			ImportNewFieldService.calloutStatusOverride = 'Enabled';
			ReportSubscriptions.SubscriptionView view = ReportSubscriptions.getView();
			Assert.isTrue(view.canSubscribe, 'Connected admin.');
			Assert.isNotNull(view.reports, 'A list, possibly empty in a test.');
			ImportNewFieldService.calloutStatusOverride = 'Disabled';
			view = ReportSubscriptions.getView();
			Assert.isFalse(view.canSubscribe, 'Callouts off.');
			Assert.isTrue(view.canUseConnection, 'Still may use it once it is on.');
		}
	}

	@IsTest
	static void subscribeExplainsAMissingConnection() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			ImportNewFieldService.systemPermissionOverride = true;
			ImportNewFieldService.connectedOverride = false;
			try {
				ReportSubscriptions.subscribe(JSON.serialize(weekly()));
				Assert.fail('No connection.');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_ReportSubscriptions_ConnectionNeeded'),
					e.getMessage(),
					'Explains the connection.'
				);
			}
		}
	}

	@IsTest
	static void subscribeRefusesAnIncompleteSchedule() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			ImportNewFieldService.systemPermissionOverride = true;
			ImportNewFieldService.connectedOverride = true;
			ImportNewFieldService.calloutStatusOverride = 'Enabled';
			ReportSubscriptions.Choice chosen = weekly();
			chosen.weekday = 'someday';
			try {
				ReportSubscriptions.subscribe(JSON.serialize(chosen));
				Assert.fail('Refused.');
			} catch (AuraHandledException e) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_ReportSubscriptions_ScheduleInvalid'),
					e.getMessage(),
					'Says what to choose.'
				);
			}
		}
	}

	@IsTest
	static void validAcceptsEachFrequencyAndRefusesBadValues() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			ReportSubscriptions.Choice chosen = weekly();
			Assert.isTrue(ReportSubscriptions.valid(chosen), 'Weekly on Monday.');
			chosen.frequency = 'daily';
			Assert.isTrue(ReportSubscriptions.valid(chosen), 'Daily.');
			chosen.frequency = 'monthly';
			Assert.isFalse(ReportSubscriptions.valid(chosen), 'Monthly needs a date.');
			chosen.monthDay = 31;
			Assert.isTrue(ReportSubscriptions.valid(chosen), 'Monthly on the 31st.');
			chosen.hour = 24;
			Assert.isFalse(ReportSubscriptions.valid(chosen), 'No hour 24.');
			chosen.hour = 0;
			chosen.frequency = 'hourly';
			Assert.isFalse(ReportSubscriptions.valid(chosen), 'Not a frequency.');
		}
	}

	@IsTest
	static void createsANewSubscriptionWhenThereIsRoom() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			Test.setMock(HttpCalloutMock.class, new AnalyticsMock('[]', 3, 200));
			Test.startTest();
			String failure = ReportSubscriptions.save(weekly(), 'LYBUNT Donors');
			Test.stopTest();
			Assert.isNull(failure, 'Saved.');
			Assert.areEqual(3, sent.size(), 'Existing, limit, create.');
			HttpRequest created = sent[2];
			Assert.areEqual('POST', created.getMethod(), 'Created.');
			Assert.isTrue(
				created.getEndpoint().endsWith('/analytics/notifications'),
				'The notifications API.'
			);
			Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
				created.getBody()
			);
			Assert.areEqual(
				'lightningReportSubscribe',
				body.get('source'),
				'A report subscription.'
			);
			Map<String, Object> schedule = (Map<String, Object>) body.get('schedule');
			Assert.areEqual('weekly', schedule.get('frequency'), 'Weekly.');
			Map<String, Object> details = (Map<String, Object>) schedule.get('details');
			Assert.areEqual(7, details.get('time'), 'At 7.');
			Assert.areEqual('mon', ((List<Object>) details.get('daysOfWeek'))[0], 'On Monday.');
		}
	}

	@IsTest
	static void updatesTheSubscriptionThePersonAlreadyHas() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			Test.setMock(
				HttpCalloutMock.class,
				new AnalyticsMock('[{"id":"0Au000000000009AAA"}]', 0, 200)
			);
			Test.startTest();
			String failure = ReportSubscriptions.save(weekly(), 'LYBUNT Donors');
			Test.stopTest();
			Assert.isNull(failure, 'Saved.');
			Assert.areEqual(2, sent.size(), 'Existing, then update; no limit check.');
			Assert.areEqual('PUT', sent[1].getMethod(), 'Updated, not duplicated.');
			Assert.isTrue(sent[1].getEndpoint().endsWith('0Au000000000009AAA'), 'That one.');
		}
	}

	@IsTest
	static void saysSoWhenThePersonHasNoRoomLeft() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			Test.setMock(HttpCalloutMock.class, new AnalyticsMock('[]', 0, 200));
			Test.startTest();
			String failure = ReportSubscriptions.save(weekly(), 'LYBUNT Donors');
			Test.stopTest();
			Assert.areEqual(
				BarnHelp.text(
					'Core',
					'Core_ReportSubscriptions_LimitReached',
					new List<Object>{ 7 }
				),
				failure,
				'In words, with the limit.'
			);
			Assert.areEqual(2, sent.size(), 'Nothing created.');
		}
	}

	@IsTest
	static void aRefusedCallNeverThrowsFromTheJob() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			Test.setMock(HttpCalloutMock.class, new AnalyticsMock('[]', 3, 401));
			Test.startTest();
			new ReportSubscriptions.SubscribeJob(weekly(), 'LYBUNT Donors').execute(null);
			Test.stopTest();
			Assert.areEqual(1, sent.size(), 'Stopped at the first refusal.');
		}
	}

	@IsTest
	static void checkSaysFailedForAJobThatIsNotTheirs() {
		System.runAs(TestUsers.withPermissionSets(CONNECTION_ADMIN)) {
			ReportSubscriptions.Outcome outcome = ReportSubscriptions.check('707000000000001AAA');
			Assert.areEqual(ReportSubscriptions.FAILED, outcome.state, 'Unknown job.');
		}
	}
}
