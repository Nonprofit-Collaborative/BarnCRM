/**
 * Gives the Volunteers permission sets to BarnCRM's roles (ADR-0127 `0127-volunteers-module.md`,
 * decision 3): Volunteers Admin to everyone holding BarnCRM Admin, directly or through a role,
 * and each other set to the people assigned its role (a permission set group). The Coordinator
 * and Team Member roles hold the same Core set, so those follow the role itself
 * (`TabAccessService.giveToGroupHolders`, ADR-0131 `0131-module-access-sync-by-role.md`).
 *
 * It only gives, never takes away: a set may also be given by hand. It runs at install
 * (`VolunteersPostInstall`), and Core asks it when a role is given on the Access page, at each
 * Turn on and with the hourly access check, which also catches roles given in Setup. Core finds
 * it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the class
 * keeps this name. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class VolunteersAccessSync extends ModuleAccessSyncBase {
    /** The module key in the Module Manager. */
    public static final String MODULE_NAME = 'Volunteers';

    /** The set the installer and BarnCRM Admin holders get. */
    public static final String ADMIN_SET = 'Volunteers_Admin';

    /** The Admin set, and the Core permission set whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
        ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
    };

    /** Each other set, and the BarnCRM role (permission set group) whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
        'Volunteers_Coordinator' => new List<String>{ 'Volunteer_Coordinator' },
        'Volunteers_Staff' => new List<String>{ 'Program_Staff' },
        'Volunteers_Read_Only' => new List<String>{ 'Read_Only' }
    };

    /** Assignments one run gives per set: all four together stay inside the 10,000 DML rows. */
    private static final Integer ROWS_PER_SET = 2400;

    @NamespaceAccessible
    public VolunteersAccessSync() {
        // Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
    }

    /** One slice of each set now. Returns true when more is left. */
    public static Boolean syncOnce() {
        return new VolunteersAccessSync().sync();
    }

    public override String moduleName() {
        return MODULE_NAME;
    }

    public override String logContext() {
        return 'VolunteersAccessSync';
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
