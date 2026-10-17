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

    /** The organization rules (R-IT2); an empty value means Name exact. */
    @NamespaceAccessible
    public static final String ORGANIZATION_RULE_NAME = 'Name exact';
    @NamespaceAccessible
    public static final String ORGANIZATION_RULE_EXTERNAL_ID = 'External ID';

    /** What happens when a key finds several records (R-IT9); empty means reject the row. */
    @NamespaceAccessible
    public static final String SEVERAL_REJECT = 'Reject the row';
    @NamespaceAccessible
    public static final String SEVERAL_MOST_RECENT = 'Use the most recently changed';

    /** How a template matches, as the wizard sends it (R-IT2, R-IT8, R-IT9). */
    @NamespaceAccessible
    public class MatchingChoices {
        @NamespaceAccessible
        public String personRule;
        @NamespaceAccessible
        public String personMatchField;
        @NamespaceAccessible
        public String organizationRule;
        @NamespaceAccessible
        public String organizationMatchField;
        @NamespaceAccessible
        public String severalMatches;
        /** Whether the org's duplicate rules are asked too (R-IT16); false when absent. */
        @NamespaceAccessible
        public Boolean useDuplicateRules;
    }

    /**
     * Saves how a template matches people and organizations, and what happens when several
     * records match (R-IT2, R-IT8, R-IT9, R-IT16). A chosen field is stored as describe names it,
     * and one the object does not offer for matching is refused, saying which.
     */
    @NamespaceAccessible
    public static Import_Template__c saveMatching(Id templateId, MatchingChoices choices) {
        Import_Template__c template = existing(templateId);
        applyMatching(template, choices);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** Sets a template's matching choices as `saveMatching` saves them, without saving. */
    private static void applyMatching(Import_Template__c template, MatchingChoices choices) {
        MatchingChoices given = choices == null ? new MatchingChoices() : choices;
        template.Matching_Rule__c = normalizedRule(given.personRule);
        template.Organization_Matching_Rule__c = normalizedOrganizationRule(given.organizationRule);
        template.Several_Matches__c = normalizedSeveralMatches(given.severalMatches);
        template.Use_Duplicate_Rules__c = given.useDuplicateRules == true;
        template.Person_Match_Field__c = RULE_EXTERNAL_ID.equals(template.Matching_Rule__c)
            ? checkedField(personType(template), given.personMatchField)
            : null;
        template.Organization_Match_Field__c = ORGANIZATION_RULE_EXTERNAL_ID.equals(
                template.Organization_Matching_Rule__c
            )
            ? checkedField(Account.SObjectType, given.organizationMatchField)
            : null;
    }

    /**
     * Creates a template that loads one object (R-IT12), empty until its first file is mapped.
     * The object must be one `ImportObjectSchema` offers: admitted by the allow-list rule
     * (R-IT14) and one the user can read and create or edit records of. It is stored by the name
     * describe gives it. People and organizations start on Update by record Id, their only
     * operation; any other object on Insert when the user may create its records.
     */
    @NamespaceAccessible
    public static Import_Template__c createObjectTemplate(String name, String objectName) {
        if (String.isBlank(name)) {
            throw new ImportException(Label.Core_Import_ErrorObjectTemplateName);
        }
        Schema.SObjectType type = ImportObjectSchema.typeNamed(objectName);
        String refused = DataProtectedFields.objectRefusal(type);
        if (refused != null) {
            throw new ImportException(refused);
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Boolean creates = described.isCreateable() && !ImportObjectSchema.updatesOnly(type);
        if (!described.isAccessible() || !(creates || described.isUpdateable())) {
            throw new ImportException(
                String.format(
                    Label.Core_Import_ErrorObjectNoAccess,
                    new List<String>{ described.getLabelPlural() }
                )
            );
        }
        Import_Template__c template = new Import_Template__c(
            Name = name.trim().abbreviate(80),
            Template_Key__c = 'object_' +
                described.getName().toLowerCase().left(40) +
                '_' +
                String.valueOf(Math.abs(Crypto.getRandomLong())).left(12),
            Column_Mapping_JSON__c = new ImportMapping().serialize(),
            Default_Values_JSON__c = '{"version":1,"defaults":[]}',
            Matching_Rule__c = RULE_EMAIL,
            Person_Mode__c = defaultPersonMode(),
            Is_Package_Default__c = false,
            Is_Recurring__c = false,
            Active__c = true,
            Target_Object__c = described.getName(),
            Load_Operation__c = creates
                ? ImportObjectSchema.OPERATION_INSERT
                : ImportObjectSchema.OPERATION_UPDATE,
            Lookup_Not_Found__c = ImportObjectSchema.LOOKUP_REJECT,
            Several_Matches__c = SEVERAL_REJECT
        );
        Database.insert(template, AccessLevel.USER_MODE);
        return template;
    }

    /** What a one-object template does with each row, as the wizard sends it (R-IT12). */
    @NamespaceAccessible
    public class LoadChoices {
        @NamespaceAccessible
        public String operation;
        @NamespaceAccessible
        public String matchField;
        @NamespaceAccessible
        public String lookupNotFound;
        @NamespaceAccessible
        public String severalMatches;
        /** The related records each row also creates, `Object.Field`, or blank (R-IT17). */
        @NamespaceAccessible
        public String related;
    }

    /**
     * Saves what a one-object template does with each row (R-IT12, R-IT13, R-IT9): the
     * operation, the field an upsert or an update by a matching field finds records by, what a
     * row whose lookup finds no record does, and what a row matching several does. People and
     * organizations keep one of the two updates. A match field the object does not offer is
     * refused, naming it.
     */
    @NamespaceAccessible
    public static Import_Template__c saveLoad(Id templateId, LoadChoices choices) {
        Import_Template__c template = existing(templateId);
        applyLoad(template, choices);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** Sets a one-object template's load choices as `saveLoad` saves them, without saving. */
    private static void applyLoad(Import_Template__c template, LoadChoices choices) {
        LoadChoices given = choices == null ? new LoadChoices() : choices;
        Schema.SObjectType type = ImportObjectSchema.typeOf(template);
        template.Load_Operation__c = given.operation;
        template.Load_Operation__c = ImportObjectSchema.operationFor(type, template);
        if (template.Load_Operation__c == ImportObjectSchema.OPERATION_DELETE) {
            String refused = ImportObjectSchema.deleteRefusal(type);
            if (refused != null) {
                throw new ImportException(refused);
            }
        }
        template.Load_Match_Field__c = null;
        Boolean byKey = template.Load_Operation__c == ImportObjectSchema.OPERATION_UPSERT;
        if (
            (byKey || template.Load_Operation__c == ImportObjectSchema.OPERATION_UPDATE_BY_FIELD) &&
            String.isNotBlank(given.matchField)
        ) {
            String found = byKey
                ? ImportObjectSchema.keyField(type, given.matchField)
                : ImportObjectSchema.matchField(type, given.matchField);
            if (found == null) {
                throw new ImportException(
                    String.format(
                        byKey
                            ? Label.Core_Import_ErrorKeyFieldUnusable
                            : Label.Core_Import_ErrorMatchFieldUnusable,
                        new List<String>{ given.matchField.trim().abbreviate(80) }
                    )
                );
            }
            template.Load_Match_Field__c = found;
        }
        template.Lookup_Not_Found__c = ImportObjectSchema.LOOKUP_LEAVE_EMPTY.equalsIgnoreCase(
                given.lookupNotFound == null ? '' : given.lookupNotFound.trim()
            )
            ? ImportObjectSchema.LOOKUP_LEAVE_EMPTY
            : ImportObjectSchema.LOOKUP_REJECT;
        template.Several_Matches__c = normalizedSeveralMatches(given.severalMatches);
        setRelated(template, type, given.related);
    }

    /**
     * Sets the related records a one-object template creates (R-IT17) from `Object.Field`, or
     * clears them when blank. Refused, with the reason, under Insert, which has no parent key,
     * and for an object a load may not create or a field that does not point at the object.
     */
    private static void setRelated(
        Import_Template__c template,
        Schema.SObjectType type,
        String chosen
    ) {
        template.Related_Object__c = null;
        template.Related_Parent_Field__c = null;
        if (String.isBlank(chosen)) {
            return;
        }
        if (template.Load_Operation__c == ImportObjectSchema.OPERATION_INSERT) {
            throw new ImportException(Label.Core_Import_ErrorRelatedNeedsKey);
        }
        Schema.SObjectType related = ImportObjectSchema.typeNamed(chosen.substringBefore('.'));
        String refused = ImportObjectSchema.insertRefusal(related);
        if (refused != null) {
            throw new ImportException(refused);
        }
        String field = ImportObjectSchema.relatedParentField(
            type,
            related,
            chosen.substringAfter('.')
        );
        if (field == null) {
            throw new ImportException(
                String.format(
                    Label.Core_Import_ErrorRelatedFieldUnusable,
                    new List<String>{
                        related.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel(),
                        type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                    }
                )
            );
        }
        template.Related_Object__c = related.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        template.Related_Parent_Field__c = field;
    }

    /** A chosen matching field as describe names it, or null for none; refused when not offered. */
    private static String checkedField(Schema.SObjectType type, String chosen) {
        if (String.isBlank(chosen)) {
            return null;
        }
        String field = ImportMatcher.matchField(type, chosen);
        if (field == null) {
            throw new ImportException(
                String.format(
                    Label.Core_Import_ErrorMatchFieldNotAllowed,
                    new List<String>{ chosen.trim().left(80) }
                )
            );
        }
        return field;
    }

    /** The object a template's people are stored on (R-IT3). */
    @NamespaceAccessible
    public static Schema.SObjectType personType(Import_Template__c template) {
        return isPersonAccountMode(template) ? Account.SObjectType : Contact.SObjectType;
    }

    /** An organization rule the picklist accepts; anything else is Name exact. */
    @NamespaceAccessible
    public static String normalizedOrganizationRule(String rule) {
        return rule != null && ORGANIZATION_RULE_EXTERNAL_ID.equalsIgnoreCase(rule.trim())
            ? ORGANIZATION_RULE_EXTERNAL_ID
            : ORGANIZATION_RULE_NAME;
    }

    /** A several-matches choice the picklist accepts; anything else rejects the row. */
    @NamespaceAccessible
    public static String normalizedSeveralMatches(String choice) {
        return choice != null && SEVERAL_MOST_RECENT.equalsIgnoreCase(choice.trim())
            ? SEVERAL_MOST_RECENT
            : SEVERAL_REJECT;
    }

    /** True when a row matching several records takes the most recently changed (R-IT9). */
    @NamespaceAccessible
    public static Boolean usesMostRecent(Import_Template__c template) {
        return template != null &&
            SEVERAL_MOST_RECENT.equals(normalizedSeveralMatches(template.Several_Matches__c));
    }

    /**
     * Creates an `Import_Template__c` for every shipped default this org does not have yet,
     * and returns how many were created. Safe to call repeatedly: a template is matched by its
     * key, so one already here, edited or not, is left as it is. Called when the wizard opens
     * with no templates and from Health Check's Restore; install and upgrade use
     * `materializeDefaultsDuringInstall`.
     */
    @NamespaceAccessible
    public static Integer materializeDefaults() {
        List<Import_Template__c> toCreate = missingDefaults(true);
        if (toCreate.isEmpty()) {
            return 0;
        }
        Database.insert(toCreate, AccessLevel.USER_MODE);
        return toCreate.size();
    }

    /** What an install's failure to add the templates is logged under, unless told otherwise. */
    private static final String INSTALL_CONTEXT = 'ImportTemplateService.materializeDefaultsDuringInstall';

    /**
     * Adds the shipped templates this org does not have yet, at install and at every upgrade, so
     * a template shipped in a later version reaches an org that already has others (D-41). Each
     * package's post-install script calls it, because Core installs first and cannot see a
     * module's templates yet. A template already here is matched by its key and left exactly as
     * the administrator left it, edited or switched off; one they deleted comes back.
     *
     * The insert is in system mode: the post-install user holds no permission set, and every
     * value written comes from packaged custom metadata (ADR-0021 condition 2). Nothing throws:
     * an install must never fail over this, so a failure goes to the Error Log and Health Check
     * still offers Restore.
     */
    @NamespaceAccessible
    public static Integer materializeDefaultsDuringInstall(String context) {
        try {
            List<Import_Template__c> toCreate = missingDefaults(true);
            if (toCreate.isEmpty()) {
                return 0;
            }
            Database.insert(toCreate, AccessLevel.SYSTEM_MODE);
            return toCreate.size();
        } catch (Exception failed) {
            ErrorLogger.log(failed, String.isBlank(context) ? INSTALL_CONTEXT : context);
            return 0;
        }
    }

    /**
     * The names of the shipped templates this org does not have yet, without creating them, so
     * Health Check can say what restoring them would add (C-21, ADR-0048).
     */
    @NamespaceAccessible
    public static List<String> missingDefaultNames() {
        List<String> names = new List<String>();
        for (Import_Template__c template : missingDefaults(false)) {
            names.add(template.Name);
        }
        return names;
    }

    /** The templates materializeDefaults would create: one per shipped default not yet here. */
    private static List<Import_Template__c> missingDefaults(Boolean logSkips) {
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
        Set<String> added = new Set<String>();
        for (Import_Template_Default__mdt row : shipped) {
            if (
                String.isBlank(row.Template_Key__c) ||
                existing.containsKey(row.Template_Key__c) ||
                added.contains(row.Template_Key__c)
            ) {
                continue;
            }
            if (String.isNotBlank(row.Target_Object__c)) {
                Import_Template__c loadOne = oneObjectTemplate(row, personMode, logSkips);
                if (loadOne != null) {
                    added.add(row.Template_Key__c);
                    toCreate.add(loadOne);
                }
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

    /** What a skipped one-object default is logged under (R-D3). */
    private static final String SKIP_CONTEXT = 'ImportTemplateService.oneObjectTemplate';

    /** Skipped defaults already logged in this transaction, so each is logged once per run. */
    private static Set<String> loggedSkips = new Set<String>();

    /**
     * The template a shipped row that loads one object becomes, or null when it is not for this
     * org (R-D3). A row for the other people mode is passed over silently. A row whose object,
     * mapped field, lookup field or match field this org lacks, or whose operation needs a match
     * field it does not name, is skipped and written to the Error Log once per run.
     */
    private static Import_Template__c oneObjectTemplate(
        Import_Template_Default__mdt row,
        String personMode,
        Boolean logSkips
    ) {
        if (String.isNotBlank(row.Person_Mode__c) && row.Person_Mode__c != personMode) {
            return null;
        }
        Schema.SObjectType type = ImportObjectSchema.typeNamed(row.Target_Object__c);
        String severity = ErrorLogger.SEVERITY_WARNING;
        String problem = null;
        if (type == null) {
            severity = ErrorLogger.SEVERITY_INFO;
            problem = 'the object ' + row.Target_Object__c + ' is not in this org';
        } else {
            problem = oneObjectFieldProblem(type, row);
        }
        if (problem != null) {
            String message =
                'The shipped import template ' +
                row.MasterLabel +
                ' was not added: ' +
                problem +
                '.';
            if (logSkips && loggedSkips.add(row.DeveloperName)) {
                ErrorLogger.logMessage(message, SKIP_CONTEXT, severity);
            }
            return null;
        }
        String operation = String.isBlank(row.Load_Operation__c)
            ? ImportObjectSchema.OPERATION_INSERT
            : row.Load_Operation__c;
        Boolean needsField =
            operation == ImportObjectSchema.OPERATION_UPSERT ||
            operation == ImportObjectSchema.OPERATION_UPDATE_BY_FIELD;
        Schema.SObjectField matchToken = ImportObjectSchema.fieldNamed(type, row.Load_Match_Field__c);
        return new Import_Template__c(
            Name = row.MasterLabel,
            Description__c = row.Description__c,
            Template_Key__c = row.Template_Key__c,
            Column_Mapping_JSON__c = row.Column_Mapping_JSON__c,
            Default_Values_JSON__c = row.Default_Values_JSON__c,
            Matching_Rule__c = normalizedRule(row.Matching_Rule__c),
            Person_Mode__c = personMode,
            Is_Package_Default__c = true,
            Is_Recurring__c = false,
            Active__c = row.Default_Active__c == true,
            Target_Object__c = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            Load_Operation__c = operation,
            Load_Match_Field__c = needsField && matchToken != null
                ? matchToken.getDescribe().getName()
                : null,
            Lookup_Not_Found__c = ImportObjectSchema.LOOKUP_REJECT,
            Several_Matches__c = SEVERAL_REJECT
        );
    }

    /** Why a one-object row cannot run on this org's schema, or null when every name exists. */
    private static String oneObjectFieldProblem(
        Schema.SObjectType type,
        Import_Template_Default__mdt row
    ) {
        ImportMapping mapping = ImportMapping.parse(
            row.Column_Mapping_JSON__c,
            row.Default_Values_JSON__c
        );
        for (String attribute : mapping.recordAttributes()) {
            if (
                attribute != null &&
                attribute != 'id' &&
                ImportObjectSchema.fieldNamed(type, attribute) == null
            ) {
                return 'the field ' + attribute + ' is not on ' + row.Target_Object__c;
            }
        }
        Map<String, String> lookups = mapping.lookupFieldsByAttribute();
        for (String attribute : lookups.keySet()) {
            Schema.SObjectField token = ImportObjectSchema.fieldNamed(type, attribute);
            Boolean found = false;
            if (token != null) {
                for (Schema.SObjectType parent : token.getDescribe().getReferenceTo()) {
                    found = found || ImportObjectSchema.fieldNamed(parent, lookups.get(attribute)) != null;
                }
            }
            if (!found) {
                return 'the lookup field ' + lookups.get(attribute) + ' for ' + attribute + ' is not in this org';
            }
        }
        String operation = row.Load_Operation__c;
        if (
            (operation == ImportObjectSchema.OPERATION_UPSERT ||
            operation == ImportObjectSchema.OPERATION_UPDATE_BY_FIELD) &&
            ImportObjectSchema.fieldNamed(type, row.Load_Match_Field__c) == null
        ) {
            return 'its match field ' + row.Load_Match_Field__c + ' is not on ' + row.Target_Object__c;
        }
        return null;
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
        Import_Template__c template = existing(templateId);
        applyMapping(template, mappingDocument, matchingRule);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** Sets a template's mapping as `saveMapping` saves it, refusing as it does, without saving. */
    private static void applyMapping(
        Import_Template__c template,
        String mappingDocument,
        String matchingRule
    ) {
        ImportMapping mapping = ImportMapping.parse(mappingDocument);
        // A one-object template names no person; its own refusals are asked when its dry run
        // starts, once its load choices are saved too (R-IT12).
        if (!ImportObjectSchema.loadsOneObject(template) && !mapping.identifiesSomebody()) {
            throw new ImportException(Label.Core_Import_ErrorMappingIdentifiesNobody);
        }
        // A broken step is skipped on read, so it is refused here, where the admin can fix it.
        List<String> changeProblems = mapping.transformProblems();
        changeProblems.addAll(ImportRowFilter.problems(mapping));
        if (!changeProblems.isEmpty()) {
            throw new ImportException(String.join(changeProblems, ' '));
        }
        template.Column_Mapping_JSON__c = mapping.serialize();
        template.Matching_Rule__c = normalizedRule(matchingRule);
    }

    /** The payment matching behaviours a template can hold (R-IT7, R-DM5). */
    @NamespaceAccessible
    public static final List<String> PAYMENT_MATCHING_VALUES = new List<String>{
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
    public static Import_Template__c savePaymentMatching(
        Id templateId,
        String behaviour,
        Integer windowDays,
        Decimal tolerance
    ) {
        Import_Template__c template = existing(templateId);
        applyPaymentMatching(template, behaviour, windowDays, tolerance);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** Sets a template's payment matching as `savePaymentMatching` saves it, without saving. */
    private static void applyPaymentMatching(
        Import_Template__c template,
        String behaviour,
        Integer windowDays,
        Decimal tolerance
    ) {
        String chosen = null;
        for (String value : PAYMENT_MATCHING_VALUES) {
            if (String.isNotBlank(behaviour) && value.equalsIgnoreCase(behaviour.trim())) {
                chosen = value;
            }
        }
        if (String.isNotBlank(behaviour) && chosen == null) {
            throw new ImportException(Label.Core_Import_ErrorPaymentMatchingUnknown);
        }
        if (
            (windowDays != null && (windowDays < 0 || windowDays > 999)) ||
            (tolerance != null &&
            tolerance < 0)
        ) {
            throw new ImportException(Label.Core_Import_ErrorPaymentMatchingRange);
        }
        template.Payment_Matching__c = chosen;
        template.Match_Date_Window_Days__c = windowDays;
        template.Match_Amount_Tolerance__c = tolerance == null ? null : tolerance.setScale(2);
    }

    /**
     * Everything the wizard saves on a template when a file is previewed: the mapping and person
     * rule always, and payment matching, load and matching choices when it sent them.
     */
    @NamespaceAccessible
    public class UploadChoices {
        @NamespaceAccessible
        public String mappingDocument;
        @NamespaceAccessible
        public String matchingRule;
        /** True when the wizard showed the payment matching choices, which are then saved. */
        @NamespaceAccessible
        public Boolean savePaymentMatching;
        @NamespaceAccessible
        public String paymentMatching;
        @NamespaceAccessible
        public Integer matchDateWindowDays;
        @NamespaceAccessible
        public Decimal matchAmountTolerance;
        @NamespaceAccessible
        public LoadChoices load;
        @NamespaceAccessible
        public MatchingChoices matching;
    }

    /**
     * Saves what the wizard settled on for one upload in one read and one write, refusing as
     * each separate save would. The person rule in the matching choices is the mapping's.
     */
    @NamespaceAccessible
    public static Import_Template__c saveUpload(Id templateId, UploadChoices choices) {
        Import_Template__c template = existing(templateId);
        applyMapping(template, choices.mappingDocument, choices.matchingRule);
        if (choices.savePaymentMatching == true) {
            applyPaymentMatching(
                template,
                choices.paymentMatching,
                choices.matchDateWindowDays,
                choices.matchAmountTolerance
            );
        }
        if (choices.load != null) {
            applyLoad(template, choices.load);
        }
        if (choices.matching != null) {
            choices.matching.personRule = choices.matchingRule;
            applyMatching(template, choices.matching);
        }
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** The template, refused with the usual message when it is gone. */
    private static Import_Template__c existing(Id templateId) {
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
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
