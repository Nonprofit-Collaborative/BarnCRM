/**
 * Tests for the nightly top up batch: every active recurring commitment is reached, not
 * only the oldest handful, and the run is recorded when the batch finishes.
 */
@IsTest(testFor='ApexClass:InstallmentTopUpBatch')
private class InstallmentTopUpBatchTest {
    @IsTest
    static void extendsEveryActiveRecurringCommitmentNotJustTheOldest() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
            insert person;
            List<Commitment__c> recurring = new List<Commitment__c>();
            for (Integer index = 0; index < 60; index++) {
                recurring.add(
                    new Commitment__c(
                        Type__c = 'Recurring',
                        Status__c = 'Active',
                        Donor_Contact__c = person.Id,
                        Amount__c = 25,
                        Frequency__c = 'Yearly',
                        Start_Date__c = Date.today().addDays(-index)
                    )
                );
            }
            insert recurring;
            delete [SELECT Id FROM Installment__c];

            // A test may run only one chunk of an asynchronous batch, so the chunks the platform
            // would hand the batch are handed to it here, the same size and in the same order.
            InstallmentTopUpBatch batch = new InstallmentTopUpBatch();
            Integer chunks = 0;
            Test.startTest();
            Database.QueryLocatorIterator rows = batch.start(null).iterator();
            List<Commitment__c> chunk = new List<Commitment__c>();
            while (rows.hasNext()) {
                chunk.add((Commitment__c) rows.next());
                if (chunk.size() == InstallmentTopUpBatch.CHUNK_SIZE || !rows.hasNext()) {
                    batch.execute(null, chunk);
                    chunks++;
                    chunk = new List<Commitment__c>();
                }
            }
            batch.finish(null);
            Test.stopTest();

            Assert.isTrue(chunks > 1, 'Sixty commitments take more chunks than one: ' + chunks);
            Assert.areEqual(60, batch.commitmentsProcessed(), 'Every chunk was counted.');
            // Reached is counted per commitment, not per installment. A yearly gift that started
            // in the last sixty days has two installments inside the twelve month horizon: the one
            // on its start date and the one a year on, which the horizon still reaches.
            Map<Id, Integer> installmentsByCommitment = new Map<Id, Integer>();
            for (AggregateResult row : [
                SELECT Commitment__c commitment, COUNT(Id) installments
                FROM Installment__c
                GROUP BY Commitment__c
            ]) {
                installmentsByCommitment.put(
                    (Id) row.get('commitment'),
                    (Integer) row.get('installments')
                );
            }
            Assert.areEqual(
                new Map<Id, Commitment__c>(recurring).keySet(),
                installmentsByCommitment.keySet(),
                'Every one of the sixty commitments was reached, across more chunks than one.'
            );
            for (Integer installments : installmentsByCommitment.values()) {
                Assert.areEqual(
                    2,
                    installments,
                    'Each was extended to the horizon: its start date and a year on.'
                );
            }
            Assert.areNotEqual(
                null,
                Giving_Settings__c.getOrgDefaults().Installment_Top_Up_Last_Run__c,
                'The batch records when it finished, which is what the Hub shows.'
            );
        }
    }

    @IsTest
    static void leavesAPausedCommitmentAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
            insert person;
            Commitment__c paused = new Commitment__c(
                Type__c = 'Recurring',
                Status__c = 'Paused',
                Donor_Contact__c = person.Id,
                Amount__c = 25,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today()
            );
            insert paused;
            delete [SELECT Id FROM Installment__c];

            Test.startTest();
            Database.executeBatch(new InstallmentTopUpBatch(), InstallmentTopUpBatch.CHUNK_SIZE);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Installment__c WHERE Commitment__c = :paused.Id],
                'A paused commitment generates nothing (R-CM3).'
            );
        }
    }
}
