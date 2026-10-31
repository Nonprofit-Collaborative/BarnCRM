/**
 * Programs case notes (P-04, canonical model 29ZA1): private to their author, people above them and
 * Programs Admin (R-CN2); out of reach of Read Only (R-CN3); deleted when their person is erased,
 * which only someone who may delete every note can do (R-CN4); and an enrollment with notes kept
 * (R-CN1).
 */
@IsTest(testFor='ApexClass:ProgramsErasureExtension, ApexClass:CaseNoteSelector')
private class CaseNoteTest {
    private static final String ADMIN = 'Programs_Admin';
    private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith('Writer', STAFF);
        TestUsers.standardUserWith('Colleague', STAFF);
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        );
    }

    private static User writer() {
        return TestUsers.standardUserWith('Writer', STAFF);
    }

    private static User colleague() {
        return TestUsers.standardUserWith('Colleague', STAFF);
    }

    /** A person enrolled in a program, created by the admin. */
    private static Enrollment__c enrollment() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
        Contact person = HouseholdTestDataFactory.newContact('Pat', 'Rivera');
        insert person;
        Program__c pantry = new Program__c(Name = 'Pantry');
        insert pantry;
        Enrollment__c enrolled = new Enrollment__c(Program__c = pantry.Id, Contact__c = person.Id);
        insert enrolled;
        // Seen by all staff, as with Participant Privacy Shared (P-08), whatever the org's group.
        insert new Enrollment__Share(
            ParentId = enrolled.Id,
            UserOrGroupId = [SELECT Id FROM Group WHERE Type = 'Organization' LIMIT 1]
            .Id,
            AccessLevel = 'Edit',
            RowCause = Schema.Enrollment__Share.RowCause.Manual
        );
        return enrolled;
    }

    private static Case_Note__c note(Id enrollmentId, String subject) {
        return new Case_Note__c(
            Enrollment__c = enrollmentId,
            Subject__c = subject,
            Note__c = 'Text'
        );
    }

    @IsTest
    static void aNoteIsSeenByItsAuthorAndAdminButNotByColleaguesOrReaders() {
        Enrollment__c enrolled;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrolled = enrollment();
        }
        Case_Note__c written = note(enrolled.Id, 'First visit');
        User author = writer();
        System.runAs(author) {
            insert written;
        }

        Test.startTest();
        Integer byColleague;
        Integer byAdmin;
        Boolean readerCanRead;
        System.runAs(colleague()) {
            byColleague = [SELECT COUNT() FROM Case_Note__c WITH USER_MODE];
        }
        System.runAs(TestUsers.adminWith(ADMIN)) {
            byAdmin = [SELECT COUNT() FROM Case_Note__c WITH USER_MODE];
        }
        System.runAs(TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        )) {
            readerCanRead = Schema.SObjectType.Case_Note__c.isAccessible();
        }
        Test.stopTest();

        Case_Note__c saved = [
            SELECT Note_Date__c, Type__c, OwnerId
            FROM Case_Note__c
            WHERE Id = :written.Id
        ];
        Assert.areEqual(Date.today(), saved.Note_Date__c, 'Dated today by default.');
        Assert.areEqual('Check-in', saved.Type__c, 'A check-in by default.');
        Assert.areEqual(author.Id, saved.OwnerId, 'Owned by its author.');
        Assert.areEqual(0, byColleague, 'A colleague does not see it.');
        Assert.areEqual(1, byAdmin, 'Programs Admin sees it.');
        Assert.isFalse(readerCanRead, 'Read Only has no case notes.');
    }

    @IsTest
    static void anEnrollmentWithNotesIsKept() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Enrollment__c enrolled = enrollment();
            insert note(enrolled.Id, 'Kept');

            Test.startTest();
            Database.DeleteResult result = Database.delete(enrolled, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'Refused while it has notes.');
        }
    }

    @IsTest
    static void erasingThePersonDeletesTheirNotesAndKeepsTheEnrollment() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Enrollment__c enrolled = enrollment();
            insert new List<Case_Note__c>{ note(enrolled.Id, 'One'), note(enrolled.Id, 'Two') };

            Test.startTest();
            List<PersonErasure.Change> changes = new ProgramsErasureExtension()
                .erase(enrolled.Contact__c);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Case_Note__c], 'The notes are gone.');
            Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c], 'The enrollment stays.');
            Assert.areEqual(2, changes.size(), 'Deleted notes, kept enrollments.');
            Assert.areEqual(PersonErasure.DELETED, changes[0].action, 'Notes deleted.');
            Assert.areEqual(2, changes[0].count, 'Both.');
            Assert.areEqual(PersonErasure.KEPT, changes[1].action, 'Enrollment kept.');
            Assert.isTrue(
                new ProgramsErasureExtension().fieldsToKeep(Contact.SObjectType).isEmpty(),
                'Nothing kept on the person.'
            );
        }
    }

    @IsTest
    static void staffCannotEraseSomeoneWithNotes() {
        Enrollment__c enrolled;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrolled = enrollment();
        }
        System.runAs(colleague()) {
            insert note(enrolled.Id, 'By a colleague');
        }

        Test.startTest();
        String refusal;
        System.runAs(writer()) {
            try {
                new ProgramsErasureExtension().erase(enrolled.Contact__c);
            } catch (PersonErasure.ErasureException refused) {
                refusal = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(Label.Programs_Erase_NeedProgramsAdmin, refusal, 'Refused, with why.');
        Assert.areEqual(1, [SELECT COUNT() FROM Case_Note__c], 'Nothing was deleted.');
    }

    @IsTest
    static void someoneWithNoProgramsRecordsIsErasedWithNoChange() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Contact nobody = HouseholdTestDataFactory.newContact('No', 'Programs');
            insert nobody;

            Test.startTest();
            List<PersonErasure.Change> changes = new ProgramsErasureExtension().erase(nobody.Id);
            Test.stopTest();

            Assert.isTrue(changes.isEmpty(), 'Nothing to report.');
        }
    }
}
