/**
 * Shipped setup objects found by name with this package's namespace (D-200, N9). In a test org
 * the source is deployed without a namespace, so BarnCRM's own rows have no NamespacePrefix and
 * the lookups find them; a name BarnCRM does not ship finds nothing.
 */
// runs-as: deploying user (the selector runs in system mode, so the runner's permissions do not change what it finds)
@IsTest(testFor='ApexClass:SetupObjectSelector')
private class SetupObjectSelectorTest {
	@IsTest
	static void findsTheShippedPermissionSetAndCustomPermission() {
		PermissionSet admin = SetupObjectSelector.permissionSet(TestUsers.CORE_ADMIN);

		Assert.isNotNull(admin, 'BarnCRM Admin ships with Core');
		Assert.areEqual(TestUsers.CORE_ADMIN, admin.Name, 'By its name');
		Assert.isNotNull(
			SetupObjectSelector.customPermissionId(BarnCRMPermissions.MANAGE_SETTINGS),
			'Manage BarnCRM Settings ships with Core'
		);
		Assert.isNull(SetupObjectSelector.permissionSet('No_Such_Barn_Set'), 'Unknown name');
		Assert.isNull(SetupObjectSelector.permissionSet(null), 'No name');
		Assert.isNull(SetupObjectSelector.customPermissionId('No_Such_Barn_Permission'), 'None');
	}

	@IsTest
	static void readsAShippedStaticResource() {
		Assert.isNotNull(SetupObjectSelector.staticResource('SampleData'), 'Core ships it');
		Assert.isTrue(
			SetupObjectSelector.staticResourceBody('SampleData').startsWith('{'),
			'Its JSON body'
		);
		Assert.isNull(SetupObjectSelector.staticResourceBody('No_Such_Barn_Resource'), 'None');
	}

	@IsTest
	static void unknownGroupsAndTemplatesFindNothing() {
		Assert.isNull(SetupObjectSelector.groupId('No_Such_Barn_Group'), 'No group');
		Assert.isNull(SetupObjectSelector.emailTemplateId('No_Such_Barn_Template', false), 'None');
		Assert.isTrue(
			SetupObjectSelector.permissionSetGroups(new Set<String>{ 'No_Such_Barn_Role' })
				.isEmpty(),
			'No role'
		);
	}

	@IsTest
	static void namespacePrefixIsNullWithoutANamespace() {
		NamespaceUtil.cachedPrefix = '';
		Assert.isNull(NamespaceUtil.namespacePrefix(), 'Matches rows with no prefix');
		NamespaceUtil.cachedPrefix = 'barn__';
		Assert.areEqual('barn', NamespaceUtil.namespacePrefix(), 'As setup objects store it');
	}
}
