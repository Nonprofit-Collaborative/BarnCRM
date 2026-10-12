/**
 * The Record Inbound Gift Flow action (X-03): many gifts in, one answer each, in order, and a
 * refused gift is an answer rather than a failure of the flow.
 */
@IsTest
private class InboundGiftActionTest {
    @IsTest
    static void eachGiftIsAnsweredInTheOrderSent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new Fund__c(Name = 'General Fund', Active__c = true, Is_Default__c = true);
            insert new Contact(
                FirstName = 'Luis',
                LastName = 'Garcia',
                Email = 'luis.flow@example.org'
            );
            InboundGift known = new InboundGift();
            known.externalId = 'flow:ok';
            known.amount = 20;
            known.paymentMethod = 'ACH';
            known.donorEmail = 'luis.flow@example.org';
            InboundGift stranger = known.clone();
            stranger.externalId = 'flow:stranger';
            stranger.donorEmail = 'nobody.flow@example.org';

            Test.startTest();
            List<InboundGiftResult> results = InboundGiftAction.record(
                new List<InboundGift>{ known, stranger }
            );
            Test.stopTest();

            Assert.areEqual(2, results.size());
            Assert.areEqual('created', results[0].outcome, results[0].message);
            Assert.isNotNull(results[0].giftId);
            Assert.areEqual('rejected', results[1].outcome);
            Assert.areEqual('donor_not_found', results[1].errorCode);
            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c]);
        }
    }
}
