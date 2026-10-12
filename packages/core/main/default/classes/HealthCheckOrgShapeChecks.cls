/**
 * The Health Check questions about what this org is: what is installed alongside BarnCRM,
 * which coexistence mode that implies, and whether the settings match it
 * (plan Section 4.8, feature C-11).
 *
 * These checks are the ones that run for everybody, because none of them asks a question
 * about other people. HealthCheckService.steps() decides the order they are read in; this
 * class decides what each of them says.
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0039 moved
 * it here: same keys, same severities, same categories, same labels, same fix targets.
 */
public with sharing class HealthCheckOrgShapeChecks {
    /**
     * An Apex class the Connect package ships, used to tell whether Connect is installed
     * without referencing it at compile time. It is the class Core already discovers for
     * Connect's Health Check findings (`HealthCheckExtensions.EXTENSION_CLASSES`, ADR-0057),
     * so the name is a contract Connect keeps anyway.
     */
    private static final String CONNECT_MARKER_CLASS = 'ConnectHealthCheckExtension';

    /** Set by tests to see Connect as installed (true) or absent (false) without the package. */
    @TestVisible
    private static Boolean connectInstalledOverride;

    /** Whether Connect is installed, looked up once per transaction. */
    private static Boolean connectInstalled;

    /** What this org has installed, and the mode that shape recommends. */
    public class OrgShapeCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return orgShapeFinding(OrgShapeDetector.detect());
        }
    }

    /** Whether the coexistence mode in settings is the one the org shape recommends. */
    public class CoexistenceModeCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return coexistenceModeFinding();
        }
    }

    /** Whether household membership can work at all in a Person Accounts org. */
    public class MembershipModeCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return membershipModeFinding(OrgShapeDetector.detect());
        }
    }

    /** Whether household membership exists that the way of belonging in force cannot see. */
    public class MembershipDataCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return membershipDataFinding();
        }
    }

    /** Whether a new person in junction mode is actually given a household. */
    public class HouseholdCreationCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return householdCreationFinding();
        }
    }

    /** How many households here are already the Nonprofit Cloud native ones. */
    public class NativeHouseholdsCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return nativeHouseholdsFinding(OrgShapeDetector.detect());
        }
    }

    /** How many Accounts are a native household and a BarnCRM household at once. */
    public class NativeHouseholdCollisionCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return nativeHouseholdCollisionFinding();
        }
    }

    /** Whether an org with Industries objects has the Connect module that mirrors to them. */
    public class ConnectModuleCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return connectModuleFinding(OrgShapeDetector.detect());
        }
    }

    /** Whether this org runs multi-currency, which v1 does not support. */
    public class MultiCurrencyCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return multiCurrencyFinding(OrgShapeDetector.detect());
        }
    }

    /**
     * What was found, as a sentence an administrator can read out loud.
     *
     * @param shape the detected org shape, or null when it could not be read
     * @return the sentence, never blank
     */
    public static String detectedSummary(OrgShapeDetector.OrgShape shape) {
        if (shape == null) {
            return System.Label.Core_HealthCheck_NothingDetected;
        }

        List<String> detected = new List<String>();
        if (shape.hasPersonAccounts == true) {
            detected.add(System.Label.Core_HealthCheck_PersonAccountsDetected);
        }
        if (shape.hasIndustriesNonprofit == true) {
            detected.add(System.Label.Core_HealthCheck_IndustriesDetected);
        }
        if (shape.hasNpsp == true) {
            detected.add(System.Label.Core_HealthCheck_NpspDetected);
        }
        if (shape.hasSalesCloudObjects == true) {
            detected.add(System.Label.Core_HealthCheck_SalesObjectsDetected);
        }
        if (detected.isEmpty()) {
            return System.Label.Core_HealthCheck_NothingDetected;
        }
        return String.join(detected, '. ') + '.';
    }

    private static HealthCheckService.Finding orgShapeFinding(OrgShapeDetector.OrgShape shape) {
        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        String detail = String.format(
            System.Label.Core_HealthCheck_OrgShapeDetail,
            new List<Object>{ detectedSummary(shape), HealthCheckService.modeLabel(recommended) }
        );
        return new HealthCheckService.Finding(
            'org_shape',
            System.Label.Core_HealthCheck_OrgShapeTitle,
            detail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    private static HealthCheckService.Finding coexistenceModeFinding() {
        String recommended = OrgShapeDetector.recommendedCoexistenceMode();
        String current = CoexistenceService.getCurrentMode();

        if (String.isBlank(current)) {
            String detail = String.format(
                System.Label.Core_HealthCheck_ModeUnsetDetail,
                new List<Object>{
                    HealthCheckService.modeLabel(CoexistenceService.MODE_STANDALONE),
                    HealthCheckService.modeLabel(recommended)
                }
            );
            return new HealthCheckService.Finding(
                    'coexistence_mode_unset',
                    System.Label.Core_HealthCheck_ModeUnsetTitle,
                    detail,
                    HealthCheckService.SEVERITY_WARNING,
                    HealthCheckService.CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_UseRecommendedFix,
                    HealthCheckService.FIX_APPLY_RECOMMENDED_MODE
                );
        }

        if (!current.equals(recommended)) {
            String detail = String.format(
                System.Label.Core_HealthCheck_ModeMismatchDetail,
                new List<Object>{
                    HealthCheckService.modeLabel(current),
                    HealthCheckService.modeLabel(recommended)
                }
            );
            return new HealthCheckService.Finding(
                    'coexistence_mode_mismatch',
                    System.Label.Core_HealthCheck_ModeMismatchTitle,
                    detail,
                    HealthCheckService.SEVERITY_WARNING,
                    HealthCheckService.CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_UseRecommendedFix,
                    HealthCheckService.FIX_APPLY_RECOMMENDED_MODE
                );
        }

        String matchDetail = String.format(
            System.Label.Core_HealthCheck_ModeMatchDetail,
            new List<Object>{ HealthCheckService.modeLabel(current) }
        );
        return new HealthCheckService.Finding(
            'coexistence_mode_match',
            System.Label.Core_HealthCheck_ModeMatchTitle,
            matchDetail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    /**
     * Person Accounts with the simple way of belonging. An org that has never chosen a way
     * of belonging is told, as an error, that the simple default does not fit. An org whose
     * administrator chose the simple way on purpose is left alone while everyone is stored
     * as a contact, and warned, with the count, once people stored as accounts appear: those
     * people cannot join a household the simple way.
     */
    private static HealthCheckService.Finding membershipModeFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.hasPersonAccounts != true) {
            return null;
        }
        if (CoexistenceService.MEMBERSHIP_JUNCTION.equals(CoexistenceService.getMembershipMode())) {
            return null;
        }

        if (!CoexistenceService.membershipModeChosen()) {
            return new HealthCheckService.Finding(
                    'membership_mode_person_accounts',
                    System.Label.Core_HealthCheck_MembershipTitle,
                    System.Label.Core_HealthCheck_MembershipDetail,
                    HealthCheckService.SEVERITY_ERROR,
                    HealthCheckService.CATEGORY_ORG_SHAPE
                )
                .withFix(
                    System.Label.Core_HealthCheck_MembershipFix,
                    HealthCheckService.FIX_APPLY_JUNCTION_MEMBERSHIP
                );
        }

        Integer asAccounts = CoexistenceService.countPeopleStoredAsAccounts();
        if (asAccounts <= 0) {
            return null;
        }
        List<Object> count = new List<Object>{ String.valueOf(asAccounts) };
        return new HealthCheckService.Finding(
                'membership_mode_people_as_accounts',
                String.format(System.Label.Core_HealthCheck_PeopleAsAccountsTitle, count),
                String.format(System.Label.Core_HealthCheck_PeopleAsAccountsDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_ORG_SHAPE
            )
            .withFix(
                System.Label.Core_HealthCheck_MembershipFix,
                HealthCheckService.FIX_APPLY_JUNCTION_MEMBERSHIP
            );
    }

    /**
     * Household membership the way of belonging in force cannot see. The settings write
     * refuses the switch that would cause this, so it is reached only by data that arrived
     * another way: a membership record loaded into an org on the simple way, or a person
     * linked straight to a household in an org on the flexible way. It is an error because
     * it is silent otherwise: the households simply read as empty, or the people as
     * belonging nowhere, and nothing else says why.
     */
    private static HealthCheckService.Finding membershipDataFinding() {
        Boolean junction = CoexistenceService.MEMBERSHIP_JUNCTION.equals(
            CoexistenceService.getMembershipMode()
        );
        Integer unseen = junction
            ? CoexistenceService.countPeopleLinkedWithoutMembershipRecords()
            : CoexistenceService.countPeopleWithMembershipRecords();
        if (unseen <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(unseen) };
        String detail = String.format(
            junction
                ? System.Label.Core_HealthCheck_MembershipHiddenByJunctionDetail
                : System.Label.Core_HealthCheck_MembershipHiddenByContactDetail,
            count
        );
        return new HealthCheckService.Finding(
                'membership_data_hidden',
                System.Label.Core_HealthCheck_MembershipHiddenTitle,
                detail,
                HealthCheckService.SEVERITY_ERROR,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_MembershipHiddenFix,
                HealthCheckService.SECTION_HOUSEHOLDS
            );
    }

    /**
     * The state this finding exists for: household membership is on the junction, and
     * automatic creation is off, so no new person gets a household and nothing else says so
     * (ADR-0037).
     *
     * It is an error rather than a warning because it is silent by construction. Nothing
     * fails, nothing is logged, and the damage is only visible later, in the people saved
     * while it was true. Only junction mode is reported: contact mode with automatic
     * creation off still leaves the household field on the person, where its being empty is
     * there to see, and junction mode has no such field to notice.
     */
    private static HealthCheckService.Finding householdCreationFinding() {
        if (
            !CoexistenceService.MEMBERSHIP_JUNCTION.equals(CoexistenceService.getMembershipMode())
        ) {
            return null;
        }
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        if (settings != null && settings.Auto_Create_Households__c == true) {
            return null;
        }

        return new HealthCheckService.Finding(
                'household_creation_disabled',
                System.Label.Core_HealthCheck_NoHouseholdCreationTitle,
                System.Label.Core_HealthCheck_NoHouseholdCreationDetail,
                HealthCheckService.SEVERITY_ERROR,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_NoHouseholdCreationFix,
                HealthCheckService.FIX_ENABLE_AUTOMATIC_HOUSEHOLDS
            );
    }

    /**
     * How many households here are already the Salesforce Nonprofit Cloud way: an Account
     * carrying a native household group. Informational, because it is not a problem, it is
     * mutual exclusion working (product-plan Section 11.2 item 9): BarnCRM leaves these
     * households alone rather than renaming, re-greeting, or re-addressing them.
     */
    private static HealthCheckService.Finding nativeHouseholdsFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.hasNativeHouseholdGroups != true) {
            return null;
        }
        String detail = shape.nativeHouseholdGroupCount != null
            ? String.format(
                  System.Label.Core_HealthCheck_NativeHouseholdsDetail,
                  new List<Object>{ String.valueOf(shape.nativeHouseholdGroupCount) }
              )
            : System.Label.Core_HealthCheck_NativeHouseholdsUnknownDetail;
        return new HealthCheckService.Finding(
            'native_households',
            System.Label.Core_HealthCheck_NativeHouseholdsTitle,
            detail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    /**
     * How many Accounts carry a native Nonprofit Cloud household group and the BarnCRM
     * Household record type at once, the collision mutual exclusion exists to prevent
     * (product-plan Section 11.2 item 9). A warning, unlike the informational count above:
     * such an Account is one where BarnCRM used to write the name, greetings, or
     * address before this guard, and an administrator should look at it.
     */
    private static HealthCheckService.Finding nativeHouseholdCollisionFinding() {
        Integer collisions = HouseholdSelector.nativeHouseholdCollisionCount();
        if (collisions == null || collisions <= 0) {
            return null;
        }
        List<Object> count = new List<Object>{ String.valueOf(collisions) };
        return new HealthCheckService.Finding(
            'native_household_collision',
            String.format(System.Label.Core_HealthCheck_NativeHouseholdCollisionTitle, count),
            String.format(System.Label.Core_HealthCheck_NativeHouseholdCollisionDetail, count),
            HealthCheckService.SEVERITY_WARNING,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    private static HealthCheckService.Finding connectModuleFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.hasIndustriesNonprofit != true) {
            return null;
        }
        if (isConnectInstalled()) {
            return null;
        }

        return new HealthCheckService.Finding(
            'connect_module_absent',
            System.Label.Core_HealthCheck_ConnectMissingTitle,
            System.Label.Core_HealthCheck_ConnectMissingDetail,
            HealthCheckService.SEVERITY_INFO,
            HealthCheckService.CATEGORY_ORG_SHAPE
        );
    }

    private static Boolean isConnectInstalled() {
        if (connectInstalledOverride != null) {
            return connectInstalledOverride;
        }
        if (connectInstalled == null) {
            connectInstalled = classExists(CONNECT_MARKER_CLASS);
        }
        return connectInstalled;
    }

    /**
     * Whether an Apex class of this name is visible: in this package's namespace first, then
     * with none (today, and unmanaged deploys). A class name is not an API name, so the prefix
     * goes in without its `__` (dynamic-apex.md section 3).
     */
    @TestVisible
    private static Boolean classExists(String className) {
        String prefix = NamespaceUtil.prefix();
        Type found = Type.forName(
            String.isBlank(prefix) ? null : prefix.removeEnd('__'),
            className
        );
        if (found == null) {
            found = Type.forName(className);
        }
        return found != null;
    }

    private static HealthCheckService.Finding multiCurrencyFinding(
        OrgShapeDetector.OrgShape shape
    ) {
        if (shape == null || shape.isMultiCurrency != true) {
            return null;
        }

        return new HealthCheckService.Finding(
            'multi_currency',
            System.Label.Core_HealthCheck_MultiCurrencyTitle,
            System.Label.Core_HealthCheck_MultiCurrencyDetail,
            HealthCheckService.SEVERITY_WARNING,
            HealthCheckService.CATEGORY_LICENSES
        );
    }
}
