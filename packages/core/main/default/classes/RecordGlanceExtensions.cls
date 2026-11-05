/**
 * Finds the record glance extensions dependent packages installed (people-14, ADR-NEXT
 * `NEXT-record-glance-extension.md`), the pattern `WhereUsedExtensions` uses (ADR-0159). A class
 * that is not installed, cannot be built or does not implement the interface is absent, and a
 * failure is logged: the record page must open whatever a module does.
 */
@NamespaceAccessible
public with sharing class RecordGlanceExtensions {
    /** The class names dependent packages register, in the order their cards show. */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'GivingRecordGlanceExtension'
    };

    /** Injected by Core's tests by class name, since no other package is there to resolve. */
    @TestVisible
    private static Map<String, RecordGlanceExtension> overrides = new Map<String, RecordGlanceExtension>();

    /** Set by Core's tests to see the org as having no extension beyond those injected. */
    @TestVisible
    private static Boolean noneForTest = false;

    /** Every installed extension, in registration order. */
    @NamespaceAccessible
    public static List<RecordGlanceExtension> installed() {
        List<RecordGlanceExtension> found = new List<RecordGlanceExtension>();
        for (String className : EXTENSION_CLASSES) {
            RecordGlanceExtension extension = overrides.get(className);
            if (extension == null && noneForTest != true) {
                extension = resolve(className);
            }
            if (extension != null) {
                found.add(extension);
            }
        }
        return found;
    }

    /** The cards every installed extension has for one record; a failing one is skipped. */
    @NamespaceAccessible
    public static List<RecordGlance.Card> cardsFor(Id recordId) {
        List<RecordGlance.Card> cards = new List<RecordGlance.Card>();
        if (recordId == null) {
            return cards;
        }
        for (RecordGlanceExtension extension : installed()) {
            try {
                RecordGlance.Card card = extension.glance(recordId);
                if (card != null) {
                    cards.add(card);
                }
            } catch (Exception failed) {
                ErrorLogger.log(failed, 'RecordGlanceExtensions.cardsFor', recordId);
            }
        }
        return cards;
    }

    private static RecordGlanceExtension resolve(String className) {
        Type extensionType = NamespaceUtil.resolveType(className);
        if (extensionType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = extensionType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'RecordGlanceExtensions.resolve');
            return null;
        }
        if (candidate instanceof RecordGlanceExtension) {
            return (RecordGlanceExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement RecordGlanceExtension'),
            'RecordGlanceExtensions.resolve'
        );
        return null;
    }
}
