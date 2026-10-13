/**
 * Stage two of the sample data load, run on its own: one chunk of people per job, each job
 * reading the payload again and the household map handed to it. Stage one is called directly
 * to make the households, and the job's execute method is called directly too, because an Apex
 * test context does not run a job that another job queued.
 */
@IsTest(testFor='ApexClass:SampleDataContactQueueable')
private class SampleDataContactQueueableTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWithInstalledModules();
    }

    private static String payload(Integer people) {
        List<Object> members = new List<Object>();
        for (Integer i = 0; i < people; i++) {
            members.add(
                new Map<String, Object>{
                    'key' => 'H0-' + (i + 1),
                    'firstName' => 'Chunk' + i,
                    'lastName' => 'Queueable',
                    'salutation' => 'Mx.',
                    'householdRole' => i == 0 ? 'Head' : 'Other',
                    'email' => 'chunk' +
                    i +
                    '@example.org',
                    'phone' => '(555) 555-0100',
                    'mailingStreet' => '1 Test St',
                    'mailingCity' => 'Testville',
                    'mailingState' => 'CA',
                    'mailingPostalCode' => '90000',
                    'birthdate' => '1980-01-01'
                }
            );
        }
        Map<String, Object> household = new Map<String, Object>{
            'key' => 'H0',
            'customName' => false,
            'name' => null,
            'anniversary' => null,
            'address' => new Map<String, Object>{
                'street' => '1 Test St',
                'city' => 'Testville',
                'state' => 'CA',
                'postalCode' => '90000'
            },
            'members' => members
        };
        Map<String, Object> organization = new Map<String, Object>{
            'key' => 'O1',
            'name' => 'Test Foundation',
            'website' => 'https://www.example.org',
            'phone' => '(555) 555-0199'
        };
        return JSON.serialize(
            new Map<String, Object>{
                'households' => new List<Object>{ household },
                'organizations' => new List<Object>{ organization }
            }
        );
    }

    private static Map<String, Id> loadHouseholds() {
        return SampleDataLoadQueueable.loadHouseholdsAndOrganizations(
            SampleDataSet.parse(SampleDataLoader.getSampleDataJson())
        );
    }

    @IsTest
    static void aJobInsertsItsChunkOfPeopleIntoTheirHousehold() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = payload(3);
            Map<String, Id> households = loadHouseholds();

            Test.startTest();
            new SampleDataContactQueueable(households, 0).execute(null);
            Test.stopTest();

            Assert.areEqual(
                3,
                SampleDataLoader.status().contactCount,
                'All three people are in the first chunk'
            );
            Assert.areEqual(
                3,
                [
                    SELECT COUNT()
                    FROM Contact
                    WHERE AccountId = :households.get('H0') AND Sample_Data__c = TRUE
                ],
                'Each of them is joined to the household the map names'
            );
        }
    }

    @IsTest
    static void twoHundredPeopleTakeTwoJobsOfOneHundred() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = payload(200);
            Map<String, Id> households = loadHouseholds();

            Test.startTest();
            new SampleDataContactQueueable(households, 0).execute(null);
            Integer afterFirst = SampleDataLoader.status().contactCount;
            new SampleDataContactQueueable(households, 1).execute(null);
            Test.stopTest();

            Assert.areEqual(
                SampleDataLoader.CONTACT_CHUNK_SIZE,
                afterFirst,
                'The first job inserts exactly one chunk'
            );
            Assert.areEqual(
                200,
                SampleDataLoader.status().contactCount,
                'The second job inserts the rest, and nobody twice'
            );
        }
    }

    @IsTest
    static void aChunkPastTheEndInsertsNothing() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = payload(2);
            Map<String, Id> households = loadHouseholds();

            Test.startTest();
            new SampleDataContactQueueable(households, 5).execute(null);
            Test.stopTest();

            Assert.areEqual(0, SampleDataLoader.status().contactCount, 'There is no chunk five');
        }
    }

    @IsTest
    static void aJobWhosePayloadCannotBeReadFailsAndSaysSo() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = 'this is not json';
            Boolean failed = false;

            Test.startTest();
            try {
                new SampleDataContactQueueable(new Map<String, Id>(), 0).execute(null);
            } catch (Exception expected) {
                failed = true;
            }
            Test.stopTest();

            Assert.isTrue(
                failed,
                'The failure is passed on so the platform records the job as failed'
            );
            Assert.areEqual(0, SampleDataLoader.status().contactCount, 'And nobody was inserted');
        }
    }
}
