/**
 * The standard phone being kept in step with the number a person chose (R-C6a).
 */
@IsTest(testFor='ApexClass:PreferredPhoneService')
private class PreferredPhoneServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String HOME = '503-555-0101';
    private static final String MOBILE = '503-555-0102';
    private static final String PHONE_ROW = 'Preferred_Phone_Contact';

    private static Contact mariaWithTwoNumbers() {
        Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        maria.HomePhone = HOME;
        maria.MobilePhone = MOBILE;
        return maria;
    }

    private static String phoneOf(Id contactId) {
        return [SELECT Phone FROM Contact WHERE Id = :contactId].Phone;
    }

    @IsTest
    static void choosingANumberFillsThePhoneOnInsert() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Preferred_Phone__c = 'Mobile';

            Test.startTest();
            insert maria;
            Test.stopTest();

            Assert.areEqual(MOBILE, phoneOf(maria.Id), 'The mobile number was copied in');
        }
    }

    @IsTest
    static void choosingWorkCopiesTheWorkPhone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Work_Phone__c = '503-555-0104';
            maria.Preferred_Phone__c = 'Work';

            Test.startTest();
            insert maria;
            Test.stopTest();

            Assert.areEqual('503-555-0104', phoneOf(maria.Id), 'The work number was copied in');
        }
    }

    @IsTest
    static void changingTheChoiceCopiesTheOtherNumber() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Preferred_Phone__c = 'Mobile';
            insert maria;

            Test.startTest();
            update new Contact(Id = maria.Id, Preferred_Phone__c = 'Home');
            Test.stopTest();

            Assert.areEqual(HOME, phoneOf(maria.Id), 'Only the choice moved');
        }
    }

    @IsTest
    static void editingTheChosenNumberUpdatesThePhone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Preferred_Phone__c = 'Home';
            insert maria;

            Test.startTest();
            update new Contact(Id = maria.Id, HomePhone = '503-555-0199');
            Test.stopTest();

            Assert.areEqual('503-555-0199', phoneOf(maria.Id), 'The new home number followed');
        }
    }

    @IsTest
    static void makingNoChoiceLeavesThePhoneAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Phone = '503-555-0000';

            Test.startTest();
            insert maria;
            update new Contact(Id = maria.Id, MobilePhone = '503-555-0103');
            Test.stopTest();

            Assert.areEqual('503-555-0000', phoneOf(maria.Id), 'No choice, no change');
        }
    }

    @IsTest
    static void clearingTheChoiceKeepsTheLastCopiedNumber() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Preferred_Phone__c = 'Mobile';
            insert maria;

            Test.startTest();
            update new Contact(Id = maria.Id, Preferred_Phone__c = null);
            Test.stopTest();

            Assert.areEqual(MOBILE, phoneOf(maria.Id), 'Clearing stops the copying only');
        }
    }

    @IsTest
    static void choosingAnEmptyNumberRefusesTheSave() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Phone = '503-555-0000';
            insert maria;
            String message;

            Test.startTest();
            try {
                update new Contact(Id = maria.Id, Preferred_Phone__c = 'Other');
            } catch (DmlException thrown) {
                message = thrown.getDmlMessage(0);
            }
            Test.stopTest();

            Assert.areEqual(
                String.format(Label.Core_Phones_PreferredEmpty, new List<String>{ 'Other' }),
                message,
                'The save was refused with the message that names the empty number'
            );
            Assert.areEqual('503-555-0000', phoneOf(maria.Id), 'The phone was not blanked');
        }
    }

    @IsTest
    static void emptyingTheChosenSourceRefusesTheSave() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = mariaWithTwoNumbers();
            maria.Preferred_Phone__c = 'Mobile';
            insert maria;
            Boolean refused = false;

            Test.startTest();
            try {
                update new Contact(Id = maria.Id, MobilePhone = null);
            } catch (DmlException thrown) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'Emptying the chosen number is refused');
            Assert.areEqual(MOBILE, phoneOf(maria.Id), 'The phone still holds the number');
        }
    }

    private static List<Contact> manyWhoPreferMobile(Integer count) {
        List<Contact> people = HouseholdTestDataFactory.manyContacts(count, 'Phoner');
        for (Integer i = 0; i < people.size(); i++) {
            people[i].MobilePhone = '503-555-' + String.valueOf(1000 + i);
            people[i].Preferred_Phone__c = 'Mobile';
        }
        return people;
    }

    private static Integer copied(List<Contact> people) {
        Integer count = 0;
        for (Contact person : [SELECT Phone, MobilePhone FROM Contact WHERE Id IN :people]) {
            if (person.Phone == person.MobilePhone) {
                count++;
            }
        }
        return count;
    }

    @IsTest
    static void twoHundredFiftyOnePeopleAreCopiedInOneSave() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = manyWhoPreferMobile(251);

            // Generated names and numbers look alike to the org's duplicate rules, which are not
            // under test here, so the save is allowed through them.
            Database.DMLOptions options = new Database.DMLOptions();
            options.duplicateRuleHeader.allowSave = true;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(people, options);
            Test.stopTest();

            for (Database.SaveResult result : results) {
                Assert.isTrue(result.isSuccess(), 'Every person was saved');
            }
            Assert.areEqual(251, copied(people), 'Every person carries their mobile number');
        }
    }

    @IsTest
    static void switchingThePreferredPhoneRowOffStopsTheCopy() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            TestDataFactory.insertAutomationSettings(
                new Map<String, Boolean>{ PHONE_ROW => false }
            );
            List<Contact> people = manyWhoPreferMobile(5);

            Test.startTest();
            insert people;
            update people;
            Test.stopTest();

            Assert.areEqual(0, copied(people), 'With its own row off nothing is copied');
        }
    }
}
