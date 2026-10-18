/**
 * Volunteers test data: settings, people, jobs, shifts and hours, built the same way by every
 * Volunteers test. Test only, used inside the package.
 */
@IsTest
public class VolunteersTestData {
    public static final String ADMIN = 'Volunteers_Admin';
    public static final Datetime SHIFT_START = Datetime.newInstance(2026, 3, 14, 9, 0, 0);
    /** The Core set a staff member holds, for contacts and accounts. */
    public static final String CORE_STAFF = 'BarnCRM_Staff';

    /**
     * A staff member who enters hours and nothing more: Standard User, BarnCRM Staff, and a
     * test-only permission set to read jobs and create and edit their own hours. No Manage
     * Volunteers, so the permission is really absent (the module's Staff set ships with the
     * permission sets, PR7).
     */
    public static User hoursStaffer(String lastName) {
        User person = TestUsers.standardUserWith(lastName, new List<String>{ CORE_STAFF });
        grant(person.Id, false, false);
        return person;
    }

    /**
     * A coordinator who holds Manage Volunteers and may see every entry but edit none: the
     * case where an approval has to report an entry rather than fail the whole call.
     */
    public static User readOnlyCoordinator(String lastName) {
        User person = TestUsers.standardUserWith(lastName, new List<String>{ CORE_STAFF });
        grant(person.Id, true, true);
        return person;
    }

