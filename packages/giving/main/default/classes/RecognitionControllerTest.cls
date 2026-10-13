/**
 * What the two record page panels call (features G-08 and G-09).
 */
@IsTest(testFor='ApexClass:TributeController, ApexClass:SoftCreditController')
private class RecognitionControllerTest {
    @IsTest
    static void listsTheCreditsOnAGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(true);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            SoftCreditController.SoftCreditPanel panel = SoftCreditController.getCredits(gift.Id);
            Test.stopTest();

            System.assertEquals(1, panel.credits.size(), 'The household credit is listed');
            System.assertEquals(true, panel.credits[0].isAutomatic, 'And marked as automatic');
            System.assertEquals('Luis Garcia', panel.credits[0].personName, 'By name');
        }
    }

    @IsTest
    static void addsAndRemovesACreditAPersonEntered() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(false);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            SoftCreditController.SoftCreditPanel afterAdd = SoftCreditController.addCredit(
                gift.Id,
                solicitor.Id,
                'Solicitor',
                null,
                500
            );
            SoftCreditController.SoftCreditPanel afterRemove = SoftCreditController.removeCredit(
                afterAdd.credits[0].recordId
            );
            Test.stopTest();

            System.assertEquals(1, afterAdd.credits.size(), 'The credit was added');
            System.assertEquals(0, afterRemove.credits.size(), 'And removed again');
        }
    }

    @IsTest
    static void refusesToRemoveAnAutomaticCredit() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(true);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
            Id automaticCreditId = RecognitionTestData.creditsFor(gift.Id)[0].Id;

            Test.startTest();
            Boolean refused = false;
            try {
                SoftCreditController.removeCredit(automaticCreditId);
            } catch (Exception expected) {
                refused = true;
            }
            Test.stopTest();

            System.assertEquals(true, refused, 'It would come straight back, so it is refused');
        }
    }

    @IsTest
    static void refusesACreditWithNoGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Boolean refused = false;
            try {
                SoftCreditController.getCredits(null);
            } catch (Exception expected) {
                refused = true;
            }
            Test.stopTest();

            System.assertEquals(true, refused, 'A soft credit belongs to a gift');
        }
    }

    @IsTest
    static void summarizesATributeAndMarksItSent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(false);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                'Rosa Garcia'
            );
            tribute.Notification_Recipient_Contact__c = ana.Id;
            insert tribute;

            Test.startTest();
            TributeController.TributeView before = TributeController.getTribute(gift.Id);
            TributeController.TributeView after = TributeController.markNotificationSent(
                tribute.Id
            );
            Test.stopTest();

            System.assertEquals('Rosa Garcia', before.honoreeName, 'The honoree is named');
            System.assertEquals('Ana Garcia', before.recipientName, 'And so is the person to tell');
            System.assertEquals(false, before.notificationSent, 'Nothing had gone out yet');
            System.assertEquals(true, after.notificationSent, 'Now it has');
            System.assertEquals(Date.today(), after.notificationSentDate, 'With the date it went');
        }
    }

    @IsTest
    static void saysWhyThereIsNothingToSendWhenNobodyIsNamedToNotify() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(false);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                'Rosa Garcia'
            );
            insert tribute;

            Test.startTest();
            TributeController.TributeView view = TributeController.getTribute(gift.Id);
            Test.stopTest();

            System.assertEquals('Rosa Garcia', view.honoreeName, 'The tribute is still shown');
            System.assertEquals(null, view.recipientName, 'There is nobody to write to');
            System.assertEquals(false, view.canMarkSent, 'So there is nothing to mark sent');
            System.assertEquals(
                Label.Giving_TributeNotification_NoRecipient,
                view.blockedReason,
                'And the panel says why rather than hiding the button without a word'
            );
        }
    }

    @IsTest
    static void allowsAMemorialToNotifyAnHonoreeWhoIsNotMarkedDeceased() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(false);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Account foundation = RecognitionTestData.organization('The Rosa Garcia Foundation');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                null
            );
            tribute.Honoree_Account__c = foundation.Id;
            tribute.Notification_Recipient_Account__c = foundation.Id;

            Test.startTest();
            Database.SaveResult result = Database.insert(tribute, false);
            Test.stopTest();

            System.assertEquals(
                true,
                result.isSuccess(),
                'An organization that is not marked deceased may be told about a gift honoring it'
            );
        }
    }

    @IsTest
    static void answersWithNothingWhenAGiftHasNoTribute() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            RecognitionTestData.setAutomaticHouseholdCredits(false);
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 100);

            Test.startTest();
            TributeController.TributeView view = TributeController.getTribute(gift.Id);
            Test.stopTest();

            System.assertEquals(null, view, 'Most gifts honor nobody, and that is not an error');
        }
    }

    @IsTest
    static void refusesToMarkATributeThatIsNotThere() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Boolean refused = false;
            try {
                TributeController.markNotificationSent(null);
            } catch (Exception expected) {
                refused = true;
            }
            Test.stopTest();

            System.assertEquals(true, refused, 'The panel is told what went wrong');
        }
    }
}
