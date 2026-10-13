/**
 * An appeal hierarchy is shallow and it never loops (R-AP2).
 */
@IsTest
private class AppealTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    @IsTest
    static void anAppealCannotBeItsOwnParent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Appeal__c appeal = GivingTestDataFactory.buildAppeal('Spring appeal');
            insert appeal;

            String message;
            Test.startTest();
            try {
                appeal.Parent_Appeal__c = appeal.Id;
                update appeal;
            } catch (DmlException selfParent) {
                message = selfParent.getDmlMessage(0);
            }
            Test.stopTest();

            // Three things refuse this, and which one answers first is the platform's choice: its own
            // check on a lookup to the same object ("Hierarchy Constraint Violation"), which in an org
            // runs before anything the package ships, then the Parent_Appeal_Not_Self rule, then the
            // loop check in the trigger. The requirement is that the save is refused and nothing moves.
            Assert.isNotNull(message, 'An appeal above itself is refused.');
            Assert.isTrue(
                message.contains('own parent') ||
                    message.contains('loop') ||
                    message.contains('Hierarchy'),
                'Refused as a hierarchy that points at itself, not for some other reason: ' +
                message
            );
            Assert.isNull(
                [SELECT Parent_Appeal__c FROM Appeal__c WHERE Id = :appeal.Id].Parent_Appeal__c,
                'And the appeal is still at the top of its own hierarchy.'
            );
        }
    }

    @IsTest
    static void aLongerLoopIsRefused() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Appeal__c campaign = GivingTestDataFactory.buildAppeal('Capital campaign');
            insert campaign;
            Appeal__c gala = GivingTestDataFactory.buildAppeal('Gala');
            gala.Parent_Appeal__c = campaign.Id;
            insert gala;

            String message = '';
            Test.startTest();
            try {
                campaign.Parent_Appeal__c = gala.Id;
                update campaign;
            } catch (DmlException loopError) {
                message = loopError.getDmlMessage(0);
            }
            Test.stopTest();

            System.assert(
                message.contains('loop'),
                'A gala cannot be the parent of the campaign it sits inside: ' + message
            );
        }
    }

    @IsTest
    static void aRealHierarchySaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Appeal__c campaign = GivingTestDataFactory.buildAppeal('Capital campaign');
            campaign.Goal__c = 250000;
            campaign.Cost__c = 12000;
            insert campaign;

            Test.startTest();
            Appeal__c calls = GivingTestDataFactory.buildAppeal('Major donor calls');
            calls.Parent_Appeal__c = campaign.Id;
            insert calls;
            Test.stopTest();

            System.assertEquals(
                campaign.Id,
                [SELECT Parent_Appeal__c FROM Appeal__c WHERE Id = :calls.Id].Parent_Appeal__c,
                'A gala inside a campaign is exactly what the hierarchy is for.'
            );
        }
    }

    @IsTest
    static void twoHundredAppealsSaveInOneGo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Appeal__c> appeals = new List<Appeal__c>();
            for (Integer i = 0; i < 200; i++) {
                appeals.add(GivingTestDataFactory.buildAppeal('Appeal ' + i));
            }

            Test.startTest();
            insert appeals;
            Test.stopTest();

            System.assertEquals(200, [SELECT COUNT() FROM Appeal__c], 'Two hundred in one save.');
        }
    }
}