    private static void grant(Id userId, Boolean readOnlyWithManage, Boolean viewAll) {
        String hoursObject = Schema.SObjectType.Volunteer_Hours__c.getName();
        String jobObject = Schema.SObjectType.Volunteer_Job__c.getName();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String name = 'Barn_Volunteers_Test_' + Math.abs(Crypto.getRandomInteger());
            PermissionSet access = new PermissionSet(Name = name, Label = name);
            insert as system access;
            insert as system new List<ObjectPermissions>{
                new ObjectPermissions(
                    ParentId = access.Id,
                    SobjectType = jobObject,
                    PermissionsRead = true
                ),
                new ObjectPermissions(
                    ParentId = access.Id,
                    SobjectType = hoursObject,
                    PermissionsRead = true,
                    PermissionsCreate = !readOnlyWithManage,
                    PermissionsEdit = !readOnlyWithManage,
                    PermissionsViewAllRecords = viewAll
                )
            };
            List<FieldPermissions> fields = new List<FieldPermissions>();
            for (
                Schema.SObjectField field : new List<Schema.SObjectField>{
                    Volunteer_Hours__c.Contact__c,
                    Volunteer_Hours__c.Volunteer_Job__c,
                    Volunteer_Hours__c.Rejection_Reason__c,
                    Volunteer_Hours__c.Approved_By__c,
                    Volunteer_Hours__c.Approved_Date__c,
                    Volunteer_Hours__c.Household__c
                }
            ) {
                fields.add(
                    new FieldPermissions(
                        ParentId = access.Id,
                        SobjectType = hoursObject,
                        Field = hoursObject + '.' + field.getDescribe().getName(),
                        PermissionsRead = true,
                        PermissionsEdit = !readOnlyWithManage &&
                            field != Volunteer_Hours__c.Approved_By__c &&
                            field != Volunteer_Hours__c.Approved_Date__c &&
                            field != Volunteer_Hours__c.Household__c
                    )
                );
            }
            insert as system fields;
            if (readOnlyWithManage) {
                insert as system new SetupEntityAccess(
                    ParentId = access.Id,
                    SetupEntityId = [
                        SELECT Id
                        FROM CustomPermission
                        WHERE DeveloperName = :VolunteerHoursService.MANAGE_PERMISSION
                        WITH SYSTEM_MODE
                        LIMIT 1
                    ]
                    .Id
                );
            }
            insert as system new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = access.Id
            );
        }
    }

    /** Contact membership mode with automatic households off: people are made as each test says. */
    public static void contactModeWithoutAutomaticHouseholds() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
    }

    /** Saves the Volunteers settings as an administrator would, and forgets the cached copy. */
    public static void volunteerSettings(
        Boolean hoursRequireApproval,
        Boolean attendanceCreatesHours
    ) {
        OrgSettingsSystemWriter.save(
            Volunteer_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Volunteer_Settings__c.Hours_Require_Approval__c => hoursRequireApproval,
                Volunteer_Settings__c.Attendance_Creates_Hours__c => attendanceCreatesHours
            }
        );
        SettingsService.clearCaches();
    }

    /** Saves how many weeks ahead recurring schedules keep their shifts (V-07). */
    public static void shiftHorizonWeeks(Integer weeks) {
        OrgSettingsSystemWriter.save(
            Volunteer_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Volunteer_Settings__c.Shift_Horizon_Weeks__c => weeks
            }
        );
        SettingsService.clearCaches();
    }

    /** An active schedule from 9:00 to 12:00 on the given days, every week, four places. */
    public static Shift_Schedule__c newSchedule(Id jobId, String weekdays, Date startDate) {
        return new Shift_Schedule__c(
            Name = 'Saturday sorting',
            Job__c = jobId,
            Weekdays__c = weekdays,
            Every_N_Weeks__c = 1,
            Start_Time__c = Time.newInstance(9, 0, 0, 0),
            End_Time__c = Time.newInstance(12, 0, 0, 0),
            Start_Date__c = startDate,
            Volunteers_Needed__c = 4,
            Active__c = true
        );
    }

    public static Account household(String name) {
        Account record = HouseholdTestDataFactory.newHousehold(name);
        insert record;
        return record;
    }

    /** A contact, in the given household when one is named (contact membership mode). */
    public static Contact contact(String lastName, Id householdId) {
        Contact record = HouseholdTestDataFactory.newContact('Ana', lastName);
        record.AccountId = householdId;
        insert record;
        return record;
    }

    public static List<Contact> contacts(Integer howMany) {
        List<Contact> records = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            records.add(HouseholdTestDataFactory.newContact('Vol', 'Unteer' + i));
        }
        insert records;
        return records;
    }

    /** A person held as an account, or null in an org without person accounts. */
    public static Account personAccount(String lastName) {
        if (!OrgShapeDetector.hasPersonAccounts()) {
            return null;
        }
        // A person type the running user is given: one they are not is refused on insert.
        Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
        if (personType == null) {
            return null;
        }
        Account person = new Account();
        person.put('LastName', lastName);
        person.put('RecordTypeId', personType);
        insert person;
        return person;
    }

    public static Volunteer_Job__c job(String name) {
        Volunteer_Job__c record = new Volunteer_Job__c(Name = name, Active__c = true);
        insert record;
        return record;
    }

    public static Volunteer_Shift__c newShift(Id jobId, Datetime startTime, Integer hours) {
        return new Volunteer_Shift__c(
            Name = 'Shift',
            Volunteer_Job__c = jobId,
            Start_Time__c = startTime,
            End_Time__c = startTime.addHours(hours),
            Volunteers_Needed__c = 4,
            Status__c = 'Open'
        );
    }

    public static Volunteer_Shift__c shift(Id jobId) {
        Volunteer_Shift__c record = newShift(jobId, SHIFT_START, 3);
        insert record;
        return record;
    }

    public static Volunteer_Hours__c newHours(Id contactId, Id jobId, Decimal hours) {
        return new Volunteer_Hours__c(
            Contact__c = contactId,
            Volunteer_Job__c = jobId,
            Date_Worked__c = Date.newInstance(2026, 3, 14),
            Hours__c = hours
        );
    }

    public static Volunteer_Signup__c newSignup(Id shiftId, Id contactId) {
        return new Volunteer_Signup__c(
            Volunteer_Shift__c = shiftId,
            Contact__c = contactId,
            Status__c = 'Signed up'
        );
    }
}
