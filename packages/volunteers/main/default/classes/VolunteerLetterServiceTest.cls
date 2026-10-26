/**
 * Volunteer letters (V-08, R-VL1 to R-VL5): what a letter counts, how its values are merged and
 * escaped, who may make one, the 251 person bulk path, and the shipped templates. Run as a
 * Standard User coordinator holding only BarnCRM Staff and Volunteers Coordinator.
 */
@IsTest(
    testFor='ApexClass:VolunteerLetterService, ApexClass:VolunteerLetterBatch, ApexClass:VolunteerLetterSelector, ApexClass:VolunteerLetterRenderer'
)
private class VolunteerLetterServiceTest {
    private static final String COORDINATOR = 'LetterCoordinator';
    private static final String STAFFER = 'LetterStaffer';
    private static final Date FROM_DATE = Date.newInstance(2026, 3, 1);
    private static final Date TO_DATE = Date.newInstance(2026, 3, 31);

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestUsers.standardUserWith(
                COORDINATOR,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
            );
            TestUsers.standardUserWith(
                STAFFER,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
            );
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            settings.Organization_Legal_Name__c = 'Barn & <Co>';
            settings.Organization_Street__c = '1 Main St';
            settings.Organization_Street_2__c = 'Unit <4>';
            settings.Organization_City__c = 'Springfield';
            settings.Organization_State__c = 'IL';
            settings.Organization_Postal_Code__c = '62701';
            TestDataFactory.saveSettings(settings);
            // Hours count as soon as they are saved, so every entry below is Approved.
            VolunteersTestData.volunteerSettings(false, true);
            VolunteersTestData.job('Food pantry');
            VolunteerLetterTemplates.installDefaultsDuringInstall();
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    private static Id templateId(String key) {
        return [
            SELECT Id
            FROM Volunteer_Letter_Template__c
            WHERE Template_Key__c = :key
            WITH SYSTEM_MODE
        ]
        .Id;
    }

    /** Contacts the coordinator owns, so only the permission set decides what they may do. */
    private static List<Contact> ownedContacts(Integer howMany) {
        List<Contact> people = VolunteersTestData.contacts(howMany);
        Id ownerId = user(COORDINATOR).Id;
        for (Contact person : people) {
            person.OwnerId = ownerId;
        }
        update people;
        return people;
    }

    private static List<Id> idsOf(List<SObject> records) {
        return new List<Id>(new Map<Id, SObject>(records).keySet());
    }

    /** Stands in for the PDF service, so the bulk test measures the generator's own work. */
    private class TextRenderer extends VolunteerLetterRenderer {
        public override Blob render(String html) {
            return Blob.valueOf(html);
        }
    }

