/**
 * Linking an employer's gift to the employee's gift that earned it (feature G-10).
 */
@IsTest
private class MatchingGiftServiceTest {
    @IsTest
    static void linksBothSidesAndCreditsTheEmployee() {
        Setup data = setUp(true);

        Test.startTest();
        MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
        Test.stopTest();

        Map<Id, Gift__c> saved = new Map<Id, Gift__c>(
            [
                SELECT Id, Matched_Gift__c
                FROM Gift__c
                WHERE Id IN (:data.employeeGift.Id, :data.employerGift.Id)
            ]
        );
        System.assertEquals(
            data.employerGift.Id,
            saved.get(data.employeeGift.Id).Matched_Gift__c,
            'The employee gift names the match'
        );
        System.assertEquals(
            data.employeeGift.Id,
            saved.get(data.employerGift.Id).Matched_Gift__c,
            'And the employer gift names the gift it matched'
        );

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(data.employerGift.Id);
        System.assertEquals(1, credits.size(), 'The employee is recognized on the company gift');
        System.assertEquals(data.ana.Id, credits[0].Contact__c, 'Ana is the credited person');
        System.assertEquals(
            SoftCreditService.ROLE_MATCHED_DONOR,
            credits[0].Role__c,
            'The role says why'
        );
        System.assertEquals(500, credits[0].Amount__c, 'The credit is the match, whole');
    }

    @IsTest
    static void linksFromTheGiftRecordItself() {
        Setup data = setUp(true);

        Test.startTest();
        data.employerGift.Matched_Gift__c = data.employeeGift.Id;
        update data.employerGift;
        Test.stopTest();

        Gift__c employeeGift = [
            SELECT Matched_Gift__c
            FROM Gift__c
            WHERE Id = :data.employeeGift.Id
        ];
        System.assertEquals(
            data.employerGift.Id,
            employeeGift.Matched_Gift__c,
            'BarnCRM fills in the other side of the link'
        );
        System.assertEquals(
            1,
            RecognitionTestData.creditsFor(data.employerGift.Id).size(),
            'And credits the employee'
        );
    }

    @IsTest
    static void refusesAMatchThatIsNotFromAnOrganization() {
        Setup data = setUp(true);
        Contact other = RecognitionTestData.person('Tom', 'Alvarez', null);
        Gift__c otherPersonGift = RecognitionTestData.gift(other.Id, null, 100);

        Test.startTest();
        Boolean refused = false;
        try {
            MatchingGiftService.link(data.employeeGift.Id, otherPersonGift.Id);
        } catch (MatchingGiftService.MatchingGiftException expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'A match is money a company paid');
    }

    @IsTest
    static void refusesAnEmployeeGiftFromAnotherOrganization() {
        Setup data = setUp(true);
        Account other = RecognitionTestData.organization('Another Company');
        Gift__c otherOrgGift = RecognitionTestData.gift(null, other.Id, 100);

        Test.startTest();
        Boolean refused = false;
        try {
            MatchingGiftService.link(otherOrgGift.Id, data.employerGift.Id);
        } catch (MatchingGiftService.MatchingGiftException expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'The gift being matched comes from a person');
    }

    @IsTest
    static void refusesAMismatchedEmployer() {
        Setup data = setUp(true);
        Account elsewhere = RecognitionTestData.organization('Somewhere Else');
        Gift__c elsewhereGift = RecognitionTestData.gift(null, elsewhere.Id, 500);

        Test.startTest();
        Boolean refused = false;
        try {
            MatchingGiftService.link(data.employeeGift.Id, elsewhereGift.Id);
        } catch (MatchingGiftService.MatchingGiftException expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            refused,
            'The employer on the person and the company that paid must agree'
        );
    }

    @IsTest
    static void linksWhenNoEmployerIsRecorded() {
        Setup data = setUp(false);

        Test.startTest();
        MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
        Test.stopTest();

        Gift__c saved = [SELECT Matched_Gift__c FROM Gift__c WHERE Id = :data.employeeGift.Id];
        System.assertEquals(
            data.employerGift.Id,
            saved.Matched_Gift__c,
            'A blank employer is not an objection'
        );
    }

    @IsTest
    static void refusesAGiftMatchingItself() {
        Setup data = setUp(true);

        Test.startTest();
        Boolean refused = false;
        try {
            MatchingGiftService.link(data.employerGift.Id, data.employerGift.Id);
        } catch (MatchingGiftService.MatchingGiftException expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'A gift does not match itself');
    }

