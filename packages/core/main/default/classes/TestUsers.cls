/**
 * The person a test runs as, so that no test depends on what the user running the tests
 * happens to hold.
 *
 * From API version 67.0 a query or DML statement with no access mode runs in user mode, in
 * test classes too. A test that runs as whoever deploys or runs it therefore passes only when
 * that person was given the BarnCRM permission sets first. The org test gate gives the
 * running user none, and a check-only deploy, a subscriber org or a different administrator
 * may not have them either, and every such
 * test fails with "fields being inaccessible", "No such column" or "You need the Manage
 * BarnCRM Settings permission". So a test that touches BarnCRM data or code runs inside
 * `System.runAs(TestUsers.admin())`, or the module's equivalent, and gets the access it needs
 * from the packaged permission sets assigned here (docs/contributor-guide/ci.md, "Tests run
 * as a user they create").
 *
 * The user is on the running user's own profile, so a test keeps everything the profile gave
 * it before (an administrator's View All Data over objects whose default access is Private,
 * the standard objects a profile grants) and only stops relying on the permission sets the
 * running user happens to hold. A test that has something to prove about least privilege
 * builds its own user with `TestDataFactory.createUser`, on the Standard User profile.
 *
 * One user per set of permission set names per transaction: the first call creates it, later
 * calls in the same test hand back the same user, and a user created in `@TestSetup` is found
 * again by every test method in the class.
 *
 * Public and namespace accessible, never global (ADR-0017), so a module package's tests can
 * call it. Test only.
 */
@IsTest
@NamespaceAccessible
public class TestUsers {
    /** The permission set an installing administrator gets for Core. */
    @NamespaceAccessible
    public static final String CORE_ADMIN = 'BarnCRM_Admin';

    /**
     * The admin permission set of each module Core calls into by name, as SampleDataModules
     * names their sample data classes. Named as strings: Core cannot depend on a module.
     */
    private static final List<String> MODULE_ADMINS = new List<String>{ 'Giving_Admin' };

    private static final String DOMAIN = '@barncrm.example.invalid';
    private static final String PREFIX = 'barn-test.';

    private static Map<String, User> usersByKey = new Map<String, User>();
    private static Id cachedStandardProfileId;

    /**
     * A user holding BarnCRM Admin: the access Core's tests need, given to the test user
     * rather than expected of whoever runs the tests.
     *
     * @return the test user, created on first use in this transaction
     */
    @NamespaceAccessible
    public static User admin() {
        return withPermissionSets(new List<String>{ CORE_ADMIN });
    }

    /**
     * A user holding BarnCRM Admin and one module permission set, for a module package's tests,
     * for example `TestUsers.adminWith('Giving_Admin')`.
     *
     * @param modulePermissionSet the bare API name of the module's permission set
     * @return the test user, created on first use in this transaction
     */
    @NamespaceAccessible
    public static User adminWith(String modulePermissionSet) {
        return withPermissionSets(new List<String>{ CORE_ADMIN, modulePermissionSet });
    }

    /**
     * A user holding BarnCRM Admin and the admin permission set of every module installed in
     * this org, for a Core test whose code calls into whichever modules are there (the sample
     * data loader counts and removes each module's records in user mode). In an org with Core
     * alone it is `admin()`.
     *
     * @return the test user, created on first use in this transaction
     */
    @NamespaceAccessible
    public static User adminWithInstalledModules() {
        List<String> names = new List<String>{ CORE_ADMIN };
        for (PermissionSet installed : [
            SELECT Name
            FROM PermissionSet
            WHERE Name IN :MODULE_ADMINS AND IsOwnedByProfile = FALSE
            WITH SYSTEM_MODE
        ]) {
            names.add(installed.Name);
        }
        return withPermissionSets(names);
    }

