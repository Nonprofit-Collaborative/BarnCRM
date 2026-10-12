/**
 * The REST endpoint (X-03): what goes over the wire, status code and body, for the outcomes
 * the API reference documents. The rules themselves are proved in InboundGiftServiceTest.
 */
@IsTest
private class InboundGiftResourceTest {
    private static final String EMAIL = 'luis.garcia.rest@example.org';

    @TestSetup
    static void setup() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new Fund__c(Name = 'General Fund', Active__c = true, Is_Default__c = true);
            insert new Contact(FirstName = 'Luis', LastName = 'Garcia', Email = EMAIL);
        }
    }

    private static Map<String, Object> post(String body) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/v1/gifts';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        InboundGiftResource.create();
        Map<String, Object> answer = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        answer.put('status', RestContext.response.statusCode);
        return answer;
    }

    private static String body(String externalId, Decimal amount) {
        return '{"externalId":"' +
            externalId +
            '","amount":' +
            amount +
            ',"paymentMethod":"Card","donorEmail":"' +
            EMAIL +
            '"}';
    }

    @IsTest
    static void aNewGiftIsCreatedAndASecondSendFindsIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Map<String, Object> first = post(body('stripe:ch_9', 50));
            Map<String, Object> second = post(body('stripe:ch_9', 50));
            Map<String, Object> conflict = post(body('stripe:ch_9', 55));
            Test.stopTest();

            Assert.areEqual(201, first.get('status'));
            Assert.areEqual('created', first.get('outcome'));
            Assert.isFalse(
                first.containsKey('errorCode'),
                'Empty fields are left out of the body.'
            );
            Assert.areEqual(200, second.get('status'));
            Assert.areEqual('existing', second.get('outcome'));
            Assert.areEqual(first.get('giftId'), second.get('giftId'));
            Assert.areEqual(409, conflict.get('status'));
            Assert.areEqual('external_id_conflict', conflict.get('errorCode'));
            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c]);
        }
    }

    @IsTest
    static void badBodiesAndUnknownDonorsGetTheirDocumentedStatus() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Object> unknownField = post(
                '{"externalId":"x:1","amount":5,"colour":"red"}'
            );
            Map<String, Object> missingAmount = post(
                '{"externalId":"x:2","paymentMethod":"Card","donorEmail":"' + EMAIL + '"}'
            );
            Map<String, Object> stranger = post(
                '{"externalId":"x:3","amount":5,"paymentMethod":"Card","donorEmail":"who@example.org"}'
            );

            Assert.areEqual(400, unknownField.get('status'));
            Assert.areEqual('invalid_request', unknownField.get('errorCode'));
            Assert.areEqual(400, missingAmount.get('status'));
            Assert.areEqual('invalid_field', missingAmount.get('errorCode'));
            Assert.areEqual(422, stranger.get('status'));
            Assert.areEqual('donor_not_found', stranger.get('errorCode'));
            Assert.areEqual('rejected', stranger.get('outcome'));
        }
    }
}
