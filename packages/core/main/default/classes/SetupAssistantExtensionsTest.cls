/**
 * How Core finds a module's Setup Assistant contributions by class name (C-29, ADR-0059). A
 * name that is not in the org, or a class that is not an extension, is treated as no module
 * at all, so the assistant still opens.
 */
@IsTest
private class SetupAssistantExtensionsTest {
    @IsTest
    static void aClassThatIsNotInTheOrgIsNoExtension() {
        Test.startTest();
        SetupAssistantExtension found = SetupAssistantExtensions.resolve(
            'NoSuchSetupAssistantExtensionC29'
        );
        Test.stopTest();

        Assert.isNull(found, 'A module that is not installed contributes nothing');
    }

    @IsTest
    static void aClassThatIsNotAnExtensionIsLeftOut() {
        Test.startTest();
        // A real class with a no-argument constructor that does not implement the interface.
        SetupAssistantExtension found = SetupAssistantExtensions.resolve(
            'SetupAssistantExtensions'
        );
        Test.stopTest();

        Assert.isNull(found, 'Only a class that implements the interface is used');
    }

    @IsTest
    static void aClassThatImplementsTheInterfaceIsFound() {
        Test.startTest();
        SetupAssistantExtension found = SetupAssistantExtensions.resolve(
            'SetupAssistantTestExtension'
        );
        Test.stopTest();

        Assert.isNotNull(found, 'An installed extension is built by its class name');
        Assert.isTrue(
            found instanceof SetupAssistantTestExtension,
            'The class named is the class built'
        );
    }

    @IsTest
    static void anOrgWithoutModulesStillAnswers() {
        Test.startTest();
        List<SetupAssistantExtension> all = SetupAssistantExtensions.findAll();
        Test.stopTest();

        Assert.isNotNull(all, 'Core alone gets an empty list, never null');
        Assert.isTrue(
            all.size() <= SetupAssistantExtensions.EXTENSION_CLASSES.size(),
            'At most one extension per registered class'
        );
    }
}
