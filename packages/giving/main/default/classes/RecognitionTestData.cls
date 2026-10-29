/**
 * The records the soft credit, tribute, and matching gift tests need.
 *
 * The Garcia family is the household these features are documented with, so it is the household
 * they are tested with: Ana Garcia gives, Luis Garcia is recognized, and Riverbend Manufacturing
 * is the employer that matches.
 *
 * This is deliberately a small local factory rather than an addition to the Giving package's
 * shared factory: it builds only what recognition needs, and it does not have to be kept in step
 * with a feature it does not test.
 */
@IsTest
public class RecognitionTestData {
    public static final String HOUSEHOLD_RECORD_TYPE = 'Household';

    /**
     * Writes the giving setting that decides whether household members are credited
     * automatically.
     */
    public static void setAutomaticHouseholdCredits(Boolean enabled) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Automatic_Household_Soft_Credits__c = enabled;
        upsert settings;
    }

    /**
     * Switches the org to junction membership, the mode a Person Account org runs in, with
     * automatic household creation off.
     *
     * The tests that use this build the household by hand: who is in the Garcia household is
     * what they are about. Automatic creation would first give every person they insert a
     * household of their own (R-H2, ADR-0037), and the gift would then be credited within that
     * one, so it is switched off rather than worked around, as the Core household tests do.
     */
    public static void useJunctionMembership() {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Household_Membership_Mode__c = 'Junction';
        settings.Auto_Create_Households__c = false;
        upsert settings;
        SettingsService.clearCaches();
    }

    public static Account household(String name) {
        Account record = new Account(Name = name);
        // No user is given the Household record type (ADR-0141), so it is never "available":
        // look it up by name and insert in system mode.
        Id recordTypeId = HouseholdService.householdRecordTypeId();
        if (recordTypeId != null) {
            record.RecordTypeId = recordTypeId;
        }
        Database.insert(record, AccessLevel.SYSTEM_MODE);
        return record;
    }

    public static Account organization(String name) {
        Account record = AccountKindsTestData.organization(name);
        insert record;
        return record;
    }

    public static Contact person(String firstName, String lastName, Id householdId) {
        Contact record = new Contact(FirstName = firstName, LastName = lastName);
        if (householdId != null) {
            record.AccountId = householdId;
        }
        insert record;
        return record;
    }

    public static Household_Member__c membership(Id householdId, Id contactId, String role) {
        // Household__c is the household; Account__c is the person, for a Person Account org.
        Household_Member__c member = new Household_Member__c(
            Household__c = householdId,
            Contact__c = contactId,
            Role__c = role
        );
        insert member;
        return member;
    }

    public static Gift__c newGift(Id donorContactId, Id donorAccountId, Decimal amount) {
        Gift__c gift = new Gift__c(
            Donor_Contact__c = donorContactId,
            Donor_Account__c = donorAccountId,
            Amount__c = amount,
            Gift_Date__c = Date.today(),
            Type__c = 'Check',
            Status__c = 'Received'
        );
        return gift;
    }

    public static Gift__c gift(Id donorContactId, Id donorAccountId, Decimal amount) {
        GivingTestDataFactory.ensureDefaultFund();
        Gift__c gift = newGift(donorContactId, donorAccountId, amount);
        insert gift;
        return gift;
    }

    public static Soft_Credit__c manualCredit(
        Id giftId,
        Id contactId,
        String role,
        Decimal amount
    ) {
        Soft_Credit__c credit = new Soft_Credit__c(
            Gift__c = giftId,
            Contact__c = contactId,
            Role__c = role,
            Amount__c = amount,
            Is_Automatic__c = false
        );
        insert credit;
        return credit;
    }

    public static Tribute__c tribute(Id giftId, String tributeType, String honoreeName) {
        return new Tribute__c(
            Gift__c = giftId,
            Type__c = tributeType,
            Honoree_Name__c = honoreeName
        );
    }

    public static List<Soft_Credit__c> creditsFor(Id giftId) {
        return [
            SELECT Id, Contact__c, Account__c, Role__c, Amount__c, Percent__c, Is_Automatic__c
            FROM Soft_Credit__c
            WHERE Gift__c = :giftId
            WITH SYSTEM_MODE
            ORDER BY Name
        ];
    }

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null || !info.isAvailable() ? null : info.getRecordTypeId();
    }
}
