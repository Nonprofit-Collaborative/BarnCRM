/**
 * The checks an inbound gift passes before any query (X-03, ADR-0051), the gift it becomes, and
 * the HTTP status each answer is given. Nothing here touches the database.
 */
@IsTest(testFor='ApexClass:InboundGiftRequest')
private class InboundGiftRequestTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static InboundGift gift(String externalId, Decimal amount) {
        InboundGift request = new InboundGift();
        request.externalId = externalId;
        request.amount = amount;
        request.paymentMethod = 'Card';
        request.donorEmail = 'luis.garcia.inbound@example.org';
        return request;
    }

    private static InboundGiftRequest checked(InboundGift request) {
        InboundGiftRequest item = new InboundGiftRequest(request);
        item.validate();
        return item;
    }

    private static String fakeId(Schema.SObjectType type) {
        return type.getDescribe().getKeyPrefix() + '000000000001';
    }

    @IsTest
    static void aWellFormedGiftPassesAndBecomesAReceivedGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            InboundGift request = gift(' Stripe:CH_1 ', 50);
            request.paymentMethod = ' card ';
            request.paymentReference = ' ch_1 ';

            InboundGiftRequest item = checked(request);
            item.donorContactId = fakeId(Contact.SObjectType);
            Gift__c made = item.toGift();

            Assert.isNull(item.result, 'No problem found.');
            Assert.areEqual('Stripe:CH_1', item.externalId, 'Stored as sent, trimmed.');
            Assert.areEqual('stripe:ch_1', item.key, 'Matched ignoring case, as the index does.');
            Assert.areEqual('Card', made.Type__c, 'The method is matched ignoring case.');
            Assert.areEqual('Received', made.Status__c);
            Assert.areEqual(Date.today(), made.Gift_Date__c, 'No date means today.');
            Assert.areEqual('ch_1', made.Payment_Reference__c);
            Assert.areEqual(50, made.Amount__c);
            Assert.areEqual(item.donorContactId, made.Donor_Contact__c);
            Assert.isNull(made.Donor_Account__c);
        }
    }

    @IsTest
    static void everyMalformedFieldIsRefusedAsInvalid() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            InboundGift noId = gift(' ', 10);
            InboundGift longId = gift('x'.repeat(InboundGiftRequest.MAX_EXTERNAL_ID + 1), 10);
            InboundGift noAmount = gift('v:1', null);
            InboundGift zero = gift('v:2', 0);
            InboundGift negative = gift('v:3', -5);
            InboundGift fractions = gift('v:4', 10.005);
            InboundGift inKind = gift('v:5', 10);
            inKind.paymentMethod = 'In-kind';
            InboundGift noMethod = gift('v:6', 10);
            noMethod.paymentMethod = null;
            InboundGift twoDonors = gift('v:7', 10);
            twoDonors.donorId = fakeId(Account.SObjectType);
            InboundGift noDonor = gift('v:8', 10);
            noDonor.donorEmail = null;
            InboundGift twoFunds = gift('v:9', 10);
            twoFunds.fundCode = '4100';
            twoFunds.fundId = fakeId(Fund__c.SObjectType);
            InboundGift longReference = gift('v:10', 10);
            longReference.paymentReference = 'r'
                .repeat(InboundGiftRequest.MAX_PAYMENT_REFERENCE + 1);

            List<InboundGift> malformed = new List<InboundGift>{
                noId,
                longId,
                noAmount,
                zero,
                negative,
                fractions,
                inKind,
                noMethod,
                twoDonors,
                noDonor,
                twoFunds,
                longReference,
                null
            };
            List<InboundGiftResult> results = new List<InboundGiftResult>();
            for (InboundGift request : malformed) {
                results.add(checked(request).result);
            }

            for (InboundGiftResult result : results) {
                Assert.areEqual(InboundGiftResult.OUTCOME_REJECTED, result.outcome);
                Assert.areEqual(
                    InboundGiftResult.ERROR_INVALID_FIELD,
                    result.errorCode,
                    result.message
                );
                Assert.areEqual(400, InboundGiftResult.httpStatus(result));
                Assert.isNull(result.giftId);
            }
            Assert.isTrue(results[6].message.contains('Grant'), 'The allowed methods are listed.');
            Assert.isFalse(results[6].message.contains('In-kind'), 'Goods have no amount.');
        }
    }

    @IsTest
    static void anIdIsReadOnlyWhenItIsOne() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isNull(InboundGiftRequest.asId(null));
            Assert.isNull(InboundGiftRequest.asId('not-an-id'));
            Assert.areEqual(
                Id.valueOf(fakeId(Account.SObjectType)),
                InboundGiftRequest.asId(' ' + fakeId(Account.SObjectType) + ' ')
            );
        }
    }

    @IsTest
    static void eachAnswerHasItsHttpStatus() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Integer> expected = new Map<String, Integer>{
                InboundGiftResult.ERROR_INVALID_REQUEST => 400,
                InboundGiftResult.ERROR_CONFLICT => 409,
                InboundGiftResult.ERROR_DONOR_NOT_FOUND => 422,
                InboundGiftResult.ERROR_FUND_NOT_FOUND => 422,
                InboundGiftResult.ERROR_APPEAL_NOT_FOUND => 422,
                InboundGiftResult.ERROR_NOT_SAVED => 422,
                InboundGiftResult.ERROR_INTERNAL => 500
            };
            for (String code : expected.keySet()) {
                Assert.areEqual(
                    expected.get(code),
                    InboundGiftResult.httpStatus(InboundGiftResult.rejected(code, 'x')),
                    code
                );
            }
            Id giftId = fakeId(Gift__c.SObjectType);
            Assert.areEqual(
                201,
                InboundGiftResult.httpStatus(
                    InboundGiftResult.recorded(InboundGiftResult.OUTCOME_CREATED, giftId, 'x')
                )
            );
            Assert.areEqual(
                200,
                InboundGiftResult.httpStatus(
                    InboundGiftResult.recorded(InboundGiftResult.OUTCOME_EXISTING, giftId, 'x')
                )
            );
            Assert.areEqual(500, InboundGiftResult.httpStatus(null));
        }
    }
}
