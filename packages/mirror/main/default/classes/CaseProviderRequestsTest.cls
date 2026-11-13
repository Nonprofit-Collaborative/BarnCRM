/**
 * The Mirror Case bridge (D-201): nothing is sent while the setting is off; the flow action sends
 * a Case and keeps the provider's number; a refusal is kept and the next run sends the Case again;
 * the nightly run reads the status of requests not yet finished and sends nothing twice. Case is
 * reached by name, as the class does, so the test compiles where Case is not available.
 */
@IsTest(
	testFor='ApexClass:CaseProviderRequests, ApexClass:CaseProviderRequestAction, ApexClass:CaseProviderRequestsNightly'
)
private class CaseProviderRequestsTest {
	private static final String CASE_OBJECT = 'Case';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	/** Answers the provider's API: a status code for sends, the given requests for reads. */
	private class Provider implements HttpCalloutMock {
		Integer sendCode;
		List<Object> statuses;
		List<HttpRequest> received = new List<HttpRequest>();
		/** Bodies sent instead of the usual answer, one per send in turn; null for the usual. */
		List<String> rawBodies = new List<String>();
		Provider(Integer sendCode, List<Object> statuses) {
			this.sendCode = sendCode;
			this.statuses = statuses;
		}
		public HttpResponse respond(HttpRequest request) {
			received.add(request);
			HttpResponse response = new HttpResponse();
			if (request.getMethod() == 'GET') {
				response.setStatusCode(200);
				response.setBody(JSON.serialize(new Map<String, Object>{ 'requests' => statuses }));
				return response;
			}
			Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
				request.getBody()
			);
			response.setStatusCode(sendCode);
			String raw = rawBodies.isEmpty() ? null : rawBodies.remove(0);
			if (raw != null) {
				response.setBody(raw);
				return response;
			}
			response.setBody(
				sendCode == 201
					? JSON.serialize(
							new Map<String, Object>{
								'reference' => body.get('reference'),
								'number' => 'REQ-000042',
								'status' => 'New'
							}
					  )
					: '{"error":"not_allowed"}'
			);
			return response;
		}
	}

	private static void turnOn(Boolean enabled) {
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		settings.Case_Requests_Enabled__c = enabled;
		settings.Case_Requests_Type__c = 'Other';
		upsert settings;
	}

	/** A Case of the chosen Type, and its number. */
	private static SObject newCase() {
		SObject record = CaseProviderRequests.caseType().newSObject();
		record.put('Subject', 'The printer is offline');
		record.put('Type', 'Other');
		record.put('Priority', 'High');
		record.put('SuppliedName', 'Sam Sender');
		record.put('SuppliedEmail', 'sam@example.org');
		insert record;
		return Database.queryWithBinds(
			'SELECT Id, CaseNumber FROM ' + CASE_OBJECT + ' WHERE Id = :caseId',
			new Map<String, Object>{ 'caseId' => record.Id },
			AccessLevel.USER_MODE
		)[0];
	}

	/**
	 * The row the class kept. Read in system mode, as the class writes it: the test user holds
	 * no Mirror permission set, so field access on Provider Request is not this test's subject.
	 */
	private static Provider_Request__c kept(Id caseId) {
		return [
			SELECT Name, Request_Number__c, Status__c, Resolution__c, Error__c, Synced__c
			FROM Provider_Request__c
			WHERE Case_Id__c = :caseId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theNightlyStepQueuesTheRunWhileOn() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			Test.setMock(HttpCalloutMock.class, new Provider(201, new List<Object>()));
			Test.startTest();
			new CaseProviderRequestsNightly().execute(null);
			Assert.areEqual(1, Limits.getQueueableJobs(), 'On: the run is queued');
			Test.stopTest();
		}
	}

	@IsTest
	static void nothingIsSentWhileOff() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(false);
			SObject record = newCase();
			Test.startTest();
			CaseProviderRequestAction.send(new List<Id>{ record.Id });
			new CaseProviderRequestsNightly().execute(null);
			Assert.areEqual(0, Limits.getQueueableJobs(), 'Off: nothing queued');
			Test.stopTest();
			Assert.isFalse(CaseProviderRequests.step().active, 'Off: not in tonight run');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Provider_Request__c WITH SYSTEM_MODE],
				'Nothing kept'
			);
		}
	}

	@IsTest
	static void theActionSendsTheCaseAndKeepsTheNumber() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject record = newCase();
			Provider provider = new Provider(201, new List<Object>());
			Test.setMock(HttpCalloutMock.class, provider);
			Test.startTest();
			CaseProviderRequestAction.send(new List<Id>{ record.Id, record.Id });
			Test.stopTest();
			Provider_Request__c row = kept(record.Id);
			Assert.areEqual(record.get('CaseNumber'), row.Name, 'Named for the Case');
			Assert.areEqual('REQ-000042', row.Request_Number__c, 'Provider number');
			Assert.areEqual('New', row.Status__c, 'Provider status');
			Assert.isNull(row.Error__c, 'No error');
			Assert.areEqual(1, provider.received.size(), 'Sent once');
			Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
				provider.received[0].getBody()
			);
			Assert.areEqual(UserInfo.getOrganizationId(), body.get('orgId'), 'This org');
			Assert.areEqual(record.get('CaseNumber'), body.get('reference'), 'Case Number');
			Assert.areEqual('sam@example.org', body.get('requesterEmail'), 'Who asked');
			Assert.isTrue(
				provider.received[0].getEndpoint().startsWith('callout:Barn_Request_Provider/'),
				'Through the named credential'
			);
		}
	}

	@IsTest
	static void aRefusalIsKeptAndTheNextRunSendsAgain() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject record = newCase();
			insert as system new Provider_Request__c(
				Name = (String) record.get('CaseNumber'),
				Case_Id__c = record.Id,
				Error__c = 'Earlier failure'
			);
			Provider provider = new Provider(403, new List<Object>());
			Test.setMock(HttpCalloutMock.class, provider);
			Test.startTest();
			new CaseProviderRequests().execute((QueueableContext) null);
			Test.stopTest();
			Provider_Request__c row = kept(record.Id);
			Assert.isNull(row.Request_Number__c, 'Not accepted');
			Assert.isTrue(row.Error__c.contains('403'), 'The refusal kept: ' + row.Error__c);
			Assert.areEqual(1, provider.received.size(), 'The nightly run sent it again');
		}
	}

	@IsTest
	static void theNightlyRunReadsStatusAndSendsNothingTwice() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject record = newCase();
			String caseNumber = (String) record.get('CaseNumber');
			insert as system new Provider_Request__c(
				Name = caseNumber,
				Case_Id__c = record.Id,
				Request_Number__c = 'REQ-000042',
				Status__c = 'In Progress'
			);
			Provider provider = new Provider(
				201,
				new List<Object>{
					new Map<String, Object>{
						'reference' => caseNumber,
						'number' => 'REQ-000042',
						'status' => 'Resolved',
						'resolution' => 'Replaced the toner'
					}
				}
			);
			Test.setMock(HttpCalloutMock.class, provider);
			Test.startTest();
			new CaseProviderRequests().execute((QueueableContext) null);
			Test.stopTest();
			Provider_Request__c row = kept(record.Id);
			Assert.areEqual('Resolved', row.Status__c, 'Status read back');
			Assert.areEqual('Replaced the toner', row.Resolution__c, 'Resolution read back');
			Assert.isNotNull(row.Synced__c, 'Synced');
			Assert.areEqual(1, provider.received.size(), 'One status call, no second send');
			Assert.areEqual('GET', provider.received[0].getMethod(), 'Status call');
		}
	}

	/**
	 * The nightly sweep leaves out Cases the provider already accepted in its query, so an org
	 * with many accepted Cases still open still sends its new ones.
	 */
	@IsTest
	static void theSweepLeavesOutAcceptedCases() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject accepted = newCase();
			SObject refused = newCase();
			SObject fresh = newCase();
			insert as system new List<Provider_Request__c>{
				new Provider_Request__c(
					Name = (String) accepted.get('CaseNumber'),
					Case_Id__c = accepted.Id,
					Request_Number__c = 'REQ-000042',
					Status__c = 'In Progress'
				),
				new Provider_Request__c(
					Name = (String) refused.get('CaseNumber'),
					Case_Id__c = refused.Id,
					Error__c = 'Earlier failure'
				)
			};

			Test.startTest();
			List<Id> pending = CaseProviderRequests.unsent();
			Test.stopTest();

			Assert.isFalse(pending.contains(accepted.Id), 'Accepted: not read again');
			Assert.isTrue(pending.contains(refused.Id), 'Refused: sent again');
			Assert.isTrue(pending.contains(fresh.Id), 'New: sent');
		}
	}

	/** An answer that is not a JSON object is kept as that Case's error; the others still save. */
	@IsTest
	static void anUnreadableAnswerCostsOnlyItsOwnCase() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject first = newCase();
			SObject second = newCase();
			Provider provider = new Provider(201, new List<Object>());
			provider.rawBodies.add('["not", "an", "object"]');
			Test.setMock(HttpCalloutMock.class, provider);

			Test.startTest();
			new CaseProviderRequests(new List<Id>{ first.Id, second.Id }, false)
				.execute((QueueableContext) null);
			Test.stopTest();

			Assert.areEqual(2, provider.received.size(), 'Both were sent');
			Integer accepted = 0;
			Integer unreadable = 0;
			for (Provider_Request__c row : [
				SELECT Request_Number__c, Error__c
				FROM Provider_Request__c
				WITH SYSTEM_MODE
			]) {
				if (row.Request_Number__c != null) {
					accepted++;
				} else if (row.Error__c != null) {
					unreadable++;
				}
			}
			Assert.areEqual(1, accepted, 'The readable answer is kept');
			Assert.areEqual(1, unreadable, 'The unreadable one is kept as an error');
		}
	}

	/** Out of callouts, the job sends what it can and leaves the rest for the next job. */
	@IsTest
	static void outOfCalloutsTheRestWaits() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (CaseProviderRequests.caseType() == null) {
				return;
			}
			turnOn(true);
			SObject first = newCase();
			SObject second = newCase();
			Provider provider = new Provider(201, new List<Object>());
			Test.setMock(HttpCalloutMock.class, provider);
			CaseProviderRequests.calloutsLeftForTest = 1;

			Test.startTest();
			new CaseProviderRequests(new List<Id>{ first.Id, second.Id }, false)
				.execute((QueueableContext) null);
			Test.stopTest();

			Assert.areEqual(1, provider.received.size(), 'One callout, as allowed');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Provider_Request__c WITH SYSTEM_MODE],
				'Only the Case sent is kept; the other waits, not marked failed'
			);
		}
	}
}
