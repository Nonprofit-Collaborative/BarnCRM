/**
 * Gives the Funders permission sets to BarnCRM's roles (ADR-NEXT `NEXT-funders-module.md`,
 * decision 9): Funders Admin to everyone holding BarnCRM Admin, directly or through a role,
 * Funders Staff to the Team Member, Coordinator and Fundraising Staff roles (the last is Giving's,
 * which Funders depends on), and Funders Read Only to the Read Only role. The roles are permission set groups, followed through
 * `TabAccessService.giveToGroupHolders` (ADR-0131 `0131-module-access-sync-by-role.md`).
 *
 * It only gives, never takes away: a set may also be given by hand. It runs at install
 * (`FundersPostInstall`), and Core asks it when a role is given on the Access page, at each
 * Turn on and with the hourly access check, which also catches roles given in Setup. Core finds
 * it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the class
 * keeps this name. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class FundersAccessSync extends ModuleAccessSyncBase {
    /** The module key in the Module Manager. */
    public static final String MODULE_NAME = 'Funders';
    /** The set the installer and BarnCRM Admin holders get. */
    public static final String ADMIN_SET = 'Funders_Admin';

    /** The Admin set, and the Core permission set whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
        ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
    };

    /** Each other set, and the BarnCRM roles (permission set groups) whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
        'Funders_Staff' => new List<String>{
            'Program_Staff',
            'Volunteer_Coordinator',
            'Fundraising_Staff'
        },
        'Funders_Read_Only' => new List<String>{ 'Read_Only' }
    };

    /** Assignments one run gives per set: all three together stay inside the 10,000 DML rows. */
    private static final Integer ROWS_PER_SET = 3000;

    @NamespaceAccessible
    public FundersAccessSync() {
        // Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
    }

    /** One slice of each set now. Returns true when more is left. */
    public static Boolean syncOnce() {
        return new FundersAccessSync().sync();
    }

    public override String moduleName() {
        return MODULE_NAME;
    }

    public override String logContext() {
        return 'FundersAccessSync';
    }

    public override Map<String, List<String>> setsByPermissionSet() {
        return BY_SET;
    }

    public override Map<String, List<String>> setsByRole() {
        return BY_ROLE;
    }

    public override Integer sliceSize() {
        return ROWS_PER_SET;
    }
}
