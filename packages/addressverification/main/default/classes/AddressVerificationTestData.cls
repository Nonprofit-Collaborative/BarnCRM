/**
 * Address Verification test data: the admin, keys for a provider, addresses, and a provider
 * stand-in that answers every lookup the same way and keeps each request.
 */
@IsTest
public class AddressVerificationTestData {
	public static final String ADMIN = 'Address_Verification_Admin';

	public static final String SMARTY_FOUND = '[{"delivery_line_1":"123 Main St","components":{"city_name":"Springfield","state_abbreviation":"IL","zipcode":"62701","plus4_code":"1234"},"analysis":{"dpv_match_code":"Y"}}]';
	public static final String GOOGLE_FOUND = '{"result":{"verdict":{"validationGranularity":"PREMISE"},"address":{"postalAddress":{"regionCode":"CA","postalCode":"M5V 2T6","administrativeArea":"ON","locality":"Toronto","addressLines":["290 Bremner Blvd"]}}}}';
	public static final String GOOGLE_VAGUE = '{"result":{"verdict":{"validationGranularity":"ROUTE","hasUnconfirmedComponents":true}}}';

	public static User admin() {
		return TestUsers.adminWith(ADMIN);
	}

	/** The provider chosen and its keys entered, with the other choices given. */
	public static void connect(String provider, Boolean corrections) {
		Address_Verification_Settings__c settings = Address_Verification_Settings__c.getOrgDefaults();
		settings.SetupOwnerId = UserInfo.getOrganizationId();
		settings.Provider__c = provider;
		settings.Apply_Corrections__c = corrections;
		settings.Verify_On_Save__c = true;
		settings.Recheck_Months__c = 12;
		settings.Nightly_Limit__c = 200;
		upsert settings;
		Address_Verification_Keys__c keys = Address_Verification_Keys__c.getOrgDefaults();
		keys.SetupOwnerId = UserInfo.getOrganizationId();
		keys.Smarty_Auth_Id__c = 'auth-id-1111';
		keys.Smarty_Auth_Token__c = 'auth-token-2222';
		keys.Google_Api_Key__c = 'AIza-3333';
		upsert keys;
	}

	/** Current addresses of one organization, inserted without the module's handler queueing. */
	public static List<Address__c> addresses(Integer count, String country) {
		Account owner = (Account) TestDataFactory.fillOrgRequiredFields(
			new Account(Name = 'Zzav Organization')
		);
		Database.insert(owner, AccessLevel.SYSTEM_MODE);
		List<Address__c> rows = new List<Address__c>();
		for (Integer i = 0; i < count; i++) {
			rows.add(
				new Address__c(
					Account__c = owner.Id,
					Street__c = (100 + i) + ' main street',
					City__c = 'springfield',
					State__c = 'IL',
					Postal_Code__c = '62701',
					Country__c = country,
					Status__c = 'Current',
					Is_Default__c = i == 0
				)
			);
		}
		AddressVerifier.writing = true;
		Database.insert(rows, AccessLevel.SYSTEM_MODE);
		AddressVerifier.writing = false;
		return rows;
	}

	public static Address__c reread(Id addressId) {
		return [
			SELECT
				Id,
				Street__c,
				City__c,
				State__c,
				Postal_Code__c,
				Country__c,
				Verification_Status__c,
				Latest_Verified_Date__c
			FROM Address__c
			WHERE Id = :addressId
			WITH SYSTEM_MODE
		];
	}

	/** Answers every request with one status and body, and keeps each request. */
	public class Provider implements HttpCalloutMock {
		public Integer status;
		public String body;
		public List<HttpRequest> requests = new List<HttpRequest>();

		public Provider(Integer status, String body) {
			this.status = status;
			this.body = body;
		}

		public HttpResponse respond(HttpRequest request) {
			requests.add(request);
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			response.setBody(body);
			return response;
		}
	}
}
