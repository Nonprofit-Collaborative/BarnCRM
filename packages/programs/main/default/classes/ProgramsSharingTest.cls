/**
 * Participant privacy (P-08, canonical model R-EN7 and R-SD6): every enrollment and delivery is
 * shared with the Programs Participant Records group; Shared, the default, puts All Internal Users
 * in the group, Private takes them out; the save is audited and refused to anyone who cannot
 * manage settings; the hourly check repairs the group; and the batch shares older records.
 *
 * The group is real org data. Only the one test that writes it turns group writes on, so tests
 * running in parallel never lock its row.
 */
@IsTest(
    testFor='ApexClass:ProgramsSharing, ApexClass:ProgramsSharingBatch, ApexClass:ProgramsSharingHandler, ApexClass:ProgramsSettingsController'
)
private class ProgramsSharingTest {
    private static final String ADMIN = 'Programs_Admin';
    private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith('Writer', STAFF);
        TestUsers.standardUserWith('Colleague', STAFF);
    }

    private static User admin() {
        return TestUsers.adminWith(ADMIN);
    }

    private static User writer() {
        return TestUsers.standardUserWith('Writer', STAFF);
    }

    private static User colleague() {
        return TestUsers.standardUserWith('Colleague', STAFF);
    }

    /** A program and service, made by the admin; the people are contacts. */
    private static Service__c service() {
        Service__c meal;
        System.runAs(admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            TestDataFactory.saveSettings(settings);
            Program__c pantry = new Program__c(Name = 'Pantry');
            insert pantry;
            meal = new Service__c(Name = 'Meal', Program__c = pantry.Id);
            insert meal;
        }
        return meal;
    }

    /** The author adds a person, enrolls them and records one delivery to them. */
    private static Enrollment__c enrollAndDeliver(User author, Service__c meal) {
        Contact person = HouseholdTestDataFactory.newContact('Pat', 'Rivera');
        Enrollment__c enrolled = new Enrollment__c(Program__c = meal.Program__c);
        System.runAs(author) {
            insert person;
            enrolled.Contact__c = person.Id;
            insert enrolled;
            insert new Service_Delivery__c(
                Service__c = meal.Id,
                Contact__c = person.Id,
                Enrollment__c = enrolled.Id
            );
        }
        return enrolled;
    }

    private static Integer seenBy(User viewer) {
        Integer seen;
        System.runAs(viewer) {
            seen =
                [SELECT COUNT() FROM Enrollment__c WITH USER_MODE] +
                [SELECT COUNT() FROM Service_Delivery__c WITH USER_MODE];
        }
        return seen;
    }

    private static Id groupId() {
        return [SELECT Id FROM Group WHERE DeveloperName = :ProgramsSharing.GROUP_NAME].Id;
    }

    private static Id everyone() {
        return [SELECT Id FROM Group WHERE Type = 'Organization' LIMIT 1].Id;
    }

    private static Integer everyoneInGroup() {
        return [
            SELECT COUNT()
            FROM GroupMember
            WHERE GroupId = :groupId() AND UserOrGroupId = :everyone()
        ];
    }

    @IsTest
    static void newRecordsAreSharedWithTheGroup() {
        // runs-as: deploying user (each write runs as its own user; this only reads share rows)
        Service__c meal = service();

        Test.startTest();
        Enrollment__c enrolled = enrollAndDeliver(writer(), meal);
        Test.stopTest();

        String reason = Schema.Enrollment__Share.RowCause.Programs_Participants__c;
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Enrollment__Share
                WHERE ParentId = :enrolled.Id AND UserOrGroupId = :groupId() AND RowCause = :reason
            ],
            'The enrollment is shared with the group.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Service_Delivery__Share
                WHERE UserOrGroupId = :groupId() AND AccessLevel = 'Edit'
            ],
            'The delivery is shared with the group, Read/Write.'
        );
    }

    @IsTest
    static void aLoadOfTwoHundredIsSharedInOneGo() {
        // runs-as: deploying user (each write runs as staff; this only reads share rows)
        Service__c meal = service();
        Integer howMany = 200;

        Test.startTest();
        System.runAs(writer()) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < howMany; i++) {
                people.add(HouseholdTestDataFactory.newContact('Pat', 'Rivera' + i));
            }
            insert people;
            List<Enrollment__c> enrollments = new List<Enrollment__c>();
            for (Contact person : people) {
                enrollments.add(
                    new Enrollment__c(Program__c = meal.Program__c, Contact__c = person.Id)
                );
            }
            insert enrollments;
            List<Service_Delivery__c> deliveries = new List<Service_Delivery__c>();
            for (Enrollment__c enrolled : enrollments) {
                deliveries.add(
                    new Service_Delivery__c(
                        Service__c = meal.Id,
                        Contact__c = enrolled.Contact__c,
                        Enrollment__c = enrolled.Id
                    )
                );
            }
            insert deliveries;
        }
        Test.stopTest();

        Id participants = groupId();
        Assert.areEqual(
            howMany,
            [
                SELECT COUNT()
                FROM Enrollment__Share
                WHERE
                    UserOrGroupId = :participants
                    AND RowCause = :Schema.Enrollment__Share.RowCause.Programs_Participants__c
            ],
            'Every enrollment of a 200 record load is shared with the group.'
        );
        Assert.areEqual(
            howMany,
            [
                SELECT COUNT()
                FROM Service_Delivery__Share
                WHERE
                    UserOrGroupId = :participants
                    AND RowCause = :Schema.Service_Delivery__Share.RowCause.Programs_Participants__c
            ],
            'And every delivery.'
        );
    }

    @IsTest
    static void thePresetDecidesWhoSeesAndTheHourlyCheckRepairsTheGroup() {
        ProgramsSharing.writeGroupInTests = true;
        User author = writer();
        User other = colleague();
        enrollAndDeliver(author, service());
        System.runAs(admin()) {
            ProgramsSharing.applyPreset();
        }
        Assert.areEqual(1, everyoneInGroup(), 'Shared: All Internal Users are in the group.');
        Assert.areEqual(2, seenBy(other), 'Shared: a colleague sees both records.');

        Test.startTest();
        ProgramsSettingsController.Settings settings;
        System.runAs(admin()) {
            settings = ProgramsSettingsController.savePrivacy(true);
        }
        Test.stopTest();

        Assert.areEqual('Private', settings.participantPrivacy, 'The page shows Private.');
        Assert.areEqual(0, everyoneInGroup(), 'Private: All Internal Users are taken out.');
        Assert.areEqual(0, seenBy(other), 'Private: a colleague sees neither.');
        Assert.areEqual(2, seenBy(author), 'The owner still sees both.');
        Assert.areEqual(2, seenBy(admin()), 'Programs Admin sees both.');
        Setting_Change__c change = [
            SELECT Old_Value__c, New_Value__c
            FROM Setting_Change__c
            WHERE Setting_Name__c = :ProgramsSharing.SETTING_NAME
        ];
        Assert.areEqual('Shared', change.Old_Value__c, 'Audited from Shared.');
        Assert.areEqual('Private', change.New_Value__c, 'Audited to Private.');

        // Someone puts All Internal Users back by hand; the hourly check takes them out again.
        System.runAs(admin()) {
            insert new GroupMember(GroupId = groupId(), UserOrGroupId = everyone());
            ProgramsAccessSync.syncOnce();
        }
        Assert.areEqual(0, everyoneInGroup(), 'Back in step with Private.');
    }

    @IsTest
    static void savingTheSamePresetChangesNothing() {
        System.runAs(admin()) {
            Test.startTest();
            ProgramsSettingsController.Settings settings = ProgramsSettingsController.savePrivacy(
                false
            );
            Test.stopTest();

            Assert.areEqual('Shared', settings.participantPrivacy, 'Shared by default.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Setting_Change__c
                    WHERE Setting_Name__c = :ProgramsSharing.SETTING_NAME
                ],
                'Nothing to audit.'
            );
        }
    }

    @IsTest
    static void onlyASettingsManagerMaySave() {
        String refusal;
        System.runAs(writer()) {
            Test.startTest();
            try {
                ProgramsSettingsController.savePrivacy(true);
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();
        }

        Assert.areEqual(Label.Programs_Settings_NoAccess, refusal, 'Refused, with why.');
        Assert.isFalse(ProgramsSharing.isPrivate(), 'Still Shared.');
    }

    @IsTest
    static void theBatchSharesARecordThatHasNoShare() {
        // runs-as: deploying user (the batch runs in system mode; the records are made as staff)
        Enrollment__c enrolled = enrollAndDeliver(writer(), service());
        delete [
            SELECT Id
            FROM Enrollment__Share
            WHERE ParentId = :enrolled.Id AND UserOrGroupId = :groupId()
        ];

        Test.startTest();
        Database.executeBatch(new ProgramsSharingBatch(Enrollment__c.SObjectType));
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Enrollment__Share
                WHERE ParentId = :enrolled.Id AND UserOrGroupId = :groupId()
            ],
            'Shared again, once.'
        );
    }
}
