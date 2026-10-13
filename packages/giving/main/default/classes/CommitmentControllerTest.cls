/**
 * Tests for the surface the commitment schedule preview component calls.
 */
@IsTest
private class CommitmentControllerTest {
    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        return person;
    }

    private static Commitment__c pledge(Id donorId) {
        Commitment__c commitment = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
        insert commitment;
        return commitment;
    }

    @IsTest
    static void previewsAScheduleBeforeAnythingIsSaved() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CommitmentController.ScheduleInput input = new CommitmentController.ScheduleInput();
            input.commitmentType = 'Pledge';
            input.amount = 100;
            input.frequency = 'Monthly';
            input.startDate = Date.today();
            input.expectedTotal = 1200;
            input.installmentsPlanned = 12;

            Test.startTest();
            CommitmentController.SchedulePreview preview = CommitmentController.getSchedulePreview(
                input
            );
            Test.stopTest();

            Assert.areEqual(
                12,
                preview.count,
                'The preview shows the twelve payments the pledge implies.'
            );
            Assert.areEqual(1200, preview.expectedTotal, 'The preview totals what is expected.');
            Assert.isFalse(preview.saved, 'Nothing was saved to produce the preview.');
            Assert.areEqual(0, [SELECT COUNT() FROM Installment__c], 'A preview writes nothing.');
        }
    }

    @IsTest
    static void refusesAPreviewWithoutEnoughToWorkWith() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            CommitmentController.ScheduleInput input = new CommitmentController.ScheduleInput();
            input.amount = null;

            Boolean refused = false;
            Test.startTest();
            try {
                CommitmentController.getSchedulePreview(input);
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(
                refused,
                'A preview without an amount asks for one rather than failing silently.'
            );
        }
    }

    @IsTest
    static void generatesTheScheduleOnDemand() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c commitment = pledge(person.Id);

            Test.startTest();
            CommitmentController.SchedulePreview preview = CommitmentController.generateNow(
                commitment.Id
            );
            Test.stopTest();

            Assert.areEqual(
                3,
                preview.count,
                'Generate now creates the payments the commitment implies.'
            );
            Assert.isTrue(preview.saved, 'What comes back is the saved schedule.');
            Assert.areEqual(
                1,
                preview.installments[0].sequence,
                'The rows come back in schedule order.'
            );
        }
    }

    @IsTest
    static void readsAScheduleThatAlreadyExists() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c commitment = pledge(person.Id);
            CommitmentService.generateInstallments(new Set<Id>{ commitment.Id });

            Test.startTest();
            CommitmentController.SchedulePreview preview = CommitmentController.getSchedule(
                commitment.Id
            );
            Test.stopTest();

            Assert.areEqual(
                3,
                preview.count,
                'The component reads the schedule the commitment has.'
            );
            Assert.areEqual(
                300,
                preview.expectedTotal,
                'The total is what the three payments expect.'
            );
            Assert.areEqual(
                'Active',
                preview.commitmentStatus,
                'The status comes back too, so the component offers only the changes it allows.'
            );
        }
    }

    @IsTest
    static void pausesAndResumesFromTheComponent() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c commitment = pledge(person.Id);
            CommitmentService.generateInstallments(new Set<Id>{ commitment.Id });

            Test.startTest();
            CommitmentController.changeStatus(commitment.Id, 'pause');
            Assert.areEqual(
                'Paused',
                [SELECT Status__c FROM Commitment__c WHERE Id = :commitment.Id].Status__c,
                'Pause is a status change, not a deletion.'
            );
            CommitmentController.changeStatus(commitment.Id, 'resume');
            Test.stopTest();

            Assert.areEqual(
                'Active',
                [SELECT Status__c FROM Commitment__c WHERE Id = :commitment.Id].Status__c,
                'Resume puts the commitment back to work.'
            );
        }
    }

    @IsTest
    static void refusesAnActionItDoesNotKnow() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();
            Commitment__c commitment = pledge(person.Id);

            Boolean refused = false;
            Test.startTest();
            try {
                CommitmentController.changeStatus(commitment.Id, 'archive');
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(
                refused,
                'An action the service does not offer is refused in plain language.'
            );
        }
    }

    @IsTest
    static void refusesAMissingRecord() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Boolean refused = false;
            Test.startTest();
            try {
                CommitmentController.getSchedule(null);
            } catch (AuraHandledException expected) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'A missing commitment is reported, not guessed at.');
        }
    }
}
