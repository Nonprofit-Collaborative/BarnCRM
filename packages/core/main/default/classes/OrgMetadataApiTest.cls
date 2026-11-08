@IsTest(testFor='ApexClass:OrgMetadataApi')
private class OrgMetadataApiTest {
	private static final String SAVED = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body><upsertMetadataResponse><result><created>true</created><fullName>Contact.BarnCRM_People_Match</fullName><success>true</success></result></upsertMetadataResponse></soapenv:Body></soapenv:Envelope>';
	private static final String REFUSED = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata"><soapenv:Body><upsertMetadataResponse><result><errors><message>Field Phone is not valid</message><statusCode>FIELD_INTEGRITY_EXCEPTION</statusCode></errors><fullName>Contact.BarnCRM_People_Duplicates</fullName><success>false</success></result></upsertMetadataResponse></soapenv:Body></soapenv:Envelope>';
	private static final String FAULT = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><soapenv:Body><soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>INVALID_SESSION_ID: Invalid Session ID</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>';

	private static HttpRequest last;

	private class MetadataMock implements HttpCalloutMock {
		public HttpResponse respond(HttpRequest request) {
			last = request;
			HttpResponse response = new HttpResponse();
			response.setStatusCode(200);
			response.setBody(SAVED);
			return response;
		}
	}

	@TestSetup
	static void createUsers() {
		TestUsers.admin();
	}

	@IsTest
	static void upsertSendsOneCallThroughTheConnection() {
		System.runAs(TestUsers.admin()) {
			Test.setMock(HttpCalloutMock.class, new MetadataMock());
			Test.startTest();
			List<OrgMetadataApi.Result> results = OrgMetadataApi.upsertMetadata(
				'MatchingRule',
				new List<String>{
					OrgMetadataApi.element('fullName', 'Contact.BarnCRM_People_Match') +
					OrgMetadataApi.wrap(
						'matchingRuleItems',
						OrgMetadataApi.element('fieldName', 'A&B')
					)
				}
			);
			Test.stopTest();
			Assert.isTrue(results[0].success, 'Saved.');
			Assert.isTrue(
				last.getEndpoint().startsWith('callout:Barn_Org_Connection/services/Soap/m/'),
				'Through the org connection.'
			);
			String body = last.getBody();
			Assert.isTrue(body.contains('<met:upsertMetadata>'), 'The upsert operation.');
			Assert.isTrue(body.contains('xsi:type="met:MatchingRule"'), 'Typed.');
			Assert.isTrue(body.contains('A&amp;B'), 'Values escaped.');
		}
	}

	@IsTest
	static void resultsReadEachComponentAndAFaultThrows() {
		// runs-as: deploying user (pure parsing of a response text, no data, query or permission)
		List<OrgMetadataApi.Result> results = OrgMetadataApi.results(REFUSED);
		Assert.areEqual(1, results.size(), 'One result.');
		Assert.isFalse(results[0].success, 'Refused.');
		Assert.areEqual('Field Phone is not valid', results[0].message, 'The API words.');
		Assert.isTrue(OrgMetadataApi.results(SAVED)[0].success, 'Saved.');
		try {
			OrgMetadataApi.results(FAULT);
			Assert.fail('A fault throws.');
		} catch (OrgMetadataApi.MetadataException e) {
			Assert.isTrue(e.getMessage().contains('INVALID_SESSION_ID'), 'Its words.');
		}
	}
}
