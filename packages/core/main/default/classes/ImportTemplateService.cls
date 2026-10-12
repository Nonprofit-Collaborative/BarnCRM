/**
 * Import templates: the ones the package ships, and the ones the administrator edits.
 *
 * Materialization follows the settings strategy in ADR-0006 and R-IT4. A shipped default
 * becomes a real `Import_Template__c` record the first time it is seen, matched by template
 * key, and is never overwritten afterwards, so an administrator's edit survives every
 * upgrade. Person Mode is the one value taken from the org rather than from the shipped row
 * (R-IT3): a Nonprofit Cloud org that stores people as person
 * Accounts gets templates that say so.
 */
@NamespaceAccessible
public with sharing class ImportTemplateService {
    @NamespaceAccessible
    public static final String PERSON_MODE_CONTACTS = 'Contacts';
    @NamespaceAccessible
    public static final String PERSON_MODE_PERSON_ACCOUNTS = 'Person Accounts';

    @NamespaceAccessible
    public static final String RULE_EMAIL = 'Email exact';
    @NamespaceAccessible
    public static final String RULE_NAME_POSTAL = 'Name plus postal code';
    @NamespaceAccessible
    public static final String RULE_EXTERNAL_ID = 'External ID';

    private static final Set<String> RULES = new Set<String>{
        RULE_EMAIL,
        RULE_NAME_POSTAL,
        RULE_EXTERNAL_ID
    };

    /**
     * Creates an `Import_Template__c` for every shipped default this org does not have yet,
     * and returns how many were created. Safe to call repeatedly: it is called on install
     * and whenever the wizard opens with no templates.
     */
    @NamespaceAccessible
    public static Integer materializeDefaults() {
        List<Import_Template__c> toCreate = missingDefaults();
        if (toCreate.isEmpty()) {
            return 0;
        }
        Database.insert(toCreate, AccessLevel.USER_MODE);
        return toCreate.size();
    }

    /**
     * The names of the shipped templates this org does not have yet, without creating them, so
     * Health Check can say what restoring them would add (C-21, ADR-0048).
     */
    @NamespaceAccessible
    public static List<String> missingDefaultNames() {
        List<String> names = new List<String>();
        for (Import_Template__c template : missingDefaults()) {
            names.add(template.Name);
        }
        return names;
    }

    /** The templates materializeDefaults would create: one per shipped default not yet here. */
    private static List<Import_Template__c> missingDefaults() {
        List<Import_Template__c> toCreate = new List<Import_Template__c>();
        List<Import_Template_Default__mdt> shipped = ImportTemplateSelector.selectShippedDefaults();
        if (shipped.isEmpty()) {
            return toCreate;
        }
        Set<String> keys = new Set<String>();
        for (Import_Template_Default__mdt row : shipped) {
            if (String.isNotBlank(row.Template_Key__c)) {
                keys.add(row.Template_Key__c);
            }
        }
        Map<String, Import_Template__c> existing = ImportTemplateSelector.selectByKeys(keys);
        String personMode = defaultPersonMode();
        for (Import_Template_Default__mdt row : shipped) {
            if (String.isBlank(row.Template_Key__c) || existing.containsKey(row.Template_Key__c)) {
                continue;
            }
            toCreate.add(
                new Import_Template__c(
                    Name = row.MasterLabel,
                    Description__c = row.Description__c,
                    Template_Key__c = row.Template_Key__c,
                    Column_Mapping_JSON__c = row.Column_Mapping_JSON__c,
                    Default_Values_JSON__c = row.Default_Values_JSON__c,
                    Matching_Rule__c = normalizedRule(row.Matching_Rule__c),
                    Person_Mode__c = personMode,
                    Is_Package_Default__c = true,
                    Is_Recurring__c = false,
                    Active__c = row.Default_Active__c == true
                )
            );
        }
        return toCreate;
    }

    /**
     * The active templates, materializing the shipped defaults first when the org has none.
     * This is what the wizard asks for when it opens.
     */
    @NamespaceAccessible
    public static List<Import_Template__c> listActive() {
        List<Import_Template__c> templates = ImportTemplateSelector.selectActive();
        if (!templates.isEmpty()) {
            return templates;
        }
        materializeDefaults();
        return ImportTemplateSelector.selectActive();
    }

    /**
     * Saves the mapping the administrator built in the picker back onto its template, so the
     * same file next month needs no work. The mapping is validated before it is stored.
     */
    @NamespaceAccessible
    public static Import_Template__c saveMapping(
        Id templateId,
        String mappingDocument,
        String matchingRule
    ) {
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        ImportMapping mapping = ImportMapping.parse(mappingDocument);
        if (!mapping.identifiesSomebody()) {
            throw new ImportException(Label.Core_Import_ErrorMappingIdentifiesNobody);
        }
        template.Column_Mapping_JSON__c = mapping.serialize();
        template.Matching_Rule__c = normalizedRule(matchingRule);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** The donation matching behaviours a template can hold (R-IT7, R-DM5). */
    @NamespaceAccessible
    public static final List<String> DONATION_MATCHING_VALUES = new List<String>{
        'Match or create',
        'Always create',
        'Match only',
        'Never match'
    };

    /**
     * Saves how this template's gifts are matched to scheduled payments (R-IT7). Core only
     * holds the values: an empty one means the default, and the Giving module reads them. A
     * behaviour Core does not know, a negative window or a negative tolerance is refused.
     */
    @NamespaceAccessible
    public static Import_Template__c saveDonationMatching(
        Id templateId,
        String behaviour,
        Integer windowDays,
        Decimal tolerance
    ) {
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        String chosen = null;
        for (String value : DONATION_MATCHING_VALUES) {
            if (String.isNotBlank(behaviour) && value.equalsIgnoreCase(behaviour.trim())) {
                chosen = value;
            }
        }
        if (String.isNotBlank(behaviour) && chosen == null) {
            throw new ImportException(Label.Core_Import_ErrorDonationMatchingUnknown);
        }
        if (
            (windowDays != null && (windowDays < 0 || windowDays > 999)) ||
            (tolerance != null &&
            tolerance < 0)
        ) {
            throw new ImportException(Label.Core_Import_ErrorDonationMatchingRange);
        }
        template.Donation_Matching__c = chosen;
        template.Match_Date_Window_Days__c = windowDays;
        template.Match_Amount_Tolerance__c = tolerance == null ? null : tolerance.setScale(2);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /**
     * Marks a template as the mapping for a file that arrives regularly, or not (R-IT6). The
     * source name says which feed it is, and is required while the template is recurring. It
     * is kept when the mark is taken off, so ticking the box again brings it back.
     */
    @NamespaceAccessible
    public static Import_Template__c saveRecurring(
        Id templateId,
        Boolean isRecurring,
        String sourceName
    ) {
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        if (isRecurring == true && String.isBlank(sourceName)) {
            throw new ImportException(Label.Core_Import_ErrorSourceNameRequired);
        }
        template.Is_Recurring__c = isRecurring == true;
        if (String.isNotBlank(sourceName)) {
            template.Source_Name__c = sourceName.trim().left(255);
        }
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /**
     * The active recurring templates, the one loaded longest ago first and one never loaded
     * before any of them, so the feed nobody has loaded is at the top of the Hub's list.
     */
    @NamespaceAccessible
    public static List<Import_Template__c> recurringSources() {
        List<Import_Template__c> never = new List<Import_Template__c>();
        Map<Date, List<Import_Template__c>> byDate = new Map<Date, List<Import_Template__c>>();
        for (Import_Template__c template : ImportTemplateSelector.selectActive()) {
            if (template.Is_Recurring__c != true) {
                continue;
            }
            if (template.Last_Import_Date__c == null) {
                never.add(template);
                continue;
            }
            if (!byDate.containsKey(template.Last_Import_Date__c)) {
                byDate.put(template.Last_Import_Date__c, new List<Import_Template__c>());
            }
            byDate.get(template.Last_Import_Date__c).add(template);
        }
        List<Date> dates = new List<Date>(byDate.keySet());
        dates.sort();
        List<Import_Template__c> result = new List<Import_Template__c>(never);
        for (Date lastImport : dates) {
            result.addAll(byDate.get(lastImport));
        }
        return result;
    }

    /** Records that a template was used, so the Hub can say how stale a recurring feed is. */
    @NamespaceAccessible
    public static void recordImport(Id templateId, Date completedOn) {
        if (templateId == null) {
            return;
        }
        Import_Template__c template = new Import_Template__c(
            Id = templateId,
            Last_Import_Date__c = completedOn == null ? Date.today() : completedOn
        );
        Database.update(template, AccessLevel.SYSTEM_MODE);
    }

    /** The person mode a new template starts in, from the org shape the assistant detected. */
    @NamespaceAccessible
    public static String defaultPersonMode() {
        return HouseholdService.isPersonAccountOrg()
            ? PERSON_MODE_PERSON_ACCOUNTS
            : PERSON_MODE_CONTACTS;
    }

    /** True when this template asks for people to be stored as person Accounts (R-IT3). */
    @NamespaceAccessible
    public static Boolean isPersonAccountMode(Import_Template__c template) {
        return template != null &&
            PERSON_MODE_PERSON_ACCOUNTS.equalsIgnoreCase(template.Person_Mode__c);
    }

    /** A rule name the picklist accepts. Anything unrecognized falls back to the safe rule. */
    @NamespaceAccessible
    public static String normalizedRule(String rule) {
        if (String.isBlank(rule)) {
            return RULE_EMAIL;
        }
        for (String known : RULES) {
            if (known.equalsIgnoreCase(rule.trim())) {
                return known;
            }
        }
        return RULE_EMAIL;
    }
}