    /**
     * A user holding exactly the packaged permission sets named here, by their bare API name
     * (never namespace qualified: a packaged permission set keeps its bare Name and carries the
     * namespace in NamespacePrefix).
     *
     * @param permissionSetNames the bare API names of the packaged permission sets
     * @return the test user, created on first use in this transaction
     */
    @NamespaceAccessible
    public static User withPermissionSets(List<String> permissionSetNames) {
        List<String> names = new List<String>(new Set<String>(permissionSetNames));
        names.sort();
        String key = String.join(names, ',');
        User cached = usersByKey.get(key);
        if (cached != null) {
            return cached;
        }
        String usernameStart = PREFIX + keyHash(key) + '.';
        List<User> existing = [
            SELECT Id, Username, ProfileId
            FROM User
            WHERE Username LIKE :(usernameStart + '%') AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        User person = existing.isEmpty() ? create(usernameStart, names) : existing[0];
        usersByKey.put(key, person);
        return person;
    }

    private static User create(String usernameStart, List<String> names) {
        User person = newUser('Test User', UserInfo.getProfileId(), usernameStart);
        person.Alias = 'barntest';
        person.FirstName = 'BarnCRM';
        return insertWith(person, names);
    }

    /**
     * A user on the least privileged standard profile holding no permission set, inserted:
     * for a test that proves what a person without BarnCRM access gets.
     *
     * @param lastName the user's last name, also the start of the alias and username
     * @return the inserted user
     */
    @NamespaceAccessible
    public static User standardUser(String lastName) {
        return standardUserWith(lastName, new List<String>());
    }

    /**
     * A user on the least privileged standard profile holding only the packaged permission
     * sets named here, inserted, so a test proves what those sets grant rather than what an
     * administrator's profile allows.
     *
     * @param lastName the user's last name, also the start of the alias and username
     * @param permissionSetNames the bare API names of the packaged permission sets
     * @return the inserted user
     */
    @NamespaceAccessible
    public static User standardUserWith(String lastName, List<String> permissionSetNames) {
        return insertWith(newStandardUser(lastName), permissionSetNames);
    }

    /**
     * A user on the running user's own profile holding the packaged permission sets named
     * here, inserted: a person of their own, with the access the profile gives.
     *
     * @param lastName the user's last name, also the start of the alias and username
     * @param permissionSetNames the bare API names of the packaged permission sets
     * @return the inserted user
     */
    @NamespaceAccessible
    public static User onRunningProfileWith(String lastName, List<String> permissionSetNames) {
        return insertWith(
            newUser(lastName, UserInfo.getProfileId(), usernameStart(lastName)),
            permissionSetNames
        );
    }

    /**
     * A user on the least privileged standard profile, not yet inserted, with a username no
     * other call can produce: for a test that sets more fields before inserting it.
     *
     * @param lastName the user's last name, also the start of the alias and username
     * @return the unsaved user
     */
    @NamespaceAccessible
    public static User newStandardUser(String lastName) {
        return newUser(lastName, standardProfileId(), usernameStart(lastName));
    }

    /**
     * The least privileged standard profile: Standard User, or when the org does not call it
     * that (Profile.Name is the translated label), the first standard profile that is not System
     * Administrator. Never "any standard profile", which also matches System Administrator and
     * would silently disarm a test about a denied user.
     *
     * @return the profile Id
     */
    @NamespaceAccessible
    public static Id standardProfileId() {
        if (cachedStandardProfileId == null) {
            List<Profile> named = [
                SELECT Id
                FROM Profile
                WHERE Name = 'Standard User'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (named.isEmpty()) {
                named = [
                    SELECT Id
                    FROM Profile
                    WHERE UserType = 'Standard' AND Name != 'System Administrator'
                    WITH SYSTEM_MODE
                    ORDER BY Name
                    LIMIT 1
                ];
            }
            Assert.isFalse(
                named.isEmpty(),
                'This org has no standard profile other than System Administrator, so the ' +
                'tests cannot build a user who lacks administrator access.'
            );
            cachedStandardProfileId = named[0].Id;
        }
        return cachedStandardProfileId;
    }

    private static String usernameStart(String lastName) {
        return PREFIX + lastName.replaceAll('[^A-Za-z0-9]', '').toLowerCase() + '.';
    }

    private static User newUser(String lastName, Id profileId, String usernameStart) {
        return new User(
            Alias = lastName.deleteWhitespace().left(8),
            Email = 'barn-test' + DOMAIN,
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'GMT',
            Username = usernameStart + System.now().getTime() + Crypto.getRandomInteger() + DOMAIN
        );
    }

    private static User insertWith(User person, List<String> names) {
        List<PermissionSet> packaged = packagedPermissionSets(names);
        // A user and its assignments are setup objects: written in their own context, so the
        // data the test writes next does not break the mixed DML rule.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert as system person;
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet permissionSet : packaged) {
                assignments.add(
                    new PermissionSetAssignment(
                        AssigneeId = person.Id,
                        PermissionSetId = permissionSet.Id
                    )
                );
            }
            insert as system assignments;
        }
        return person;
    }

    /**
     * One permission set per name, preferring the one in this package's namespace when a
     * subscriber org also has its own set of the same name.
     *
     * @param names the bare API names asked for
     * @return the permission sets to assign
     */
    private static List<PermissionSet> packagedPermissionSets(List<String> names) {
        Map<String, PermissionSet> byName = permissionSetsByName(names);
        for (String name : names) {
            Assert.isTrue(
                byName.containsKey(name),
                'This org does not have the packaged permission set ' +
                    name +
                    ', so the test user cannot be given it. Deploy the package metadata into ' +
                    'the org before running the tests.'
            );
        }
        return byName.values();
    }

    /**
     * The permission sets with these bare API names, one per name, preferring the one in this
     * package's namespace (NamespaceUtil.prefix()) when a subscriber org also has its own set of
     * the same name. A name the org does not have is simply absent from the map.
     *
     * @param names the bare API names asked for
     * @return the chosen permission set per name
     */
    @NamespaceAccessible
    public static Map<String, PermissionSet> permissionSetsByName(List<String> names) {
        String namespace = NamespaceUtil.prefix().removeEnd('__');
        Map<String, PermissionSet> byName = new Map<String, PermissionSet>();
        for (PermissionSet candidate : [
            SELECT Id, Name, NamespacePrefix
            FROM PermissionSet
            WHERE Name IN :names AND IsOwnedByProfile = FALSE
            WITH SYSTEM_MODE
        ]) {
            Boolean ours = String.isBlank(namespace)
                ? String.isBlank(candidate.NamespacePrefix)
                : candidate.NamespacePrefix == namespace;
            if (ours || !byName.containsKey(candidate.Name)) {
                byName.put(candidate.Name, candidate);
            }
        }
        return byName;
    }

    private static String keyHash(String key) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(key))).left(10);
    }
}
