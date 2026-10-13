/**
 * The standard email being kept in step with the address a person chose (R-C6).
 */
@IsTest
private class PreferredEmailServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String PERSONAL = 'maria.garcia@example.org';
    private static final String WORK = 'mgarcia@springfieldfoodbank.example.org';

    private static Contact mariaWithThreeAddresses() {
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        maria.Personal_Email__c = PERSONAL;
        maria.Work_Email__c = WORK;
        return maria;
    }

    @IsTest
    static void choosingAnAddressFillsTheStandardEmailOnInsert() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithThreeAddresses();
            maria.Preferred_Email__c = 'Work';

            Test.startTest();
            insert maria;
            Test.stopTest();

            Assert.areEqual(
                WORK,
                [SELECT Email FROM Contact WHERE Id = :maria.Id].Email,
                'The work address was copied into the standard email'
            );
        }
    }

    @IsTest
    static void choosingAnAddressFillsTheStandardEmailOnUpdate() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithThreeAddresses();
            insert maria;

            Test.startTest();
            update new Contact(Id = maria.Id, Preferred_Email__c = 'Personal');
            Test.stopTest();

            Assert.areEqual(
                PERSONAL,
                [SELECT Email FROM Contact WHERE Id = :maria.Id].Email,
                'The personal address was copied in on the save that made the choice'
            );
        }
    }

    @IsTest
    static void changingTheChoiceCopiesTheOtherAddress() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithThreeAddresses();
            maria.Preferred_Email__c = 'Work';
            insert maria;

            Test.startTest();
            update new Contact(Id = maria.Id, Preferred_Email__c = 'Personal');
            Test.stopTest();

            Assert.areEqual(
                PERSONAL,
                [SELECT Email FROM Contact WHERE Id = :maria.Id].Email,
                'Maria changed jobs and only the choice moved'
            );
        }
    }

    @IsTest
    static void makingNoChoiceLeavesTheStandardEmailAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithThreeAddresses();
            maria.Email = 'whatever.maria.typed@example.org';

            Test.startTest();
            insert maria;
            update new Contact(Id = maria.Id, Work_Email__c = 'another@example.org');
            Test.stopTest();

            Assert.areEqual(
                'whatever.maria.typed@example.org',
                [SELECT Email FROM Contact WHERE Id = :maria.Id].Email,
                'An org that has not chosen an address sees no change at all'
            );
        }
    }

    @IsTest
    static void choosingAnEmptyAddressRefusesTheSave() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithThreeAddresses();
            maria.Email = 'whatever.maria.typed@example.org';
            insert maria;
            String message;

            Test.startTest();
            try {
                update new Contact(Id = maria.Id, Preferred_Email__c = 'Alternate');
            } catch (DmlException thrown) {
                message = thrown.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.areEqual(
                String.format(Label.Core_Emails_PreferredEmpty, new List<String>{ 'Alternate' }),
                message,
                'The save was refused with the message that names the empty address'
            );
            Assert.areEqual(
                'whatever.maria.typed@example.org',
                [SELECT Email FROM Contact WHERE Id = :maria.Id].Email,
                'The standard email was not blanked'
            );
        }
    }

    @IsTest
    static void twoHundredPeopleAreCopiedInOneSave() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Emailer');
            for (Integer i = 0; i < people.size(); i++) {
                people[i].Work_Email__c = 'person' + i + '@example.org';
                people[i].Preferred_Email__c = 'Work';
            }

            Test.startTest();
            insert people;
            Test.stopTest();

            Integer copied = 0;
            for (Contact person : [
                SELECT Email, Work_Email__c
                FROM Contact
                WHERE Id IN :people
            ]) {
                if (person.Email == person.Work_Email__c) {
                    copied++;
                }
            }
            Assert.areEqual(200, copied, 'Every person in the batch carries their work address');
        }
    }

    @IsTest
    static void anOrgWithoutThePersonEmailFieldSavesAnAccountUntouched() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            // Both overrides on, so the account half runs as far as it can on an org shape that
            // has no person email field to write: it must leave the save alone rather than fail.
            // An org that has the field is an org with person accounts, where declaring the
            // household a person would make the test write a person field onto a business
            // account; there the household is left as what it is, and the account half must leave
            // it alone for that reason instead (ADR-0013).
            if (!Schema.SObjectType.Account.fields.getMap().containsKey('PersonEmail')) {
                HouseholdService.personAccountOverride = true;
                PersonRecordSelector.personRecordOverride = true;
            }
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            household.Personal_Email__c = PERSONAL;
            household.Preferred_Email__c = 'Personal';

            Test.startTest();
            insert household;
            Test.stopTest();

            Assert.areEqual(
                PERSONAL,
                [SELECT Personal_Email__c FROM Account WHERE Id = :household.Id].Personal_Email__c,
                'The account saved with its addresses and nothing was refused'
            );
        }
    }
}