    @IsTest
    static void aLetterCountsApprovedHoursInThePeriodAndIsFiledOnThePerson() {
        Contact person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = ownedContacts(1)[0];
            Volunteer_Job__c other = VolunteersTestData.job('Front desk');
            Volunteer_Hours__c outside = VolunteersTestData.newHours(person.Id, jobId(), 7);
            outside.Date_Worked__c = Date.newInstance(2026, 4, 2);
            insert new List<Volunteer_Hours__c>{
                VolunteersTestData.newHours(person.Id, jobId(), 3),
                VolunteersTestData.newHours(person.Id, other.Id, 2.5),
                outside
            };
            VolunteersTestData.volunteerSettings(true, true);
            insert VolunteersTestData.newHours(person.Id, jobId(), 40);
        }
        VolunteerLetterService.Letter letter;
        VolunteerLetterService.Outcome outcome;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            letter = VolunteerLetterService.mergeLetters(
                new List<Id>{ person.Id },
                templateId('Hours_Letter'),
                FROM_DATE,
                TO_DATE
            )[0];
            outcome = VolunteerLetterService.generate(
                new List<Id>{ person.Id },
                templateId('Certificate'),
                FROM_DATE,
                TO_DATE
            );
        }
        Test.stopTest();

        Assert.isNull(letter.skipReason, 'The person has approved hours in the period.');
        Assert.isTrue(
            letter.body.contains(' 5.5 hours'),
            'Approved, in period only: ' + letter.body
        );
        Assert.isTrue(letter.body.contains('<li>Food pantry: 3 hours</li>'), letter.body);
        Assert.isTrue(letter.body.contains('<li>Front desk: 2.5 hours</li>'), letter.body);
        Assert.isTrue(
            letter.body.contains('1 Main St, Unit &lt;4&gt;, Springfield, IL 62701'),
            'The address is its parts on one line, HTML escaped: ' + letter.body
        );
        Assert.areEqual(1, outcome.versionIds.size(), 'One file for one person.');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            ContentVersion file = [
                SELECT ContentDocumentId, Title, FileExtension
                FROM ContentVersion
                WHERE Id = :outcome.versionIds[0]
            ];
            Assert.isTrue(
                file.Title.startsWith('Certificate of volunteer service for '),
                file.Title
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE
                        ContentDocumentId = :file.ContentDocumentId
                        AND LinkedEntityId = :person.Id
                ],
                'The file is linked to the person.'
            );
        }
    }

    @IsTest
    static void everyMergedValueIsEscapedAndUnknownTokensStayAsTyped() {
        Contact person;
        Volunteer_Letter_Template__c template = new Volunteer_Letter_Template__c(
            Name = 'Proof',
            Type__c = VolunteerLetterTemplates.TYPE_HOURS_LETTER,
            Body__c = '{OrganizationName}|{PersonName}|{FirstName}|{Hours}|{JobList}|{Typo}',
            Active__c = true
        );
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = ownedContacts(1)[0];
            update new Contact(
                Id = person.Id,
                LastName = '<b>Ruiz</b>',
                Preferred_Name__c = '{Hours}'
            );
            Volunteer_Job__c job = VolunteersTestData.job('<script>alert(1)</script>');
            insert VolunteersTestData.newHours(person.Id, job.Id, 2);
            insert template;
        }
        String body;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            body = VolunteerLetterService.mergeLetters(
                    new List<Id>{ person.Id },
                    template.Id,
                    FROM_DATE,
                    TO_DATE
                )[0]
                .body;
        }
        Test.stopTest();

        Assert.isTrue(body.startsWith('Barn &amp; &lt;Co&gt;|'), body);
        Assert.isTrue(body.contains('&lt;b&gt;Ruiz&lt;/b&gt;'), 'The name is escaped: ' + body);
        Assert.isTrue(body.contains('|{Hours}|2|'), 'A value is never merged twice: ' + body);
        Assert.isTrue(body.contains('&lt;script&gt;'), 'The job is escaped: ' + body);
        Assert.isFalse(body.contains('<script>'), 'No markup from a value: ' + body);
        Assert.isTrue(body.endsWith('|{Typo}'), 'An unknown token is left as typed: ' + body);
    }

    @IsTest
    static void aPersonWithoutHoursAndAnAccountThatIsNotAPersonAreSkipped() {
        Contact person;
        Account household;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = ownedContacts(1)[0];
            household = VolunteersTestData.household('Okafor Household');
        }
        VolunteerLetterService.Outcome outcome;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            outcome = VolunteerLetterService.generate(
                new List<Id>{ person.Id, household.Id },
                templateId('Hours_Letter'),
                FROM_DATE,
                TO_DATE
            );
        }
        Test.stopTest();

        Assert.isTrue(outcome.versionIds.isEmpty(), 'No file is made.');
        Assert.areEqual(
            Label.Volunteers_Letter_NoHours,
            outcome.skipped.get(person.Id),
            'No hours.'
        );
        Assert.areEqual(
            Label.Volunteers_Letter_NotAPerson,
            outcome.skipped.get(household.Id),
            'A household is not a person.'
        );
    }

    @IsTest
    static void lettersNeedManageVolunteersAndAPeriodInOrder() {
        Id hoursLetter = templateId('Hours_Letter');
        String byStaff;
        String reversed;
        String flow;

        Test.startTest();
        System.runAs(user(STAFFER)) {
            try {
                VolunteerLetterService.mergeLetters(
                    new List<Id>(),
                    hoursLetter,
                    FROM_DATE,
                    TO_DATE
                );
            } catch (VolunteerLetterService.VolunteerLetterException refused) {
                byStaff = refused.getMessage();
            }
            try {
                VolunteerLetterBatch.generateLetters(new List<VolunteerLetterBatch.Request>());
            } catch (VolunteerLetterService.VolunteerLetterException refused) {
                flow = refused.getMessage();
            }
        }
        System.runAs(user(COORDINATOR)) {
            try {
                VolunteerLetterService.mergeLetters(
                    new List<Id>(),
                    hoursLetter,
                    TO_DATE,
                    FROM_DATE
                );
            } catch (VolunteerLetterService.VolunteerLetterException refused) {
                reversed = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(Label.Volunteers_Letter_NeedManagePermission, byStaff, 'Staff cannot.');
        Assert.areEqual(Label.Volunteers_Letter_NeedManagePermission, flow, 'Nor from a flow.');
        Assert.areEqual(Label.Volunteers_Letter_BadPeriod, reversed, 'From after To is refused.');
    }

    @IsTest
    static void generateAndMergeRefuseAReversedOrMissingPeriodBeforeAnyFileIsMade() {
        Id hoursLetter = templateId('Hours_Letter');
        List<String> refusals = new List<String>();

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            for (
                Date[] period : new List<Date[]>{
                    new List<Date>{ TO_DATE, FROM_DATE },
                    new List<Date>{ null, TO_DATE },
                    new List<Date>{ FROM_DATE, null }
                }
            ) {
                try {
                    VolunteerLetterService.generate(
                        new List<Id>(),
                        hoursLetter,
                        period[0],
                        period[1]
                    );
                } catch (VolunteerLetterService.VolunteerLetterException refused) {
                    refusals.add(refused.getMessage());
                }
                try {
                    VolunteerLetterService.mergeLetters(
                        new List<Id>(),
                        hoursLetter,
                        period[0],
                        period[1]
                    );
                } catch (VolunteerLetterService.VolunteerLetterException refused) {
                    refusals.add(refused.getMessage());
                }
            }
        }
        Test.stopTest();

        Assert.areEqual(6, refusals.size(), 'Every bad period is refused by both entry points.');
        Assert.areEqual(
            new Set<String>{ Label.Volunteers_Letter_BadPeriod },
            new Set<String>(refusals),
            'With the plain period message.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ContentVersion WITH SYSTEM_MODE],
            'No file was made.'
        );
    }

    @IsTest
    static void twoHundredFiftyOnePeopleAreGeneratedInOneTransaction() {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(251);
            List<Volunteer_Hours__c> hours = new List<Volunteer_Hours__c>();
            Id job = jobId();
            for (Contact person : people) {
                hours.add(VolunteersTestData.newHours(person.Id, job, 1));
            }
            insert hours;
        }
        VolunteerLetterService.renderer = new TextRenderer();
        VolunteerLetterService.Outcome outcome;
        Integer queries;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            outcome = VolunteerLetterService.generate(
                idsOf(people),
                templateId('Hours_Letter'),
                FROM_DATE,
                TO_DATE
            );
            queries = Limits.getQueries();
        }
        Test.stopTest();

        Assert.areEqual(251, outcome.versionIds.size(), 'A file for every person.');
        Assert.isTrue(outcome.skipped.isEmpty(), 'Nobody skipped: ' + outcome.skipped);
        Assert.isTrue(queries < 15, 'The query count does not grow with people: ' + queries);
    }

    @IsTest
    static void aFlowRunsTheBatchForAListOfPeople() {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = ownedContacts(3);
            insert new List<Volunteer_Hours__c>{
                VolunteersTestData.newHours(people[0].Id, jobId(), 4),
                VolunteersTestData.newHours(people[1].Id, jobId(), 1)
            };
        }
        VolunteerLetterBatch.Request request = new VolunteerLetterBatch.Request();
        request.personIds = idsOf(people);
        request.letterType = VolunteerLetterTemplates.TYPE_HOURS_LETTER;
        request.fromDate = FROM_DATE;
        request.toDate = TO_DATE;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            VolunteerLetterBatch.generateLetters(new List<VolunteerLetterBatch.Request>{ request });
        }
        Test.stopTest();

        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId IN :request.personIds
                ],
                'The two people with hours get a letter; the third is skipped.'
            );
        }
    }

    @IsTest
    static void aPersonAccountLetterCountsTheAccountsHours() {
        Account person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = VolunteersTestData.personAccount('Mbeki');
            if (person != null) {
                update new Account(Id = person.Id, OwnerId = user(COORDINATOR).Id);
                Volunteer_Hours__c hours = VolunteersTestData.newHours(null, jobId(), 6);
                hours.Account__c = person.Id;
                insert hours;
            }
        }
        if (person == null) {
            // An org without person accounts (oi-test): this path runs on oi-pa.
            Assert.isFalse(
                OrgShapeDetector.hasPersonAccounts() &&
                OrgShapeDetector.creatablePersonRecordTypeId() != null,
                'A person account could have been made.'
            );
            return;
        }
        VolunteerLetterService.Letter letter;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            letter = VolunteerLetterService.mergeLetters(
                new List<Id>{ person.Id },
                templateId('Hours_Letter'),
                FROM_DATE,
                TO_DATE
            )[0];
        }
        Test.stopTest();

        Assert.isNull(letter.skipReason, 'A person account is a person: ' + letter.skipReason);
        Assert.isTrue(letter.body.contains(' 6 hours'), letter.body);
    }
}
