/**
 * Tribute rules and the notification record (feature G-09).
 */
@IsTest
private class TributeServiceTest {
    @IsTest
    static void savesAMemorialWithATypedHonoreeName() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);

            Test.startTest();
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                'Rosa Garcia'
            );
            insert tribute;
            Test.stopTest();

            Gift__c saved = [SELECT Tribute__c FROM Gift__c WHERE Id = :gift.Id];
            System.assertEquals(
                tribute.Id,
                saved.Tribute__c,
                'The gift carries a mirror of the tribute so list views see it'
            );
        }
    }

    @IsTest
    static void refusesATributeWithNobodyHonored() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Tribute__c(Gift__c = gift.Id, Type__c = TributeService.TYPE_IN_HONOR_OF),
                false
            );
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'A tribute honors someone');
        }
    }

    @IsTest
    static void refusesASecondTributeOnOneGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            insert RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_HONOR_OF,
                'Rosa Garcia'
            );

            Test.startTest();
            Database.SaveResult result = Database.insert(
                RecognitionTestData.tribute(
                    gift.Id,
                    TributeService.TYPE_IN_HONOR_OF,
                    'Luis Garcia'
                ),
                false
            );
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'One gift, one tribute');
        }
    }

    @IsTest
    static void refusesAMemorialThatWouldNotifyTheHonoree() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            Contact rosa = RecognitionTestData.person('Rosa', 'Garcia', null);
            rosa.Deceased__c = true;
            update rosa;

            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                null
            );
            tribute.Honoree_Contact__c = rosa.Id;
            tribute.Notification_Recipient_Contact__c = rosa.Id;

            Test.startTest();
            Database.SaveResult result = Database.insert(tribute, false);
            Test.stopTest();

            System.assertEquals(
                false,
                result.isSuccess(),
                'A family is told about a memorial, never the person it remembers'
            );
        }
    }

    @IsTest
    static void allowsAMemorialNotifiedToTheFamily() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            Contact rosa = RecognitionTestData.person('Rosa', 'Garcia', null);
            rosa.Deceased__c = true;
            update rosa;
            Contact ana = [SELECT Id FROM Contact WHERE FirstName = 'Ana' LIMIT 1];

            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                null
            );
            tribute.Honoree_Contact__c = rosa.Id;
            tribute.Notification_Recipient_Contact__c = ana.Id;

            Test.startTest();
            insert tribute;
            Test.stopTest();

            System.assertNotEquals(null, tribute.Id, 'The family may be notified');
        }
    }

    @IsTest
    static void marksTheNotificationSentAndStampsTheDate() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_MEMORY_OF,
                'Rosa Garcia'
            );
            tribute.Notification_Recipient_Name__c = 'The Garcia family, 14 Mill Lane';
            insert tribute;

            Test.startTest();
            TributeService.markNotificationSent(new Set<Id>{ tribute.Id });
            Test.stopTest();

            Tribute__c saved = [
                SELECT Notification_Sent__c, Notification_Sent_Date__c
                FROM Tribute__c
                WHERE Id = :tribute.Id
            ];
            System.assertEquals(true, saved.Notification_Sent__c, 'The notification has gone out');
            System.assertEquals(
                Date.today(),
                saved.Notification_Sent_Date__c,
                'And the date is kept'
            );
        }
    }

    @IsTest
    static void keepsTheFirstSentDateWhenMarkedAgain() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_HONOR_OF,
                'Rosa Garcia'
            );
            tribute.Notification_Sent__c = true;
            tribute.Notification_Sent_Date__c = Date.today().addDays(-10);
            insert tribute;

            Test.startTest();
            TributeService.markNotificationSent(new Set<Id>{ tribute.Id });
            Test.stopTest();

            Tribute__c saved = [
                SELECT Notification_Sent_Date__c
                FROM Tribute__c
                WHERE Id = :tribute.Id
            ];
            System.assertEquals(
                Date.today().addDays(-10),
                saved.Notification_Sent_Date__c,
                'The record of what the organization did is not rewritten'
            );
        }
    }

    @IsTest
    static void stampsTheDateWhenTheBoxIsTickedOnTheRecord() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_HONOR_OF,
                'Rosa Garcia'
            );
            insert tribute;

            Test.startTest();
            // The box alone, as a record page saves it. The tribute in memory still carries its gift,
            // and a master-detail field that cannot be reparented is not editable, so a save that
            // sends it is refused in user mode before the box is ever looked at.
            update new Tribute__c(Id = tribute.Id, Notification_Sent__c = true);
            Test.stopTest();

            Tribute__c saved = [
                SELECT Notification_Sent_Date__c
                FROM Tribute__c
                WHERE Id = :tribute.Id
            ];
            System.assertEquals(
                Date.today(),
                saved.Notification_Sent_Date__c,
                'The date follows the box'
            );
        }
    }

    @IsTest
    static void clearsTheGiftMirrorWhenTheTributeIsDeleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c gift = giftFromAna(100);
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TributeService.TYPE_IN_HONOR_OF,
                'Rosa Garcia'
            );
            insert tribute;

            Test.startTest();
            delete tribute;
            Test.stopTest();

            Gift__c saved = [SELECT Tribute__c FROM Gift__c WHERE Id = :gift.Id];
            System.assertEquals(null, saved.Tribute__c, 'The mirror goes when the tribute goes');
        }
    }

    private static Gift__c giftFromAna(Decimal amount) {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        return RecognitionTestData.gift(ana.Id, null, amount);
    }
}
