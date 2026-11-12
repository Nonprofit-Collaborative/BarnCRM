/**
 * Looking addresses up (ADR-0209 address verification module, decisions 2 to 5; R-AV1 to R-AV3):
 * a Smarty match writes only Verified and today's date; Google's standardized parts are taken
 * only with Apply Corrections on; a vague answer is Failed and keeps the last date; Smarty never
 * looks up a non-US address; a provider error changes nothing and is logged; a change makes an
 * address Unverified and queues its lookup; the nightly batch takes only waiting addresses.
 */
@IsTest(
	testFor='ApexClass:AddressVerifier, ApexClass:AddressVerificationJob, ApexClass:AddressVerificationHandler'
)
private class AddressVerifierTest {
	@TestSetup
	static void createTestUser() {
		System.runAs(TestUsers.admin()) {
			AddressVerificationTestData.admin();
		}
	}

	private static List<Id> idsOf(List<Address__c> rows) {
		return new List<Id>(new Map<Id, Address__c>(rows).keySet());
	}

	@IsTest
	static void aSmartyMatchWritesOnlyTheStatusAndDate() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			Address__c home = AddressVerificationTestData.addresses(1, null)[0];
			AddressVerificationTestData.Provider smarty = new AddressVerificationTestData.Provider(
				200,
				AddressVerificationTestData.SMARTY_FOUND
			);
			Test.setMock(HttpCalloutMock.class, smarty);

			Test.startTest();
			Integer looked = AddressVerifier.verify(new List<Id>{ home.Id });
			Test.stopTest();

