/**
 * The mapping document: parsing, the entity and attribute halves of a target, and the check
 * that refuses a mapping which identifies nobody.
 */
// runs-as: deploying user (pure logic: parses and checks a mapping document, no DML or SOQL)
@IsTest(testFor='ApexClass:ImportMapping')
private class ImportMappingTest {
    @IsTest
    static void parsesAMappingDocument() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        Assert.areEqual(
            DataTransform.DOCUMENT_VERSION,
            mapping.version,
            'A new document carries the current version (ADR-0112).'
        );
        Assert.areEqual(5, mapping.columns.size(), 'Every column is read.');
        Assert.areEqual(
            'Contact1.Email',
            mapping.targetsBySourceKey().get('email'),
            'A column is found by its name folded to lower case.'
        );
    }

    @IsTest
    static void anUnreadableDocumentIsAnEmptyMapping() {
        ImportMapping mapping = ImportMapping.parse('this is not JSON');
        Assert.isTrue(mapping.columns.isEmpty(), 'Nothing is read from an unreadable document.');
        Assert.isFalse(
            mapping.identifiesSomebody(),
            'An empty mapping identifies nobody, which is what the caller reports.'
        );
    }

    @IsTest
    static void aBlankDocumentIsAnEmptyMapping() {
        Assert.isTrue(
            ImportMapping.parse(null).columns.isEmpty(),
            'A null document reads as an empty mapping rather than throwing.'
        );
        Assert.isTrue(ImportMapping.parse('').columns.isEmpty(), 'So does a blank one.');
    }

    @IsTest
    static void readsTheDefaultsDocumentSeparately() {
        ImportMapping mapping = ImportMapping.parse(
            ImportTestDataFactory.donorMapping(),
            '{"version":1,"defaults":[{"target":"Contact1.MailingCountry","value":"United States"}]}'
        );
        Assert.areEqual(1, mapping.defaults.size(), 'The defaults come from the second document.');
        Assert.areEqual('United States', mapping.defaults[0].value, 'With their value intact.');
    }

    @IsTest
    static void splitsATargetIntoItsEntityAndAttribute() {
        Assert.areEqual('Contact1', ImportMapping.entityOf('Contact1.Email'), 'Entity half.');
        Assert.areEqual('Email', ImportMapping.attributeOf('Contact1.Email'), 'Attribute half.');
        Assert.isNull(ImportMapping.entityOf('Email'), 'A target with no dot names no entity.');
        Assert.isNull(
            ImportMapping.attributeOf('Contact1.'),
            'Nor does one with nothing after it.'
        );
    }

    @IsTest
    static void treatsUnusableTargetsAsIgnored() {
        Assert.isTrue(ImportMapping.isIgnored(null), 'A blank target loads nothing.');
        Assert.isTrue(ImportMapping.isIgnored('Ignore'), 'So does the ignore target.');
        Assert.isTrue(ImportMapping.isIgnored('Nonsense'), 'So does one that names no entity.');
        Assert.isFalse(ImportMapping.isIgnored('Contact1.Email'), 'A real target is not ignored.');
    }

    @IsTest
    static void namesTheColumnsSetToDoNotLoad() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column(' Email ', 'Ignore'));
        mapping.columns.add(new ImportMapping.Column('Notes', null));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        Assert.areEqual(
            new Set<String>{ 'email' },
            mapping.ignoredSourceKeys(),
            'Only a column explicitly set to Do not load, keyed as a header row is matched.'
        );
        Assert.isFalse(
            mapping.targetsBySourceKey().containsKey('email'),
            'Loading a row still leaves it out.'
        );
    }

    @IsTest
    static void aMappingWithOnlyAnAddressIdentifiesNobody() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('City', 'Contact1.MailingCity'));
        Assert.isFalse(
            mapping.identifiesSomebody(),
            'An address alone cannot say who a row is about, so the run is refused.'
        );
    }

    @IsTest
    static void anEmailOrANameOrAnOrganizationIdentifiesSomebody() {
        for (
            String target : new List<String>{
                'Contact1.Email',
                'Contact1.LastName',
                'Contact1.FullName',
                'Organization.Name'
            }
        ) {
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('A column', target));
            Assert.isTrue(mapping.identifiesSomebody(), target + ' identifies somebody.');
        }
    }

    @IsTest
    static void reportsTheEntitiesCoreCannotLoad() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
        mapping.columns.add(new ImportMapping.Column('Fund', 'Allocation.Fund'));
        Set<String> deferred = mapping.deferredEntities();
        Assert.areEqual(2, deferred.size(), 'The gift and the allocation are both deferred.');
        Assert.isTrue(deferred.contains('Gift'), 'The gift is one of them.');
        Assert.isFalse(deferred.contains('Contact1'), 'A person is not: Core loads people.');
    }

    @IsTest
    static void roundTripsThroughItsOwnDocument() {
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        ImportMapping again = ImportMapping.parse(mapping.serialize());
        Assert.areEqual(
            mapping.targetsBySourceKey(),
            again.targetsBySourceKey(),
            'A mapping saved and read again is the same mapping.'
        );
    }

    @IsTest
    static void aOneObjectMappingKeepsItsLookupFieldsAndRecordAttributes() {
        ImportMapping mapping = ImportMapping.parse(
            '{"columns":[' +
                '{"source":"Program","target":"Record.Program__c","lookupField":"Code__c"},' +
                '{"source":"Person","target":"Record.Contact__c","lookupField":"Id"},' +
                '{"source":"Hours","target":"Record.Hours__c"},' +
                '{"source":"Email","target":"Contact1.Email","lookupField":"Name"}],' +
                '"defaults":[{"target":"Record.Status__c","value":"Done"}]}'
        );

        ImportMapping again = ImportMapping.parse(mapping.serialize());

        Assert.areEqual(
            new Map<String, String>{ 'program__c' => 'Code__c' },
            again.lookupFieldsByAttribute(),
            'Only a Record lookup named by a field other than the ID.'
        );
        Assert.areEqual(
            new Set<String>{ 'program__c', 'contact__c', 'hours__c', 'status__c' },
            again.recordAttributes(),
            'Columns and values for every row, folded to lower case.'
        );
    }

    @IsTest
    static void aSeveralObjectMappingReadsAsEachObjectsOwnRecordColumns() {
        ImportMapping mapping = ImportMapping.parse(
            '{"objects":[{"entity":"Program__c","operation":"Insert"},' +
                '{"entity":"Session__c","operation":"Upsert by external ID","keyField":"Code__c"}],' +
                '"columns":[' +
                '{"source":"Program","target":"Program__c.Name","transforms":[{"op":"trim"}]},' +
                '{"source":"Code","target":"Session__c.Code__c","blankClears":true},' +
                '{"source":"Leader","target":"session__c.Leader__c","lookupField":"Email"},' +
                '{"source":"Skip","target":"Ignore"}],' +
                '"defaults":[{"target":"Session__c.Status__c","value":"Planned"}]}'
        );

        ImportMapping sessions = mapping.forEntity('Session__c');

        Assert.isTrue(mapping.loadsSeveralObjects(), 'The objects are read.');
        Assert.areEqual('Code__c', mapping.objects[1].keyField, 'With their keys.');
        Assert.isFalse(sessions.loadsSeveralObjects(), 'One object is a one-object mapping.');
        Assert.areEqual(
            new Set<String>{ 'code__c', 'leader__c', 'status__c' },
            sessions.recordAttributes(),
            'Its own columns and values, any capitals, as Record attributes.'
        );
        Assert.areEqual(
            new Map<String, String>{ 'leader__c' => 'Email' },
            sessions.lookupFieldsByAttribute(),
            'With their lookups.'
        );
        Assert.areEqual(new Set<String>{ 'code__c' }, sessions.clearingAttributes(), 'Clears.');
        Assert.areEqual(
            1,
            mapping.forEntity('Program__c').transformsBySourceKey().get('program').size(),
            'And changes.'
        );
        Assert.isFalse(new ImportMapping().loadsSeveralObjects(), 'None by default.');
    }
}
