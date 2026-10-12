/**
 * Tests for UserAccessSelector (feature C-11).
 *
 * The counts themselves are asserted through the Health Check findings that use them. What
 * is covered here is the behavior a finding cannot show: that an empty or missing set of
 * names asks the database nothing and answers nothing, rather than counting the whole org.
 */
@IsTest
private class UserAccessSelectorTest {
    @IsTest
    static void noGroupNamesMeansNobody() {
        System.assert(
            UserAccessSelector.getAssignedUserIds(null).isEmpty(),
            'No group names asked about means no people found.'
        );
        System.assert(
            UserAccessSelector.getAssignedUserIds(new Set<String>()).isEmpty(),
            'An empty set of group names finds nobody rather than everybody.'
        );
        System.assertEquals(
            0,
            UserAccessSelector.countActiveAssignees(null),
            'Counting nothing counts nobody.'
        );
        System.assertEquals(
            0,
            UserAccessSelector.countActiveAssignees(new Set<String>()),
            'Counting an empty set counts nobody.'
        );
    }

    @IsTest
    static void noPermissionSetNamesMeansNobody() {
        System.assert(
            UserAccessSelector.getPermissionSetAssigneeIds(null).isEmpty(),
            'No permission set names asked about means no people found.'
        );
        System.assert(
            UserAccessSelector.getPermissionSetAssigneeIds(new Set<String>()).isEmpty(),
            'An empty set of permission set names finds nobody.'
        );
        System.assertEquals(
            0,
            UserAccessSelector.countActiveDirectAssignees(null),
            'Counting nothing counts nobody.'
        );
        System.assertEquals(
            0,
            UserAccessSelector.countActiveDirectAssignees(new Set<String>()),
            'Counting an empty set counts nobody.'
        );
    }

    @IsTest
    static void thePackagedGroupsAreQueryable() {
        Test.startTest();
        Set<Id> assigned = UserAccessSelector.getAssignedUserIds(HealthCheckService.BARNCRM_GROUPS);
        Integer standardUsers = UserAccessSelector.countActiveStandardUsersExcluding(assigned);
        Test.stopTest();

        System.assertNotEquals(null, assigned, 'The query runs against the packaged groups.');
        System.assert(
            standardUsers >= 0,
            'Counting the people with no role always produces a number.'
        );
    }
}
