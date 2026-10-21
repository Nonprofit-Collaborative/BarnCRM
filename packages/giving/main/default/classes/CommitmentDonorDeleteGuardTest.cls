/**
 * The donor of an open commitment is not deleted (R-CM1).
 *
 * The platform clears a commitment's Donor Contact or Donor Account when the record it names is
 * deleted, and a commitment with no donor can never be saved again, not even by its own totals,
 * which then fail and retry in the Rollup Queue. So a person or organization that is the donor of
 * an Active or Paused commitment, or the account of a person who is, is refused. A merge still
 * works, and erasing a person, which anonymizes them in place, is untouched.
 */
@IsTest(testFor='ApexClass:GiftDonorDeleteGuardHandler, ApexClass:CommitmentService')
private class CommitmentDonorDeleteGuardTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
            GivingTestDataFactory.insertHouseholdContact('The Okafor Family', 'Ben', 'Okafor');
        }
    }

    private static Contact ana() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    private static Contact ben() {
        return [SELECT Id FROM Contact WHERE LastName = 'Okafor' LIMIT 1];
    }

    private static Commitment__c pledgeFrom(Id contactId, Id accountId, String status) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = status,
            Donor_Contact__c = contactId,
            Donor_Account__c = accountId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
        insert pledge;
        return pledge;
    }

    private static User eraser() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Admin', 'BarnCRM_Erase_People' }
        );
    }

    private static String deleteRefusal(SObject record) {
        try {
            delete record;
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    @IsTest
    static void theDonorOfAnActivePledgeIsNotDeleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Commitment__c pledge = pledgeFrom(ana().Id, null, 'Active');

            Test.startTest();
            String refusal = deleteRefusal(new Contact(Id = ana().Id));
            Test.stopTest();

            Assert.areEqual(Label.Giving_Commitment_DonorDeleteBlocked, refusal);
            Assert.areEqual(
                ana().Id,
                [SELECT Donor_Contact__c FROM Commitment__c WHERE Id = :pledge.Id].Donor_Contact__c,
                'The pledge still names Ana.'
            );
        }
    }

    @IsTest
    static void theHouseholdOfAPausedPledgesDonorIsNotDeleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // Deleting the household would delete Ana with it, and no Contact trigger runs.
            pledgeFrom(ana().Id, null, 'Paused');

            Test.startTest();
            String refusal = deleteRefusal(new Account(Id = ana().AccountId));
            Test.stopTest();

            Assert.areEqual(Label.Giving_Commitment_DonorDeleteBlocked, refusal);
        }
    }

    @IsTest
    static void theOrganizationDonorOfAnActivePledgeIsNotDeleted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account riverside = GivingTestDataFactory.insertOrganization('Riverside Foundation');
            pledgeFrom(null, riverside.Id, 'Active');

            Test.startTest();
            String refusal = deleteRefusal(riverside);
            Test.stopTest();

            Assert.areEqual(Label.Giving_Commitment_DonorDeleteBlocked, refusal);
        }
    }

    /** Only the donor with an open pledge is refused, in a delete of two hundred people. */
    @IsTest
    static void aDonorWhosePledgeIsOverIsDeletedWithTheRest() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 199; i++) {
                people.add(new Contact(FirstName = 'Donor' + i, LastName = 'Nobody'));
            }
            insert people;
            pledgeFrom(people[0].Id, null, 'Cancelled');
            pledgeFrom(people[1].Id, null, 'Completed');
            pledgeFrom(ana().Id, null, 'Active');
            List<Contact> everyone = new List<Contact>(people);
            everyone.add(new Contact(Id = ana().Id));

            Test.startTest();
            List<Database.DeleteResult> results = Database.delete(everyone, false);
            Test.stopTest();

            Integer refused = 0;
            for (Database.DeleteResult result : results) {
                if (!result.isSuccess()) {
                    refused++;
                    Assert.areEqual(ana().Id, result.getId(), 'Only Ana is refused.');
                }
            }
            Assert.areEqual(1, refused, 'A cancelled or completed pledge does not hold anyone.');
        }
    }

    @IsTest
    static void mergingTheDonorOfAnActivePledgeStillWorks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Commitment__c pledge = pledgeFrom(ana().Id, null, 'Active');
            Contact ben = ben();

            Test.startTest();
            Database.MergeResult result = Database.merge(ben, ana().Id, false);
            Test.stopTest();

            Assert.isTrue(result.isSuccess(), 'A merge is not a delete: ' + result.getErrors());
            Assert.areEqual(
                ben.Id,
                [SELECT Donor_Contact__c FROM Commitment__c WHERE Id = :pledge.Id].Donor_Contact__c,
                'The pledge moved to Ben.'
            );
        }
    }

    /** Erasing a person anonymizes them in place, so their open pledge stays credited to them. */
    @IsTest
    static void erasingTheDonorOfAnActivePledgeStillWorks() {
        System.runAs(eraser()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact jordan = GivingTestDataFactory.insertHouseholdContact(
                'The Lee Family',
                'Jordan',
                'Lee'
            );
            Commitment__c pledge = pledgeFrom(jordan.Id, null, 'Active');

            Test.startTest();
            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            Assert.areNotEqual(
                'Lee',
                [SELECT LastName FROM Contact WHERE Id = :jordan.Id].LastName,
                'The erasure went through: the person is anonymized, not deleted.'
            );
            Assert.areEqual(
                jordan.Id,
                [SELECT Donor_Contact__c FROM Commitment__c WHERE Id = :pledge.Id].Donor_Contact__c,
                'The pledge is still credited to the anonymous record.'
            );
        }
    }
}
