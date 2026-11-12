/**
 * The Grant Finder (F-09, R-GN11, R-FS2): a Grants.gov search read into listings, Save to
 * Pipeline making a Prospect grant and its funder once, a saved listing marked, a failed search
 * logged and explained, the setting turning it off, and a reader who cannot save.
 */
@IsTest(testFor='ApexClass:GrantFinder, ApexClass:GrantFinderController')
private class GrantFinderTest {
	private static final String FOUND =
		'{"errorcode":0,"data":{"hitCount":2,"oppHits":[' +
		'{"id":"350001","number":"ED-GRANTS-2027","title":"Literacy Grants","agency":"Department of Education",' +
		'"openDate":"01/15/2027","closeDate":"03/31/2027","oppStatus":"posted","cfdaList":["84.287"]},' +
		'{"id":"350002","number":"HHS-2027","title":"Forecast Program","agencyCode":"HHS",' +
		'"openDate":"","closeDate":"","oppStatus":"forecasted","alnist":["93.6XX9"]}]}}';

	private class GrantsGov implements HttpCalloutMock {
		private final Integer status;
		private final String body;
		GrantsGov(Integer status, String body) {
			this.status = status;
			this.body = body;
		}
		public HttpResponse respond(HttpRequest request) {
			Assert.areEqual(GrantFinder.ENDPOINT, request.getEndpoint(), 'The public search API');
			Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
				request.getBody()
			);
			Assert.areEqual(
				'posted|forecasted',
				sent.get('oppStatuses'),
				'Only known statuses are sent'
			);
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			response.setBody(body);
			return response;
		}
	}

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.standardUserWith(
			'Gfreader',
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
		);
	}

	private static final List<String> BOTH = new List<String>{ 'Posted', 'forecasted', 'archived' };

	@IsTest
	static void aSearchSavesAProspectOnce() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Test.setMock(HttpCalloutMock.class, new GrantsGov(200, FOUND));

			Test.startTest();
			List<GrantFinder.Listing> listings = GrantFinderController.search('literacy', BOTH);
			Id grantId = GrantFinderController.save(JSON.serialize(listings[0]));
			Id again = GrantFinderController.save(JSON.serialize(listings[0]));
			// A callout cannot follow the save in one transaction, so the marking is checked alone.
			List<GrantFinder.Listing> marked = listings.clone();
			GrantFinder.markSaved(marked);
			Test.stopTest();

			Assert.areEqual(2, listings.size(), 'Both hits');
			Assert.areEqual(
				Date.newInstance(2027, 3, 31),
				listings[0].closeDate,
				'MM/DD/YYYY read'
			);
			Assert.isNull(listings[1].closeDate, 'No date');
			Assert.areEqual('HHS', listings[1].agency, 'The agency code when no name');
			Assert.areEqual(
				GrantFinder.LISTING_PAGE + '350001',
				listings[0].url,
				'Its Grants.gov page'
			);
			Assert.areEqual(grantId, again, 'Saved once');
			Assert.areEqual(grantId, marked[0].grantId, 'Marked saved');
			Grant__c grant = [
				SELECT
					Name,
					Stage__c,
					Application_Deadline__c,
					Funding_Source__c,
					Federal_Agency__c,
					Assistance_Listing_Number__c,
					Funder__r.Name
				FROM Grant__c
				WHERE Id = :grantId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Literacy Grants', grant.Name, 'The title');
			Assert.areEqual('Prospect', grant.Stage__c, 'A prospect');
			Assert.areEqual(
				Date.newInstance(2027, 3, 31),
				grant.Application_Deadline__c,
				'The close date'
			);
			Assert.areEqual('Federal', grant.Funding_Source__c, 'Federal');
			Assert.areEqual('84.287', grant.Assistance_Listing_Number__c, 'The listing number');
			Assert.areEqual(
				'Department of Education',
				grant.Funder__r.Name,
				'A funder of the agency name'
			);

			GrantFinder.Listing forecast = listings[1];
			Id second = GrantFinder.save(forecast);
			Assert.isNull(
				[
					SELECT Assistance_Listing_Number__c
					FROM Grant__c
					WHERE Id = :second
					WITH SYSTEM_MODE
				]
				.Assistance_Listing_Number__c,
				'A number of another shape is left out'
			);
		}
	}

	@IsTest
	static void aFailedSearchIsLoggedAndExplained() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Test.setMock(HttpCalloutMock.class, new GrantsGov(503, 'down'));
			Boolean explained = false;
			Test.startTest();
			try {
				GrantFinderController.search('literacy', BOTH);
			} catch (AuraHandledException e) {
				explained = e.getMessage().contains('Grants.gov');
			}
			Test.stopTest();
			Assert.isTrue(explained, 'A message a person can act on');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'GrantFinderController.search'
					WITH SYSTEM_MODE
				],
				'Logged'
			);
		}
	}

	@IsTest
	static void theSettingTurnsItOff() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			OrgSettingsSystemWriter.save(
				Funders_Settings__c.SObjectType,
				new Map<Schema.SObjectField, Object>{
					Funders_Settings__c.Grant_Finder_Enabled__c => false
				}
			);
			SettingsService.clearCaches();
			Boolean refused = false;
			Test.startTest();
			try {
				GrantFinderController.search('literacy', BOTH);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();
			Assert.isFalse((Boolean) GrantFinderController.getStatus().get('enabled'), 'Off');
			Assert.isTrue(refused, 'No search while off');
		}
	}

	@IsTest
	static void aReaderSearchesButCannotSave() {
		User reader = [SELECT Id FROM User WHERE LastName = 'Gfreader' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Test.setMock(HttpCalloutMock.class, new GrantsGov(200, FOUND));
			Boolean refused = false;
			Test.startTest();
			List<GrantFinder.Listing> listings = GrantFinderController.search('literacy', BOTH);
			try {
				GrantFinderController.save(JSON.serialize(listings[0]));
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();
			Assert.isFalse(
				(Boolean) GrantFinderController.getStatus().get('canSave'),
				'No Save to Pipeline'
			);
			Assert.isTrue(refused, 'Saving is refused');
		}
	}
}
