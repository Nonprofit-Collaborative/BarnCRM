/**
 * The rules a soft credit is saved by (feature G-08).
 */
@IsTest
private class SoftCreditTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    @IsTest
    static void refusesACreditWithNobodyCredited() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Soft_Credit__c(Gift__c = gift.Id, Role__c = 'Solicitor', Amount__c = 500),
                false
            );
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'A credit recognizes somebody');
        }
    }

    @IsTest
    static void refusesACreditWithTwoPartiesCredited() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Account riverbend = RecognitionTestData.organization('Riverbend Manufacturing');
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Soft_Credit__c(
                    Gift__c = gift.Id,
                    Contact__c = ana.Id,
                    Account__c = riverbend.Id,
                    Role__c = 'Solicitor',
                    Amount__c = 500
                ),
                false
            );
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'One party, not two');
        }
    }

    @IsTest
    static void fillsInThePercentFromTheAmount() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            Soft_Credit__c credit = RecognitionTestData.manualCredit(
                gift.Id,
                solicitor.Id,
                'Solicitor',
                250
            );
            Test.stopTest();

            Soft_Credit__c saved = [
                SELECT Amount__c, Percent__c
                FROM Soft_Credit__c
                WHERE Id = :credit.Id
            ];
            System.assertEquals(50, saved.Percent__c, 'Half the gift is fifty percent of it');
        }
    }

    @IsTest
    static void fillsInTheAmountFromThePercent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            Soft_Credit__c credit = new Soft_Credit__c(
                Gift__c = gift.Id,
                Contact__c = solicitor.Id,
                Role__c = 'Solicitor',
                Percent__c = 50
            );
            insert credit;
            Test.stopTest();

            Soft_Credit__c saved = [SELECT Amount__c FROM Soft_Credit__c WHERE Id = :credit.Id];
            System.assertEquals(250, saved.Amount__c, 'Fifty percent of the gift is half of it');
        }
    }

    @IsTest
    static void refusesAnAmountAndAPercentThatDisagree() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Soft_Credit__c(
                    Gift__c = gift.Id,
                    Contact__c = solicitor.Id,
                    Role__c = 'Solicitor',
                    Amount__c = 250,
                    Percent__c = 100
                ),
                false
            );
            Test.stopTest();

            System.assertEquals(
                false,
                result.isSuccess(),
                'One number or the other, not two that differ'
            );
        }
    }

    @IsTest
    static void refusesRoleOtherWithoutWording() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account garcias = RecognitionTestData.household('The Garcia Family');
            Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
            Contact helper = RecognitionTestData.person('Tom', 'Alvarez', null);
            Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

            Test.startTest();
            Database.SaveResult result = Database.insert(
                new Soft_Credit__c(
                    Gift__c = gift.Id,
                    Contact__c = helper.Id,
                    Role__c = 'Other',
                    Amount__c = 500
                ),
                false
            );
            Test.stopTest();

            System.assertEquals(
                false,
                result.isSuccess(),
                'Role Other needs the organization\'s wording'
            );
        }
    }
}
