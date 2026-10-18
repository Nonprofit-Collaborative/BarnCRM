/**
 * Volunteers test data: settings, people, jobs, shifts and hours, built the same way by every
 * Volunteers test. Test only, used inside the package.
 */
@IsTest
public class VolunteersTestData {
    public static final String ADMIN = 'Volunteers_Admin';
    public static final Datetime SHIFT_START = Datetime.newInstance(2026, 3, 14, 9, 0, 0);

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