			Address__c after = AddressVerificationTestData.reread(home.Id);
			Assert.areEqual(1, looked, 'One lookup');
			Assert.areEqual('Verified', after.Verification_Status__c, 'Verified');
			Assert.areEqual(Date.today(), after.Latest_Verified_Date__c, 'Dated today');
			Assert.areEqual('100 main street', after.Street__c, 'The street is left alone');
			Assert.isTrue(
				smarty.requests[0].getEndpoint().contains('auth-id=auth-id-1111'),
				'The org own key is sent'
			);
		}
	}

	@IsTest
	static void googleCorrectionsAreTakenOnlyWhenSwitchedOn() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.GOOGLE, true);
			Address__c office = AddressVerificationTestData.addresses(1, 'Canada')[0];
			AddressVerificationTestData.Provider google = new AddressVerificationTestData.Provider(
				200,
				AddressVerificationTestData.GOOGLE_FOUND
			);
			Test.setMock(HttpCalloutMock.class, google);

			Test.startTest();
			AddressVerifier.verify(new List<Id>{ office.Id });
			Test.stopTest();

			Address__c after = AddressVerificationTestData.reread(office.Id);
			Assert.areEqual('Verified', after.Verification_Status__c, 'Verified');
			Assert.areEqual('290 Bremner Blvd', after.Street__c, 'Standardized street');
			Assert.areEqual('Toronto', after.City__c, 'Standardized city');
			Assert.areEqual('M5V 2T6', after.Postal_Code__c, 'Standardized postal code');
			Assert.areEqual('Canada', after.Country__c, 'The country never changes');
			Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
				google.requests[0].getBody()
			);
			Assert.areEqual(
				'CA',
				((Map<String, Object>) sent.get('address')).get('regionCode'),
				'The country name is sent as its code'
			);
		}
	}

	@IsTest
	static void aVagueAnswerFailsAndKeepsTheLastDate() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.GOOGLE, true);
			Address__c home = AddressVerificationTestData.addresses(1, 'US')[0];
			Date earlier = Date.today().addYears(-2);
			AddressVerifier.writing = true;
			update new Address__c(Id = home.Id, Latest_Verified_Date__c = earlier);
			AddressVerifier.writing = false;
			Test.setMock(
				HttpCalloutMock.class,
				new AddressVerificationTestData.Provider(
					200,
					AddressVerificationTestData.GOOGLE_VAGUE
				)
			);

			Test.startTest();
			AddressVerifier.verify(new List<Id>{ home.Id });
			Test.stopTest();

			Address__c after = AddressVerificationTestData.reread(home.Id);
			Assert.areEqual('Failed', after.Verification_Status__c, 'Failed');
			Assert.areEqual(earlier, after.Latest_Verified_Date__c, 'The last success is kept');
			Assert.areEqual('100 main street', after.Street__c, 'No correction on a failure');
		}
	}

	@IsTest
	static void smartyNeverLooksUpAnAddressOutsideTheUnitedStates() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			Address__c abroad = AddressVerificationTestData.addresses(1, 'France')[0];
			AddressVerificationTestData.Provider smarty = new AddressVerificationTestData.Provider(
				200,
				AddressVerificationTestData.SMARTY_FOUND
			);
			Test.setMock(HttpCalloutMock.class, smarty);

			Test.startTest();
			Integer looked = AddressVerifier.verify(new List<Id>{ abroad.Id });
			Test.stopTest();

			Assert.areEqual(0, looked, 'Nothing looked up');
			Assert.areEqual(0, smarty.requests.size(), 'No request made');
			Assert.areEqual(
				'Unverified',
				AddressVerificationTestData.reread(abroad.Id).Verification_Status__c,
				'Left Unverified'
			);
		}
	}

	@IsTest
	static void aProviderErrorChangesNothingAndIsLogged() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			Address__c home = AddressVerificationTestData.addresses(1, null)[0];
			Test.setMock(
				HttpCalloutMock.class,
				new AddressVerificationTestData.Provider(401, 'Unauthorized')
			);

			Test.startTest();
			AddressVerifier.verify(new List<Id>{ home.Id });
			Test.stopTest();

			Assert.areEqual(
				'Unverified',
				AddressVerificationTestData.reread(home.Id).Verification_Status__c,
				'Left Unverified'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Context__c = 'AddressVerifier.verify'
					WITH SYSTEM_MODE
				],
				'One entry for the run'
			);
		}
	}

	@IsTest
	static void nothingIsLookedUpWithoutKeys() {
		System.runAs(AddressVerificationTestData.admin()) {
			Address__c home = AddressVerificationTestData.addresses(1, null)[0];
			AddressVerificationTestData.Provider smarty = new AddressVerificationTestData.Provider(
				200,
				AddressVerificationTestData.SMARTY_FOUND
			);
			Test.setMock(HttpCalloutMock.class, smarty);

			Test.startTest();
			Integer looked = AddressVerifier.verify(new List<Id>{ home.Id });
			Id batch = AddressVerificationJob.startBatch();
			Test.stopTest();

			Assert.areEqual(0, looked, 'Nothing looked up');
			Assert.isNull(batch, 'No batch started');
			Assert.areEqual(0, smarty.requests.size(), 'No request made');
		}
	}

	@IsTest
	static void aChangeMakesAnAddressUnverifiedAndQueuesItsLookup() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			Address__c home = AddressVerificationTestData.addresses(1, null)[0];
			AddressVerifier.writing = true;
			update new Address__c(
				Id = home.Id,
				Verification_Status__c = 'Verified',
				Latest_Verified_Date__c = Date.today().addDays(-5)
			);
			AddressVerifier.writing = false;
			Test.setMock(
				HttpCalloutMock.class,
				new AddressVerificationTestData.Provider(
					200,
					AddressVerificationTestData.SMARTY_FOUND
				)
			);

			Test.startTest();
			update new Address__c(Id = home.Id, Street__c = '123 main street');
			String duringSave = AddressVerificationTestData.reread(home.Id).Verification_Status__c;
			Test.stopTest();

			Address__c after = AddressVerificationTestData.reread(home.Id);
			Assert.areEqual('Unverified', duringSave, 'Unverified as soon as it changes');
			Assert.areEqual(
				'Verified',
				after.Verification_Status__c,
				'Looked up by the queued job'
			);
			Assert.areEqual(Date.today(), after.Latest_Verified_Date__c, 'Dated today');
		}
	}

	@IsTest
	static void aChangeElsewhereLeavesTheStatus() {
		Address__c home;
		System.runAs(AddressVerificationTestData.admin()) {
			home = AddressVerificationTestData.addresses(2, null)[1];
			AddressVerifier.writing = true;
			update new Address__c(Id = home.Id, Verification_Status__c = 'Verified');
			AddressVerifier.writing = false;

			update new Address__c(Id = home.Id, Type__c = 'Work');
		}
		Assert.areEqual(
			'Verified',
			AddressVerificationTestData.reread(home.Id).Verification_Status__c,
			'Only the street, city, state, postal code and country count'
		);
	}

	@IsTest
	static void theNightlyBatchTakesOnlyWaitingAddressesUpToTheLimit() {
		System.runAs(AddressVerificationTestData.admin()) {
			AddressVerificationTestData.connect(AddressVerifier.SMARTY, false);
			Address_Verification_Settings__c settings = Address_Verification_Settings__c.getOrgDefaults();
			settings.Nightly_Limit__c = 3;
			upsert settings;
			List<Address__c> rows = AddressVerificationTestData.addresses(5, null);
			AddressVerifier.writing = true;
			update new Address__c(
				Id = rows[4].Id,
				Verification_Status__c = 'Verified',
				Latest_Verified_Date__c = Date.today()
			);
			AddressVerifier.writing = false;
			AddressVerificationTestData.Provider smarty = new AddressVerificationTestData.Provider(
				200,
				AddressVerificationTestData.SMARTY_FOUND
			);
			Test.setMock(HttpCalloutMock.class, smarty);

			Test.startTest();
			new AddressVerificationJob().execute((SchedulableContext) null);
			Test.stopTest();

			Integer verified = [
				SELECT COUNT()
				FROM Address__c
				WHERE Id IN :idsOf(rows) AND Verification_Status__c = 'Verified'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(3, smarty.requests.size(), 'The nightly limit');
			Assert.areEqual(4, verified, 'Three looked up, plus the one verified today');
		}
	}

	@IsTest
	static void aRegionIsACodeOrAKnownName() {
		System.runAs(AddressVerificationTestData.admin()) {
			Assert.areEqual('DE', AddressVerifier.regionOf('de'), 'A two-letter code');
			Assert.areEqual('GB', AddressVerifier.regionOf('United Kingdom'), 'A known name');
			Assert.isNull(AddressVerifier.regionOf('Atlantis'), 'An unknown name');
			Assert.isTrue(AddressVerifier.isUnitedStates('united states'), 'Any case');
			Assert.isFalse(AddressVerifier.isUnitedStates('Mexico'), 'Another country');
		}
	}
}
