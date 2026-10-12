/**
 * Test users for the Health Check and coexistence tests (features C-07 and C-11).
 *
 * Two people appear in these tests: Maria, the operations manager, who holds the Manage
 * Nonprofit Settings permission, and Priya, the program coordinator, who does not and who is
 * the reason the access checks are gated at all.
 *
 * The permission comes from the packaged custom permission, not from a copy of it, and its
 * absence fails loudly. A test that quietly does nothing because a dependency has not merged
 * yet is the one failure mode a test exists to prevent.
 */
@IsTest
public class HealthCheckTestHelper {
    /** The packaged role an administrator of BarnCRM is given (admin guide, Access). */
    private static final String NONPROFIT_ADMIN = HealthCheckService.PERMISSION_SET_ADMIN;

    /**
     * Maria: a user holding the Manage Nonprofit Settings custom permission, and the packaged
     * Nonprofit Admin permission set that carries it in a real org.
     *
     * Both, because the permission alone does not describe anybody. The custom permission is
     * what the settings console and Health Check check, so a test that only granted that would
     * still exercise the gate, but it would exercise it as a user who cannot exist: the admin
     * guide tells Maria to ask for the Nonprofit Admin role, and that role is what gives her
     * create access on Setting Change, which every audited settings save writes in user mode
     * (ADR-0021 keeps the audit trail in user mode on purpose). Without it these tests failed
     * on the audit row rather than on anything they were written to check.
     */
    public static User mariaWithManageSettings() {
        List<CustomPermission> permissions = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :HealthCheckService.MANAGE_SETTINGS
            LIMIT 1
        ];
        System.assert(
            !permissions.isEmpty(),
            'The Manage Nonprofit Settings custom permission is not in this org. It ships with ' +
            'the settings console (C-03), which has to merge before these tests mean anything.'
        );

        List<PermissionSet> packaged = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :NONPROFIT_ADMIN
            LIMIT 1
        ];
        System.assert(
            !packaged.isEmpty(),
            'The Nonprofit Admin permission set is not in this org. It is the role the admin ' +
                'guide tells Maria to ask for, and it carries the object access an audited ' +
                'settings save needs, so these tests are about nobody without it.'
        );

        User maria = newUser('maria');
        String suffix = String.valueOf(System.now().getTime());
        PermissionSet grant = new PermissionSet(
            Name = 'Health_Check_Test_' + suffix,
            Label = 'Health Check test ' + suffix
        );

        System.runAs(currentUser()) {
            insert grant;
            insert new SetupEntityAccess(ParentId = grant.Id, SetupEntityId = permissions[0].Id);
            insert maria;
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = grant.Id),
                new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = packaged[0].Id)
            };
        }
        return maria;
    }

    /**
     * Priya: an ordinary user with no packaged permission at all.
     *
     * Every test that means "without the permission" has to run as her. Without a System.runAs
     * it runs as whoever is running the tests, and in any org the packages have been deployed
     * to that is an administrator holding the packaged permission sets, so a check that
     * correctly answers "yes" reads as a broken gate.
     */
    public static User priyaWithoutManageSettings() {
        User priya = newUser('priya');
        System.runAs(currentUser()) {
            insert priya;
        }
        return priya;
    }

    /**
     * The user running the test, used to keep setup object DML out of the same context as
     * ordinary record DML.
     */
    public static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static User newUser(String alias) {
        String unique =
            alias +
            '.' +
            String.valueOf(System.now().getTime()) +
            Crypto.getRandomInteger();
        return new User(
            Alias = alias.left(8),
            Email = alias + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            FirstName = alias.capitalize(),
            LastName = 'Nonprofit',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/New_York',
            Username = unique + '@example.invalid'
        );
    }
}