    @IsTest
    static void refusesAGiftAlreadyLinkedElsewhere() {
        Setup data = setUp(true);
        MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
        Gift__c secondEmployerGift = RecognitionTestData.gift(null, data.riverbend.Id, 500);

        Test.startTest();
        Boolean refused = false;
        try {
            MatchingGiftService.link(data.employeeGift.Id, secondEmployerGift.Id);
        } catch (MatchingGiftService.MatchingGiftException expected) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'One gift matches one gift');
    }

    @IsTest
    static void unlinkClearsBothSidesAndTheCredit() {
        Setup data = setUp(true);
        MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);

        Test.startTest();
        MatchingGiftService.unlink(data.employerGift.Id);
        Test.stopTest();

        for (Gift__c gift : [
            SELECT Matched_Gift__c
            FROM Gift__c
            WHERE Id IN (:data.employeeGift.Id, :data.employerGift.Id)
        ]) {
            System.assertEquals(null, gift.Matched_Gift__c, 'Neither gift names the other now');
        }
        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(data.employerGift.Id).size(),
            'The credit the link created goes with it'
        );
    }

    @IsTest
    static void linkingTwiceCreditsOnce() {
        Setup data = setUp(true);

        Test.startTest();
        MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
        MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
        Test.stopTest();

        System.assertEquals(
            1,
            RecognitionTestData.creditsFor(data.employerGift.Id).size(),
            'The same link recognizes the same person once'
        );
    }

    @IsTest
    static void refusesAMatchOnARefundedGift() {
        Setup data = setUp(true);
        data.employeeGift.Status__c = SoftCreditService.STATUS_REFUNDED;
        update data.employeeGift;

        Test.startTest();
        String message = null;
        try {
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
        } catch (MatchingGiftService.MatchingGiftException refused) {
            message = refused.getMessage();
        }
        Test.stopTest();

        System.assertEquals(
            Label.Giving_MatchingGift_GiftNotReceived,
            message,
            'A refunded gift is not half of a matching pair'
        );
        Gift__c employerGift = [
            SELECT Matched_Gift__c
            FROM Gift__c
            WHERE Id = :data.employerGift.Id
        ];
        System.assertEquals(null, employerGift.Matched_Gift__c, 'And no link was written');
    }

    @IsTest
    static void refusesAMatchOnAWrittenOffEmployerGift() {
        Setup data = setUp(true);
        data.employerGift.Status__c = SoftCreditService.STATUS_WRITTEN_OFF;
        update data.employerGift;

        Test.startTest();
        data.employerGift.Matched_Gift__c = data.employeeGift.Id;
        Database.SaveResult result = Database.update(data.employerGift, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'The link is refused on the record itself');
        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(data.employerGift.Id).size(),
            'And no matched donor credit was created'
        );
    }

    @IsTest
    static void createsOneCreditWhenBothSidesOfThePairAreSavedTogether() {
        Setup data = setUp(true);

        Test.startTest();
        data.employerGift.Matched_Gift__c = data.employeeGift.Id;
        update data.employerGift;
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(data.employerGift.Id);
        System.assertEquals(
            1,
            credits.size(),
            'Writing the other side of the link re-enters the handler, and must not credit twice'
        );
    }

    @IsTest
    static void linksTwoHundredPairsInOneUpdate() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        GivingTestDataFactory.ensureDefaultFund();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Account riverbend = RecognitionTestData.organization('Riverbend Manufacturing');
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < 200; index++) {
            people.add(
                new Contact(
                    FirstName = 'Giver',
                    LastName = 'Number ' + index,
                    AccountId = garcias.Id,
                    Employer__c = riverbend.Id
                )
            );
        }
        insert people;
        List<Gift__c> employeeGifts = new List<Gift__c>();
        List<Gift__c> employerGifts = new List<Gift__c>();
        for (Contact person : people) {
            employeeGifts.add(RecognitionTestData.newGift(person.Id, null, 100));
            employerGifts.add(RecognitionTestData.newGift(null, riverbend.Id, 100));
        }
        insert employeeGifts;
        insert employerGifts;
        for (Integer index = 0; index < 200; index++) {
            employerGifts[index].Matched_Gift__c = employeeGifts[index].Id;
        }

        Test.startTest();
        update employerGifts;
        Test.stopTest();

        System.assertEquals(
            200,
            [
                SELECT COUNT()
                FROM Soft_Credit__c
                WHERE Role__c = :SoftCreditService.ROLE_MATCHED_DONOR
            ],
            'One matched donor credit per pair, from one query rather than two hundred'
        );
    }

    private class Setup {
        Contact ana;
        Account riverbend;
        Gift__c employeeGift;
        Gift__c employerGift;
    }

    private static Setup setUp(Boolean recordEmployer) {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Setup data = new Setup();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        data.riverbend = RecognitionTestData.organization('Riverbend Manufacturing');
        data.ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        if (recordEmployer) {
            data.ana.Employer__c = data.riverbend.Id;
            update data.ana;
        }
        data.employeeGift = RecognitionTestData.gift(data.ana.Id, null, 500);
        data.employerGift = RecognitionTestData.gift(null, data.riverbend.Id, 500);
        return data;
    }
}
