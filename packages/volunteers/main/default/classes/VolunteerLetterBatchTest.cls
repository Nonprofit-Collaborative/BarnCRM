/**
 * The Generate volunteer letters flow action and its job (V-08, R-VL1, R-VL6, R-VL7): it takes a
 * letter type, refuses an unusable template or period before anything starts, runs a
 * transaction's requests as one job, and tells the person who started it the counts. Run as a
 * Standard User coordinator holding only BarnCRM Staff and Volunteers Coordinator.
 */
@IsTest(testFor='ApexClass:VolunteerLetterBatch, ApexClass:VolunteerLetterService')
private class VolunteerLetterBatchTest {
    private static final String COORDINATOR = 'BatchCoordinator';
    private static final Date FROM_DATE = Date.newInstance(2026, 3, 1);
    private static final Date TO_DATE = Date.newInstance(2026, 3, 31);
    private static final String HOURS_LETTER = VolunteerLetterTemplates.TYPE_HOURS_LETTER;

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestUsers.standardUserWith(
                COORDINATOR,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
            );
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            settings.Job_Notifications__c = true;
            TestDataFactory.saveSettings(settings);
            VolunteersTestData.volunteerSettings(false, true);
            VolunteersTestData.job('Food pantry');
            VolunteerLetterTemplates.installDefaultsDuringInstall();
        }
    }

    private static User coordinator() {
        return [SELECT Id FROM User WHERE LastName = :COORDINATOR AND IsActive = TRUE LIMIT 1];
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    private static List<Contact> ownedContacts(Integer howMany) {
        List<Contact> people = VolunteersTestData.contacts(howMany);
        Id ownerId = coordinator().Id;
        for (Contact person : people) {
            person.OwnerId = ownerId;
        }
        update people;
        return people;
    }

    private static VolunteerLetterBatch.Request requestFor(List<Id> people, String letterType) {
        VolunteerLetterBatch.Request request = new VolunteerLetterBatch.Request();
        request.personIds = people;
        request.letterType = letterType;
        request.fromDate = FROM_DATE;
        request.toDate = TO_DATE;
        return request;
    }

    private static Id shippedTemplateId(String key) {
        return [
            SELECT Id
            FROM Volunteer_Letter_Template__c
            WHERE Template_Key__c = :key
            WITH SYSTEM_MODE
        ]
        .Id;
    }

    private static String refusalOf(List<VolunteerLetterBatch.Request> requests) {
        try {
            VolunteerLetterBatch.generateLetters(requests);
        } catch (VolunteerLetterService.VolunteerLetterException refused) {
            return refused.getMessage();
        }
        return null;
    }

    @IsTest
    static void theFlowActionUsesTheActiveTemplateOfTheType() {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(1);
            insert VolunteersTestData.newHours(people[0].Id, jobId(), 2);
            // Activating a new template of the type retires the shipped one (R-VL1).
            insert new Volunteer_Letter_Template__c(
                Name = 'Our own letter',
                Type__c = HOURS_LETTER,
                Body__c = '<p>{PersonName}</p>',
                Active__c = true
            );
        }

        Test.startTest();
        System.runAs(coordinator()) {
            VolunteerLetterBatch.generateLetters(
                new List<VolunteerLetterBatch.Request>{
                    requestFor(new List<Id>{ people[0].Id }, HOURS_LETTER)
                }
            );
        }
        Test.stopTest();

        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :people[0].Id
            ];
            Assert.areEqual(1, links.size(), 'One letter made: ' + links.size());
            List<ContentVersion> files = [
                SELECT Title
                FROM ContentVersion
                WHERE ContentDocumentId = :links[0].ContentDocumentId
            ];
            Assert.areEqual(1, files.size(), 'One letter made.');
            Assert.isTrue(
                files[0].Title.startsWith('Our own letter'),
                'From the active template of the type: ' + files[0].Title
            );
        }
    }

    @IsTest
    static void aTypeWithNoActiveTemplateIsRefusedBeforeAnythingStarts() {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(1);
            update new Volunteer_Letter_Template__c(
                Id = shippedTemplateId('Hours_Letter'),
                Active__c = false
            );
        }
        String noTemplate;
        String blankType;
        Integer jobsBefore = [SELECT COUNT() FROM AsyncApexJob];

        Test.startTest();
        System.runAs(coordinator()) {
            noTemplate = refusalOf(
                new List<VolunteerLetterBatch.Request>{
                    requestFor(new List<Id>{ people[0].Id }, HOURS_LETTER)
                }
            );
            blankType = refusalOf(
                new List<VolunteerLetterBatch.Request>{
                    requestFor(new List<Id>{ people[0].Id }, ' ')
                }
            );
        }
        Test.stopTest();

        Assert.areEqual(
            String.format(
                Label.Volunteers_Letter_NoActiveTemplateForType,
                new List<Object>{ HOURS_LETTER }
            ),
            noTemplate,
            'A readable message names the type.'
        );
        Assert.areEqual(Label.Volunteers_Letter_TypeRequired, blankType, 'A blank type too.');
        Assert.areEqual(jobsBefore, [SELECT COUNT() FROM AsyncApexJob], 'No job was started.');
    }

    @IsTest
    static void aBadPeriodIsRefusedBeforeAnythingStarts() {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(1);
        }
        VolunteerLetterBatch.Request reversed = requestFor(
            new List<Id>{ people[0].Id },
            HOURS_LETTER
        );
        reversed.fromDate = TO_DATE;
        reversed.toDate = FROM_DATE;
        String refusal;
        Integer jobsBefore = [SELECT COUNT() FROM AsyncApexJob];

        Test.startTest();
        System.runAs(coordinator()) {
            refusal = refusalOf(new List<VolunteerLetterBatch.Request>{ reversed });
        }
        Test.stopTest();

        Assert.areEqual(Label.Volunteers_Letter_BadPeriod, refusal, 'The period is checked.');
        Assert.areEqual(jobsBefore, [SELECT COUNT() FROM AsyncApexJob], 'No job was started.');
    }

    @IsTest
    static void anInactiveTemplateIsNeverMerged() {
        Id shipped = shippedTemplateId('Certificate');
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(1);
            update new Volunteer_Letter_Template__c(Id = shipped, Active__c = false);
        }
        String preview;
        String generated;

        Test.startTest();
        System.runAs(coordinator()) {
            try {
                VolunteerLetterService.mergeLetters(
                    new List<Id>{ people[0].Id },
                    shipped,
                    FROM_DATE,
                    TO_DATE
                );
            } catch (VolunteerLetterService.VolunteerLetterException refused) {
                preview = refused.getMessage();
            }
            try {
                VolunteerLetterService.generate(
                    new List<Id>{ people[0].Id },
                    shipped,
                    FROM_DATE,
                    TO_DATE
                );
            } catch (VolunteerLetterService.VolunteerLetterException refused) {
                generated = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.isNotNull(preview, 'A preview of an inactive template is refused.');
        Assert.isTrue(preview.contains('not active'), preview);
        Assert.areEqual(preview, generated, 'And so is generating with it.');
    }

    @IsTest
    static void theJobCountsMadeSkippedAndFailedAndTellsTheStarterOnce() {
        List<Contact> people;
        Id template = shippedTemplateId('Hours_Letter');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(4);
            insert new List<Volunteer_Hours__c>{
                VolunteersTestData.newHours(people[0].Id, jobId(), 2),
                VolunteersTestData.newHours(people[1].Id, jobId(), 1)
            };
        }
        // One chunk for people with a good template, one the job cannot make (no template).
        VolunteerLetterBatch.Work good = new VolunteerLetterBatch.Work();
        good.personIds = new List<Id>{ people[0].Id, people[1].Id, people[2].Id };
        good.templateId = template;
        good.fromDate = FROM_DATE;
        good.toDate = TO_DATE;
        VolunteerLetterBatch.Work broken = new VolunteerLetterBatch.Work();
        broken.personIds = new List<Id>{ people[3].Id };
        broken.fromDate = FROM_DATE;
        broken.toDate = TO_DATE;
        Id starter = coordinator().Id;
        VolunteerLetterBatch job = new VolunteerLetterBatch(
            new List<VolunteerLetterBatch.Work>{ good, broken },
            starter
        );

        Test.startTest();
        System.runAs(coordinator()) {
            job.execute(null, new List<VolunteerLetterBatch.Work>{ good, broken });
            job.finish(null);
        }
        Test.stopTest();

        Assert.areEqual(2, job.lettersMade(), 'Two letters made.');
        Assert.areEqual(1, job.peopleFailed(), 'The chunk with no template failed.');
        Assert.areEqual(
            new Map<String, Integer>{ Label.Volunteers_Letter_NoHours => 1 },
            job.peopleSkippedByReason(),
            'One person skipped, with the reason.'
        );
        List<JobNotifier.Notice> sent = JobNotifier.sentNotices();
        Assert.areEqual(1, sent.size(), 'One notification, not one per chunk.');
        Assert.areEqual(starter, sent[0].recipientId, 'To the person who started it.');
        Assert.areEqual('Error Log', sent[0].section, 'Failures point to the Error Log.');
        String body = VolunteerLetterBatch.summary(
            job.lettersMade(),
            job.peopleSkippedByReason(),
            job.peopleFailed()
        );
        Assert.isTrue(body.contains('2 letters made, 1 skipped, 1 failed.'), body);
        Assert.isTrue(body.contains(Label.Volunteers_Letter_NoHours), body);
        Assert.isTrue(body.contains(Label.Volunteers_JobNotice_LettersFailed), body);
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Error_Log__c
                WHERE Context__c = 'VolunteerLetterBatch'
                WITH SYSTEM_MODE
            ],
            'The failure is in the Error Log.'
        );
    }

    @IsTest
    static void aJobWithNoFailuresDoesNotPointToTheErrorLog() {
        String body;
        System.runAs(coordinator()) {
            body = VolunteerLetterBatch.summary(3, new Map<String, Integer>(), 0);
        }
        Assert.areEqual('3 letters made, 0 skipped, 0 failed.', body);
    }

    @IsTest
    static void everyRequestInOneTransactionStartsOneJob() {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            // Ten people is one chunk: a test method may run only one chunk of a job.
            people = ownedContacts(10);
        }
        List<VolunteerLetterBatch.Request> requests = new List<VolunteerLetterBatch.Request>();
        for (Contact person : people) {
            requests.add(requestFor(new List<Id>{ person.Id }, HOURS_LETTER));
        }
        // The same person in two requests is still one letter.
        requests.add(requestFor(new List<Id>{ people[0].Id }, HOURS_LETTER));
        List<Id> jobIds;
        Integer queries;

        Test.startTest();
        System.runAs(coordinator()) {
            jobIds = VolunteerLetterBatch.generateLetters(requests);
            queries = Limits.getQueries();
        }
        Test.stopTest();

        Assert.areEqual(11, jobIds.size(), 'An answer for every request.');
        Assert.areEqual(new Set<Id>{ jobIds[0] }, new Set<Id>(jobIds), 'The same one job.');
        Assert.isNotNull(jobIds[0], 'A job was started.');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex' AND ApexClass.Name = 'VolunteerLetterBatch'
            ],
            'One job for every request.'
        );
        Assert.isTrue(queries < 20, 'Checks do not repeat per request: ' + queries);
    }
}
