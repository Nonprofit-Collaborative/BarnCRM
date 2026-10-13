/**
 * The org's coexistence mode: how BarnCRM behaves next to whatever is already installed
 * (plan Section 4.5). One org-level setting, proposed by detection and confirmed by an
 * administrator, changeable at any time.
 *
 * Every write goes through SettingsService so that it is cached, invalidated, and audited
 * the same way as every other setting (canonical model Section 12).
 */
@NamespaceAccessible
public with sharing class CoexistenceService {
    public static final String MODE_STANDALONE = 'Standalone';
    public static final String MODE_NPSP = 'NPSP';
    public static final String MODE_NONPROFIT_CLOUD = 'NonprofitCloud';

    public static final String MEMBERSHIP_CONTACT = 'Contact';
    public static final String MEMBERSHIP_JUNCTION = 'Junction';

    public static final String KEY_COEXISTENCE_MODE = 'Coexistence_Mode__c';
    public static final String KEY_MEMBERSHIP_MODE = 'Household_Membership_Mode__c';

    /** The custom permission that gates changing the mode. */
    public static final String MANAGE_SETTINGS = 'Manage_BarnCRM_Settings';

    private static final Set<String> VALID_MODES = new Set<String>{
        MODE_STANDALONE,
        MODE_NPSP,
        MODE_NONPROFIT_CLOUD
    };

    /**
     * The mode this org is running in, or null when nobody has confirmed one yet.
     */
    public static String getCurrentMode() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        String mode = settings == null ? null : settings.Coexistence_Mode__c;
        return String.isBlank(mode) ? null : mode;
    }

    /**
     * How household membership is stored, defaulting to contact mode when unset.
     */
    public static String getMembershipMode() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        String mode = settings == null ? null : settings.Household_Membership_Mode__c;
        return String.isBlank(mode) ? MEMBERSHIP_CONTACT : mode;
    }

    /**
     * Whether somebody has chosen how people belong to a household. Blank is the shipped
     * default, read as contact mode, and it is the only state detection is allowed to change.
     */
    public static Boolean membershipModeChosen() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings != null && String.isNotBlank(settings.Household_Membership_Mode__c);
    }

    /**
     * Set the mode from detection, but only when the org has not chosen one. An
     * administrator's choice is never overwritten. Returns the mode in force afterward.
     *
     * Nonprofit Cloud coexistence, and any org with Person Accounts, implies junction
     * membership: the person is an account, so contact mode cannot express a household. The
     * two values are written
     * together, in one save, so the org is never briefly in an impossible state. The
     * membership half is only proposed, like the rest: an administrator who already chose the
     * simple way keeps it, and Health Check says so if people stored as accounts appear.
     */
    public static String applyRecommendedIfUnset() {
        String current = getCurrentMode();
        if (String.isNotBlank(current)) {
            return current;
        }

        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        save(withMembership(recommended));
        return recommended;
    }

    /**
     * Set the mode explicitly, as the settings console and Health Check do.
     */
    public static void setMode(String mode) {
        if (String.isBlank(mode) || !VALID_MODES.contains(mode)) {
            throw new CoexistenceException(
                String.format(
                    System.Label.Core_CoexistenceMode_InvalidMode,
                    new List<Object>{ mode }
                )
            );
        }
        save(withMembership(mode));
    }

    /**
     * The modes this org is offered, in the order a person reads them
     * (ADR-0062). Standalone always; a mode named
     * after another Salesforce product only when detection finds that product, because Core
     * names no other product in an org that does not have it. The mode already saved is
     * always included, so a choice made earlier is never hidden from the person who made it.
     */
    public static List<String> availableModes(OrgShapeDetector.OrgShape shape) {
        String current = getCurrentMode();
        List<String> modes = new List<String>{ MODE_STANDALONE };
        if ((shape != null && shape.hasNpsp == true) || MODE_NPSP.equals(current)) {
            modes.add(MODE_NPSP);
        }
        if (
            (shape != null && shape.hasIndustriesNonprofit == true) ||
            MODE_NONPROFIT_CLOUD.equals(current)
        ) {
            modes.add(MODE_NONPROFIT_CLOUD);
        }
        return modes;
    }

    /** The same, for the shape detection reports for this org. */
    public static List<String> availableModes() {
        OrgShapeDetector.OrgShape shape;
        try {
            shape = OrgShapeDetector.detect();
        } catch (Exception e) {
            ErrorLogger.log(e, 'BarnCRM coexistence modes');
        }
        return availableModes(shape);
    }

    /**
     * The coexistence mode to write, with junction membership alongside it when the mode
     * or the org calls for that and nobody has chosen a way of belonging yet: Nonprofit Cloud
     * coexistence, or any mode in an org with Person Accounts. A choice already made is
     * left alone, whichever way it went: forcing the junction over an explicit choice would
     * also be the destructive switch the settings write refuses.
     */
    private static Map<String, Object> withMembership(String mode) {
        Map<String, Object> values = new Map<String, Object>{ KEY_COEXISTENCE_MODE => mode };
        Boolean needsJunction = MODE_NONPROFIT_CLOUD.equals(mode) || hasPersonAccounts();
        if (needsJunction && !membershipModeChosen()) {
            values.put(KEY_MEMBERSHIP_MODE, MEMBERSHIP_JUNCTION);
        }
        return values;
    }

    private static Boolean hasPersonAccounts() {
        try {
            OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
            return shape != null && shape.hasPersonAccounts == true;
        } catch (Exception e) {
            ErrorLogger.log(e, 'BarnCRM coexistence modes');
            return false;
        }
    }

    /**
     * Move household membership to the junction, which is what Person Accounts require.
     * Existing households are not touched: this changes how the next one is built. Refused,
     * with the reason, when people are linked straight to a household and would be stranded.
     */
    public static void applyJunctionMembership() {
        save(new Map<String, Object>{ KEY_MEMBERSHIP_MODE => MEMBERSHIP_JUNCTION });
    }

    /**
     * One save for every write here. A settings write the service refuses, including the
     * membership guard below, comes back as this class's own exception so that the Health
     * Check and Setup Assistant fix paths show the person the reason rather than a generic
     * failure.
     */
    private static void save(Map<String, Object> values) {
        try {
            SettingsService.saveValues(values);
        } catch (SettingsService.SettingsException refused) {
            throw new CoexistenceException(refused.getMessage());
        }
    }

    /**
     * Why a change of how people belong to a household must not happen, or null when it may.
     * SettingsService asks this on every write of the membership mode, whoever is writing.
     *
     * There is no migration between the two ways of belonging. Moving to the simple way
     * hides every membership record: the next upkeep counts those households as empty,
     * renames them, and deletes them if that setting is on. Moving to the flexible way
     * strands every person linked straight to a household account, because automatic
     * creation leaves such a person alone and the flexible way reads only membership
     * records. Either switch is allowed only while there is nobody to strand, which is what
     * a fresh org looks like, and what an org that has never used the other way looks like.
     */
    public static String membershipChangeRefusal(String fromMode, String toMode) {
        String current = String.isBlank(fromMode) ? MEMBERSHIP_CONTACT : fromMode;
        String wanted = String.isBlank(toMode) ? MEMBERSHIP_CONTACT : toMode;
        if (current.equals(wanted)) {
            return null;
        }
        if (MEMBERSHIP_CONTACT.equals(wanted)) {
            Integer hidden = countPeopleWithMembershipRecords();
            return hidden == 0
                ? null
                : String.format(
                      System.Label.Core_Coexistence_SwitchToContactRefused,
                      new List<Object>{ String.valueOf(hidden) }
                  );
        }
        Integer stranded = countPeopleLinkedWithoutMembershipRecords();
        return stranded == 0
            ? null
            : String.format(
                  System.Label.Core_Coexistence_SwitchToJunctionRefused,
                  new List<Object>{ String.valueOf(stranded) }
              );
    }

    /**
     * The three counts the guard and Health Check are built on. They are the whole of the
     * SOQL in this class, and they run in system mode under ADR-0021 for the same reason
     * the empty-household delete guard does: the answer has to describe the org, not the
     * reader. A count taken with the administrator's own sharing would read zero for rows
     * they cannot see, the switch would go through, and the rows this guard exists to
     * protect would be the ones lost. Only a number reaches the person, never a record, and
     * nothing typed by anybody enters the query.
     */

    /** People who belong to a household today through a membership record. */
    public static Integer countPeopleWithMembershipRecords() {
        Date today = Date.today();
        return [
            SELECT COUNT()
            FROM Household_Member__c
            WHERE End_Date__c = NULL OR End_Date__c > :today
            WITH SYSTEM_MODE
        ];
    }

    /**
     * People linked straight to a household account, the simple way, with no membership
     * record joining them to any household. Nobody to count when the org has no household
     * record type at all.
     */
    public static Integer countPeopleLinkedWithoutMembershipRecords() {
        Id householdRecordTypeId = HouseholdService.householdRecordTypeId();
        if (householdRecordTypeId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM Contact
            WHERE
                Account.RecordTypeId = :householdRecordTypeId
                AND Id NOT IN (SELECT Contact__c FROM Household_Member__c WHERE Contact__c != NULL)
            WITH SYSTEM_MODE
        ];
    }

    /**
     * People stored as accounts: accounts of a record type the org describes as a person
     * type. Zero in any org without Person Accounts, because there is no such record type.
     */
    public static Integer countPeopleStoredAsAccounts() {
        return countPeopleStoredAsAccounts(null);
    }

    /**
     * The same, stopping at `cap` when one is given, so that Health Check on an org with a
     * great many person accounts does not count every one of them against the query row limit.
     */
    public static Integer countPeopleStoredAsAccounts(Integer cap) {
        Set<Id> personTypes = OrgShapeDetector.personAccountRecordTypeIds();
        if (personTypes == null || personTypes.isEmpty()) {
            return 0;
        }
        if (cap != null) {
            return [
                SELECT COUNT()
                FROM Account
                WHERE RecordTypeId IN :personTypes
                WITH SYSTEM_MODE
                LIMIT :cap
            ];
        }
        return [SELECT COUNT() FROM Account WHERE RecordTypeId IN :personTypes WITH SYSTEM_MODE];
    }

    /**
     * Change the mode on behalf of the person asking, which is what the settings console and
     * Health Check do. Unlike setMode, this refuses anyone without the Manage BarnCRM
     * Settings permission: the coexistence mode governs how the whole package behaves, so it
     * is an administrator's decision even where the calling code forgot to say so.
     *
     * Nonprofit Cloud brings junction household membership with it, in the same audited
     * save, because in a Person Accounts org the person is an account and contact membership
     * cannot express a household.
     */
    @NamespaceAccessible
    public static void applyMode(String mode) {
        if (!FeatureManagement.checkPermission(MANAGE_SETTINGS)) {
            throw new CoexistenceException(System.Label.Core_HealthCheck_PermissionRequired);
        }
        setMode(mode);
    }

    /** Raised when a value that is not a coexistence mode is offered as one. */
    public class CoexistenceException extends Exception {
    }
}
