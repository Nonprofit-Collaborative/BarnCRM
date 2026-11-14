// Template for scripts/org/package-upgrade-test.sh: %%NS%%, %%MODULE%%, %%MODULE_CLASSES%% and
// %%MODULE_OBJECTS%% are filled in from the module's source. Not deployed.
// Run after the module is uninstalled. Principle 3: a module that is off leaves nothing behind.
// Checks that none of its classes or objects remain and that no Core automation switch still
// names one of its handler classes. Core still working is checked by the Health Check and Core
// smoke steps that run after this one. It only reads.
Set<String> moduleClasses = new Set<String>{ %%MODULE_CLASSES%% };
Set<String> moduleObjects = new Set<String>{ %%MODULE_OBJECTS%% };
List<String> left = new List<String>();
for (ApexClass cls : [SELECT Name FROM ApexClass WHERE NamespacePrefix = '%%NS%%' AND Name IN :moduleClasses]) {
	left.add('class ' + cls.Name);
}
for (EntityDefinition entity : [SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName IN :moduleObjects]) {
	left.add('object ' + entity.QualifiedApiName);
}
for (%%NS%%__Automation_Setting__c setting : [
	SELECT Name, %%NS%%__Handler_Class__c
	FROM %%NS%%__Automation_Setting__c
	WHERE %%NS%%__Handler_Class__c IN :moduleClasses
]) {
	left.add('automation switch ' + setting.Name + ' (' + setting.%%NS%%__Handler_Class__c + ')');
}
Assert.areEqual(0, left.size(), '%%MODULE%% left behind: ' + String.join(left, '; '));
