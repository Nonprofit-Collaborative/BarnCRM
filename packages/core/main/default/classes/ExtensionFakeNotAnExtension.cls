/**
 * A class that can be found by name but implements neither extension interface, for Core's
 * tests of how a wrongly registered class is handled. Test only.
 */
@IsTest
public class ExtensionFakeNotAnExtension {
    public Integer value = 1;
}
