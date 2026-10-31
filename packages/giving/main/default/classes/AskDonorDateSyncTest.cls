/**
 * Open asks set the donor's Next Ask Date (canonical model R-SO9): the earliest open Target Date
 * is written, a closed or deleted last ask clears the date it had set, and a date somebody
 * entered by hand is kept.
 */
@IsTest(testFor='ApexClass:AskDonorDateSync, ApexClass:AskNextAskDateHandler')
private class AskDonorDateSyncTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith('Giving_Staff');
    }

    private static User staff() {
        return TestUsers.adminWith('Giving_Staff');
    }

    private static Contact person(Date nextAsk) {
        Contact donor = new Contact(
            FirstName = 'Ana',
            LastName = 'Ramirez',
            Next_Ask_Date__c = nextAsk
        );
        insert donor;
        return donor;
    }

    private static Date nextAskOf(Id donorId) {
        if (donorId.getSObjectType() == Account.SObjectType) {
            return [SELECT Next_Ask_Date__c FROM Account WHERE Id = :donorId].Next_Ask_Date__c;
        }
        return [SELECT Next_Ask_Date__c FROM Contact WHERE Id = :donorId].Next_Ask_Date__c;
    }

    @IsTest
    static void theEarliestOpenTargetDateIsWritten() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact donor = person(null);
            insert new List<Ask__c>{
                new Ask__c(Donor_Contact__c = donor.Id, Target_Date__c = today.addDays(40)),
                new Ask__c(Donor_Contact__c = donor.Id, Target_Date__c = today.addDays(20)),
                // No Target Date: ignored.
                new Ask__c(Donor_Contact__c = donor.Id)
            };
            Assert.areEqual(today.addDays(20), nextAskOf(donor.Id), 'The earliest open ask.');
        }
    }

    @IsTest
    static void movingOrClosingTheEarliestAskMovesTheDate() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact donor = person(null);
            Ask__c soon = new Ask__c(
                Donor_Contact__c = donor.Id,
                Target_Date__c = today.addDays(10)
            );
            Ask__c later = new Ask__c(
                Donor_Contact__c = donor.Id,
                Target_Date__c = today.addDays(30)
            );
            insert new List<Ask__c>{ soon, later };

            update new Ask__c(Id = soon.Id, Target_Date__c = today.addDays(5));
            Assert.areEqual(today.addDays(5), nextAskOf(donor.Id), 'Follows a new Target Date.');

            update new Ask__c(Id = soon.Id, Outcome__c = 'Won');
            Assert.areEqual(
                today.addDays(30),
                nextAskOf(donor.Id),
                'The next open ask takes over.'
            );
        }
    }

    @IsTest
    static void theLastOpenAskClosingClearsTheDateItSet() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact donor = person(null);
            Ask__c ask = new Ask__c(
                Donor_Contact__c = donor.Id,
                Target_Date__c = today.addDays(15)
            );
            insert ask;
            Assert.areEqual(today.addDays(15), nextAskOf(donor.Id), 'Set by the ask.');

            update new Ask__c(Id = ask.Id, Outcome__c = 'Declined');

            Assert.isNull(nextAskOf(donor.Id), 'No open ask left, and the date was the ask\'s.');
        }
    }

    @IsTest
    static void aDateEnteredByHandIsKeptWhenTheLastAskCloses() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact donor = person(null);
            Ask__c ask = new Ask__c(
                Donor_Contact__c = donor.Id,
                Target_Date__c = today.addDays(15)
            );
            insert ask;
            // Somebody moves the donor's date out by hand while the ask is open.
            update new Contact(Id = donor.Id, Next_Ask_Date__c = today.addDays(90));

            update new Ask__c(Id = ask.Id, Outcome__c = 'Withdrawn');

            Assert.areEqual(today.addDays(90), nextAskOf(donor.Id), 'A date by hand is kept.');
        }
    }

    @IsTest
    static void aDateEnteredByHandWithNoAsksIsNeverTouchedByAClosedAsk() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact donor = person(today.addDays(60));
            Ask__c ask = new Ask__c(Donor_Contact__c = donor.Id, Outcome__c = 'Declined');
            insert ask;
            update new Ask__c(Id = ask.Id, Target_Date__c = today.addDays(5));

            Assert.areEqual(today.addDays(60), nextAskOf(donor.Id), 'Closed asks set nothing.');
        }
    }

    @IsTest
    static void closingTheLastAskCarriesItsAskAgainDate() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact donor = person(null);
            Ask__c ask = new Ask__c(
                Donor_Contact__c = donor.Id,
                Target_Date__c = today.addDays(15)
            );
            insert ask;

            update new Ask__c(
                Id = ask.Id,
                Outcome__c = 'Won',
                Next_Ask_Date__c = today.addDays(365)
            );

            Assert.areEqual(today.addDays(365), nextAskOf(donor.Id), 'Ask again in a year.');
        }
    }

    @IsTest
    static void aBlankDonorDateTakesTheAskAgainDateAndAPastOneIsIgnored() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact blank = person(null);
            Contact past = person(null);
            Ask__c noTarget = new Ask__c(Donor_Contact__c = blank.Id);
            Ask__c pastAgain = new Ask__c(
                Donor_Contact__c = past.Id,
                Target_Date__c = today.addDays(10)
            );
            insert new List<Ask__c>{ noTarget, pastAgain };

            update new List<Ask__c>{
                new Ask__c(
                    Id = noTarget.Id,
                    Outcome__c = 'Declined',
                    Next_Ask_Date__c = today.addDays(180)
                ),
                new Ask__c(
                    Id = pastAgain.Id,
                    Outcome__c = 'Declined',
                    Next_Ask_Date__c = today.addDays(-1)
                )
            };

            Assert.areEqual(today.addDays(180), nextAskOf(blank.Id), 'A blank date takes it.');
            Assert.isNull(nextAskOf(past.Id), 'A date already gone is not carried.');
        }
    }

    @IsTest
    static void theAskAgainDateNeverReplacesADateByHandOrAnOpenAsk() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact byHand = person(today.addDays(90));
            Contact stillOpen = person(null);
            Ask__c closing = new Ask__c(Donor_Contact__c = byHand.Id);
            Ask__c first = new Ask__c(
                Donor_Contact__c = stillOpen.Id,
                Target_Date__c = today.addDays(10)
            );
            Ask__c second = new Ask__c(
                Donor_Contact__c = stillOpen.Id,
                Target_Date__c = today.addDays(40)
            );
            insert new List<Ask__c>{ closing, first, second };

            update new List<Ask__c>{
                new Ask__c(
                    Id = closing.Id,
                    Outcome__c = 'Won',
                    Next_Ask_Date__c = today.addDays(365)
                ),
                new Ask__c(Id = first.Id, Outcome__c = 'Won', Next_Ask_Date__c = today.addDays(365))
            };

            Assert.areEqual(today.addDays(90), nextAskOf(byHand.Id), 'A date by hand is kept.');
            Assert.areEqual(
                today.addDays(40),
                nextAskOf(stillOpen.Id),
                'The open ask still sets the date.'
            );
        }
    }

    @IsTest
    static void deletingTheLastAskClearsAndAnOrganizationDonorIsKeptToo() {
        System.runAs(staff()) {
            Date today = Date.today();
            Account foundation = new Account(Name = 'Rivera Foundation');
            insert foundation;
            Ask__c ask = new Ask__c(
                Donor_Account__c = foundation.Id,
                Target_Date__c = today.addDays(25)
            );
            insert ask;
            Assert.areEqual(today.addDays(25), nextAskOf(foundation.Id), 'Account donors too.');

            delete ask;

            Assert.isNull(nextAskOf(foundation.Id), 'The deleted ask took its date with it.');
        }
    }

    @IsTest
    static void movingAnAskToAnotherDonorUpdatesBoth() {
        System.runAs(staff()) {
            Date today = Date.today();
            Contact first = person(null);
            Contact second = person(null);
            Ask__c ask = new Ask__c(
                Donor_Contact__c = first.Id,
                Target_Date__c = today.addDays(12)
            );
            insert ask;

            update new Ask__c(Id = ask.Id, Donor_Contact__c = second.Id);

            Assert.isNull(nextAskOf(first.Id), 'The first donor has no open ask left.');
            Assert.areEqual(today.addDays(12), nextAskOf(second.Id), 'The second donor has it.');
        }
    }

    @IsTest
    static void aLoadOfAsksIsHandledInOneGo() {
        System.runAs(staff()) {
            Date today = Date.today();
            List<Contact> donors = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                donors.add(new Contact(FirstName = 'Donor', LastName = 'Number ' + i));
            }
            insert donors;
            List<Ask__c> asks = new List<Ask__c>();
            for (Integer i = 0; i < 200; i++) {
                asks.add(
                    new Ask__c(Donor_Contact__c = donors[i].Id, Target_Date__c = today.addDays(i))
                );
            }
            Test.startTest();
            insert asks;
            Test.stopTest();
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE Id IN :donors AND Next_Ask_Date__c != NULL],
                'Every donor got its date.'
            );
        }
    }
}
