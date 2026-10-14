/**
 * The Fundraising Staff role carries the Giving Staff permission set (owner decision
 * 2026-10-13), so assigning the role on the Access page is all a gift entry person needs.
 */
@IsTest
private class FundraisingStaffGroupTest {
    @IsTest
    static void theRoleIncludesGivingStaff() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Set<String> included = new Set<String>();
            for (PermissionSetGroupComponent component : [
                SELECT PermissionSet.Name
                FROM PermissionSetGroupComponent
                WHERE PermissionSetGroup.DeveloperName = 'Fundraising_Staff'
                WITH SYSTEM_MODE
            ]) {
                included.add(component.PermissionSet.Name);
            }
            Test.stopTest();

            Assert.isTrue(included.contains('BarnCRM_Staff'), 'Core staff access, as before');
            Assert.isTrue(included.contains('Giving_Staff'), 'and the Giving records');
        }
    }
}
