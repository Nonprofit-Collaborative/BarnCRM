/**
 * The Posting card on a gift's page (G-20, ADR-0053): what it says about a gift, and the unpost
 * it carries for Jen.
 */
@IsTest
private class GiftPostingControllerTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    /** The default fund and the close date are an administrator's, set outside Jen's work. */
    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
    }

    private static Gift__c gift(Decimal amount, String status, Date giftDate) {
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, amount);
        gift.Status__c = status;
        gift.Gift_Date__c = giftDate;
        insert gift;
        return gift;
    }

    @IsTest
    static void showsWhoPostedAndLetsJenUnpost() {
        User jen = jen();
        System.runAs(jen) {
            Gift__c gift = gift(250, 'Received', Date.today());
            GiftPostingService.markPosted(new Set<Id>{ gift.Id });

            GiftPostingController.PostingState posted = GiftPostingController.getState(gift.Id);
            Assert.isTrue(posted.posted);
            Assert.isTrue(posted.inBooks);
            Assert.areEqual(
                [SELECT Name FROM User WHERE Id = :jen.Id].Name,
                posted.postedBy,
                'Names who posted it'
            );
            Assert.isNotNull(posted.postedAt);
            Assert.isTrue(posted.canUnpost, 'Jen holds Post Gifts');
            Assert.isFalse(posted.inClosedPeriod);

            GiftPostingController.PostingState after = GiftPostingController.unpost(
                gift.Id,
                'Wrong fund'
            );
            Assert.isFalse(after.posted, 'Unposted');
            Assert.isFalse(after.canUnpost, 'Nothing left to unpost');
        }
    }

    @IsTest
    static void saysWhenAGiftIsInAClosedPeriod() {
        User jen = jen();
        // Taken once: Date.today() differs between the test user and Jen near midnight when
        // their time zones differ.
        Date closeDate = Date.today().addDays(-1);
        Gift__c gift;
        System.runAs(jen) {
            gift = gift(250, 'Received', closeDate.addDays(-9));
        }
        GivingTestDataFactory.closeBooksThrough(closeDate);
        System.runAs(jen) {
            GiftPostingController.PostingState state = GiftPostingController.getState(gift.Id);

            Assert.isFalse(state.posted);
            Assert.isTrue(state.inClosedPeriod, 'Locked by the close date');
            Assert.areEqual(closeDate, state.closedThrough);
        }
    }

    @IsTest
    static void aPendingGiftIsNotInTheBooks() {
        User jen = jen();
        Gift__c gift;
        System.runAs(jen) {
            gift = gift(75, 'Pending', Date.today().addDays(-10));
        }
        GivingTestDataFactory.closeBooksThrough(Date.today().addDays(-1));
        System.runAs(jen) {
            GiftPostingController.PostingState state = GiftPostingController.getState(gift.Id);

            Assert.isFalse(state.inBooks);
            Assert.isFalse(state.inClosedPeriod, 'A Pending gift stays editable');
        }
    }

    @IsTest
    static void staffSeeTheCardWithoutUnpost() {
        System.runAs(david()) {
            Gift__c gift = gift(250, 'Received', Date.today());
            GiftPostingService.postPermission = true;
            GiftPostingService.markPosted(new Set<Id>{ gift.Id });
            GiftPostingService.postPermission = null;

            GiftPostingController.PostingState state = GiftPostingController.getState(gift.Id);
            Assert.isTrue(state.posted);
            Assert.isFalse(state.canUnpost, 'David does not hold Post Gifts');
            try {
                GiftPostingController.unpost(gift.Id, 'Typo');
                Assert.fail('Refused');
            } catch (AuraHandledException refused) {
                Assert.areEqual(Label.Giving_Posting_NoPermission, refused.getMessage());
            }
        }
    }
}
