/**
 * Household test data. Kept apart from the shared TestDataFactory so that the household
 * feature can add helpers without touching a file every other feature also edits.
 */
@IsTest
@NamespaceAccessible
public class HouseholdTestDataFactory {
    @NamespaceAccessible
    public static final String MODE_CONTACT = 'Contact';
    @NamespaceAccessible
    public static final String MODE_JUNCTION = 'Junction';

    /**
     * Org level settings with the shipped defaults, so that a test never depends on what
     * another test left behind.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c settings(String membershipMode) {
        BarnCRM_Settings__c record = BarnCRM_Settings__c.getOrgDefaults();
        record.Household_Membership_Mode__c = membershipMode;
        record.Auto_Create_Households__c = true;
        record.Delete_Empty_Households__c = true;
        record.Household_Name_Pattern__c = 'The {LastName} Family';
        record.Formal_Greeting_Pattern__c = '{Salutation} {FirstName} {LastName}';
        record.Informal_Greeting_Pattern__c = '{FirstName}';
        record.Include_Deceased_In_Name__c = false;
        return save(record);
    }

    /**
     * Junction mode with automatic household creation switched off.
     *
     * The tests that use this build their memberships by hand, which is how they say what
     * they are testing: who is in which household, and what a move or a merge does to that.
     * Automatic creation would give every person inserted by those tests a household of
     * their own first (R-H2, ADR-0037), so it is switched off rather than worked around.
     * The tests of automatic creation itself use the shipped settings.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c junctionSettingsWithoutAutomaticHouseholds() {
        BarnCRM_Settings__c record = settings(MODE_JUNCTION);
        record.Auto_Create_Households__c = false;
        return save(record);
    }

    /**
     * Saves the org level settings and forgets the cached copy, so that the next read sees
     * what was just written. Without this a test that changes a setting after something has
     * already read the settings in the same transaction is silently ignored: SettingsService
     * holds the first answer for the rest of the transaction.
     */
    public static BarnCRM_Settings__c save(BarnCRM_Settings__c record) {
        upsert record;
        SettingsService.clearCaches();
        return record;
    }

    @NamespaceAccessible
    public static Contact newContact(String firstName, String lastName) {
        return newContact('Ms.', firstName, lastName);
    }

    public static Contact newContact(String salutation, String firstName, String lastName) {
        return (Contact) TestDataFactory.pastDuplicateRules(
            new Contact(Salutation = salutation, FirstName = firstName, LastName = lastName)
        );
    }

    @NamespaceAccessible
    public static Account newHousehold(String name) {
        return (Account) TestDataFactory.pastDuplicateRules(
            new Account(
                Name = name,
                RecordTypeId = HouseholdService.householdRecordTypeId(),
                Custom_Name__c = false,
                Member_Count__c = 0
            )
        );
    }

    /**
     * Inserts households the way BarnCRM creates them for a person: through HouseholdWriter in
     * system mode, with its access checks, since no user is given the Household record type
     * (ADR-0141). Run it as the user the test is about; a plain `insert` of a
     * household in user mode is refused for anyone without the record type. Asserts that every
     * household was saved, and answers the same records, now with their Ids.
     */
    @NamespaceAccessible
    public static List<Account> insertHouseholds(List<Account> households) {
        List<Database.SaveResult> saves = HouseholdWriter.createHouseholdsForUser(households, null);
        for (Integer i = 0; i < saves.size(); i++) {
            Assert.isTrue(
                saves[i].isSuccess(),
                'Household ' + i + ' was saved: ' + HouseholdWriter.failureReason(saves[i])
            );
        }
        return households;
    }

    /** Named households, numbered from 1, inserted through HouseholdWriter as above. */
    @NamespaceAccessible
    public static List<Account> insertHouseholds(String namePrefix, Integer count) {
        List<Account> households = new List<Account>();
        for (Integer i = 1; i <= count; i++) {
            households.add(newHousehold(namePrefix + ' ' + i));
        }
        return insertHouseholds(households);
    }

    public static HouseholdService.Person person(
        String salutation,
        String firstName,
        String lastName,
        String role
    ) {
        HouseholdService.Person result = new HouseholdService.Person();
        result.salutation = salutation;
        result.firstName = firstName;
        result.lastName = lastName;
        result.role = role;
        return result;
    }

    /**
     * Maria Garcia and Wei Lee, the pair the admin guide walkthrough uses.
     */
    public static List<HouseholdService.Person> garciaAndLee() {
        return new List<HouseholdService.Person>{
            person('Ms.', 'Maria', 'Garcia', 'Head'),
            person('Mr.', 'Wei', 'Lee', 'Spouse or Partner')
        };
    }

    /**
     * A couple who share a surname, as David would enter them.
     */
    public static List<HouseholdService.Person> smithCouple() {
        return new List<HouseholdService.Person>{
            person('Mr.', 'John', 'Smith', 'Head'),
            person('Mrs.', 'Jane', 'Smith', 'Spouse or Partner')
        };
    }

    /**
     * A user with an ordinary standard profile and no packaged permission set at all: the
     * shape of user that a household save must still work for. Built by
     * `TestUsers.standardUser`.
     */
    public static User standardUser(String nickname) {
        return TestUsers.standardUser(nickname);
    }

    /**
     * Read access to the membership object and to the fields on it that the package's own
     * permission sets grant, and nothing else: no access is granted to any field on
     * Account, so a user holding this can open a household panel in junction mode and is
     * still a user who cannot read a person's deceased flag.
     *
     * The required lookup to the household is deliberately absent: a universally required
     * field carries no field level access row, and asking to insert one fails.
     */
    public static void grantMembershipRead(String name, Id userId) {
        grantMembership(name, userId, false);
    }

    /**
     * The same, with create access to the membership object and edit access to the same
     * fields: what a user needs to save a membership row at all, the platform enforcing
     * object and field access on the save itself. Still nothing on Account, so the upkeep
     * that save starts reads packaged Account fields this user cannot.
     */
    public static void grantMembershipCreate(String name, Id userId) {
        grantMembership(name, userId, true);
    }

    private static void grantMembership(String name, Id userId, Boolean mayCreate) {
        List<String> fields = new List<String>{
            'Account__c',
            'Contact__c',
            'End_Date__c',
            'Is_Primary__c',
            'Role__c',
            'Start_Date__c'
        };
        // Setup objects are saved on their own so that granting access and creating records
        // never mix in one transaction.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet grant = new PermissionSet(Name = name, Label = name);
            insert grant;
            insert new ObjectPermissions(
                ParentId = grant.Id,
                SobjectType = String.valueOf(Household_Member__c.SObjectType),
                PermissionsRead = true,
                PermissionsCreate = mayCreate
            );
            List<FieldPermissions> reads = new List<FieldPermissions>();
            for (String field : fields) {
                reads.add(
                    new FieldPermissions(
                        ParentId = grant.Id,
                        SobjectType = String.valueOf(Household_Member__c.SObjectType),
                        Field = String.valueOf(Household_Member__c.SObjectType) +
                            '.' +
                            NamespaceUtil.qualify(field),
                        PermissionsRead = true,
                        PermissionsEdit = mayCreate
                    )
                );
            }
            insert reads;
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = grant.Id);
        }
    }

    public static List<Contact> manyContacts(Integer howMany, String lastName) {
        List<Contact> result = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            result.add(newContact('Mx.', 'Person' + i, lastName + i));
        }
        return result;
    }
}
