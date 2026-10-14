/**
 * Column changes in an import mapping (canonical model R-IT15): a row's values are changed
 * before they are matched and saved, in the dry run as in the commit; a broken change is
 * refused when the mapping is saved; the wizard's preview and the dry run's changed values
 * show each value before and after. The 200-row case runs as a minimal-profile user holding
 * only BarnCRM Admin, since every read and save of an import is in that user's own mode.
 */
@IsTest(testFor='ApexClass:DataTransform, ApexClass:ImportMapping')
private class ImportTransformTest {
    private static final Integer MANY = 200;
    private static final Integer ALREADY_THERE = 10;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static DataTransform.Step step(String op) {
        return new DataTransform.Step(op);
    }

    /** A people mapping whose email, last name and birthdate columns are changed as they load. */
    private static ImportMapping changingMapping() {
        DataTransform.Step at = step(DataTransform.OP_REPLACE);
        at.text = ' at ';
        at.replaceWith = '@';
        DataTransform.Step born = step(DataTransform.OP_DATE);
        born.dateOrder = 'DMY';
        ImportMapping mapping = new ImportMapping();
        ImportMapping.Column email = new ImportMapping.Column('E-mail', 'Contact1.Email');
        email.transforms = new List<DataTransform.Step>{ step('trim'), at, step('lower') };
        ImportMapping.Column surname = new ImportMapping.Column('Surname', 'Contact1.LastName');
        surname.transforms = new List<DataTransform.Step>{ step('proper') };
        ImportMapping.Column birthdate = new ImportMapping.Column('Born', 'Contact1.Birthdate');
        birthdate.transforms = new List<DataTransform.Step>{ born };
        mapping.columns.add(new ImportMapping.Column('First', 'Contact1.FirstName'));
        mapping.columns.add(email);
        mapping.columns.add(surname);
        mapping.columns.add(birthdate);
        return mapping;
    }

    private static Map<String, String> row(Integer i) {
        return new Map<String, String>{
            'First' => 'Ana',
            'E-mail' => '  PERSON' +
            i +
            ' AT Example.org ',
            'Surname' => 'RIVERA-LOPEZ',
            'Born' => '31/12/1980'
        };
    }

    private static ImportRowProcessor.Outcome run(
        Import_Template__c template,
        Import_Batch__c batch,
        Boolean dryRun
    ) {
        ImportBatchService.beginPass(batch.Id);
        return ImportRowProcessor.process(
            ImportBatchSelector.selectById(batch.Id),
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    @IsTest
    static void twoHundredRowsAreChangedBeforeTheyAreMatchedAndSaved() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Contact> existing = new List<Contact>();
                for (Integer i = 0; i < ALREADY_THERE; i++) {
                    existing.add(
                        new Contact(
                            FirstName = 'Ana',
                            LastName = 'Old',
                            Email = 'person' + i + '@example.org'
                        )
                    );
                }
                insert existing;
                Import_Template__c template = ImportTestDataFactory.template(
                    changingMapping().serialize(),
                    ImportTemplateService.RULE_EMAIL
                );
                template = ImportTemplateSelector.selectById(template.Id);
                Import_Batch__c batch = ImportTestDataFactory.batch(template);
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY; i++) {
                    values.add(row(i));
                }
                ImportTestDataFactory.rows(batch, values);

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(template, batch, true);
                Integer contactsAfterPreview = [SELECT COUNT() FROM Contact];
                ImportRowProcessor.Outcome committed = run(template, batch, false);
                Test.stopTest();

                Assert.areEqual(
                    MANY - ALREADY_THERE,
                    preview.created,
                    'Changed emails match the ten.'
                );
                Assert.areEqual(ALREADY_THERE, contactsAfterPreview, 'The dry run writes nothing.');
                Assert.areEqual(
                    MANY - ALREADY_THERE,
                    committed.created,
                    'The commit decides alike.'
                );
                Assert.areEqual(MANY, [SELECT COUNT() FROM Contact], 'Nobody was created twice.');
                Contact made = [
                    SELECT Email, LastName, Birthdate
                    FROM Contact
                    WHERE Email = 'person150@example.org'
                    LIMIT 1
                ];
                Assert.areEqual('person150@example.org', made.Email);
                Assert.areEqual(
                    'Rivera-Lopez',
                    made.LastName,
                    'The surname is capitalized per word.'
                );
                Assert.areEqual(Date.newInstance(1980, 12, 31), made.Birthdate, 'Read day first.');
            }

        }
    }

    @IsTest
    static void aBrokenChangeIsRefusedWhenTheMappingIsSavedNamingTheColumn() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportMapping mapping = changingMapping();
                mapping.columns[2].transforms.add(step(DataTransform.OP_REPLACE));
                Import_Template__c template = ImportTestDataFactory.template(
                    new ImportMapping().serialize(),
                    ImportTemplateService.RULE_EMAIL
                );

                Test.startTest();
                String refusal;
                try {
                    ImportTemplateService.saveMapping(
                        template.Id,
                        mapping.serialize(),
                        ImportTemplateService.RULE_EMAIL
                    );
                } catch (ImportException e) {
                    refusal = e.getMessage();
                }
                Test.stopTest();

                Assert.isNotNull(refusal, 'A replace with nothing to find is refused.');
                Assert.isTrue(refusal.contains('Surname'), 'The column is named: ' + refusal);
                Assert.isTrue(refusal.contains(Label.Core_Transform_ErrorNeedsText), refusal);
            }

        }
    }

    @IsTest
    static void theChangesAreSavedWithTheMapping() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Import_Template__c template = ImportTestDataFactory.template(
                    new ImportMapping().serialize(),
                    ImportTemplateService.RULE_EMAIL
                );

                Test.startTest();
                ImportTemplateService.saveMapping(
                    template.Id,
                    changingMapping().serialize(),
                    ImportTemplateService.RULE_EMAIL
                );
                Test.stopTest();

                ImportMapping saved = ImportMapping.parse(
                    ImportTemplateSelector.selectById(template.Id).Column_Mapping_JSON__c
                );
                Map<String, List<DataTransform.Step>> changes = saved.transformsBySourceKey();
                Assert.areEqual(3, changes.size(), 'Three columns have changes.');
                Assert.areEqual(3, changes.get('e-mail').size(), 'In order.');
                Assert.areEqual('@', changes.get('e-mail')[1].replaceWith);
                Assert.areEqual('DMY', changes.get('born')[0].dateOrder);
            }

        }
    }

    @IsTest
    static void aColumnSetToDoNotLoadHasNoChangesThatRun() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = changingMapping();
            mapping.columns[1].target = ImportMapping.TARGET_IGNORE;
            Assert.isFalse(mapping.transformsBySourceKey().containsKey('e-mail'));
            Assert.isTrue(mapping.transformsBySourceKey().containsKey('surname'));
        }
    }

    @IsTest
    static void aOneObjectRowIsReadAfterItsChanges() {
        System.runAs(TestUsers.admin()) {
            DataTransform.Step fill = step(DataTransform.OP_IF_BLANK);
            fill.value = 'Imported';
            ImportMapping mapping = new ImportMapping();
            ImportMapping.Column reason = new ImportMapping.Column('Reason', 'Record.Reason__c');
            reason.transforms = new List<DataTransform.Step>{ fill };
            mapping.columns.add(reason);
            Import_Row__c staged = new Import_Row__c(Raw_Values_JSON__c = '{"Reason":" "}');

            Map<String, String> record = ImportRowProcessor.valuesByEntity(staged, mapping)
                .get(ImportMapping.ENTITY_RECORD);

            Assert.areEqual('Imported', record.get('Reason__c'), 'A blank cell is filled.');
        }
    }

    @IsTest
    static void theWizardPreviewShowsBeforeAndAfterAndWhatIsWrong() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            List<Map<String, String>> sample = new List<Map<String, String>>();
            for (Integer i = 0; i < 7; i++) {
                sample.add(new Map<String, String>{ 'First' => 'ana', 'Middle' => 'M' });
            }
            DataTransform.Step add = step(DataTransform.OP_APPEND);
            add.columns = new List<String>{ 'Middle' };

            Test.startTest();
            ImportController.ChangesPreview good = ImportController.previewChanges(
                'First',
                JSON.serialize(new List<DataTransform.Step>{ step('proper'), add }),
                JSON.serialize(sample)
            );
            ImportController.ChangesPreview broken = ImportController.previewChanges(
                'First',
                '[{"op":"ifBlank"}]',
                JSON.serialize(sample)
            );
            Test.stopTest();

            Assert.areEqual(5, good.samples.size(), 'Only the first rows are shown.');
            Assert.areEqual('ana', good.samples[0].before);
            Assert.areEqual('Ana M', good.samples[0].after);
            Assert.areEqual(
                2,
                good.samples[0].rowNumber,
                'Counted as the file counts, header first.'
            );
            Assert.isTrue(good.problems.isEmpty());
            Assert.isTrue(broken.problems.contains(Label.Core_Transform_ErrorNeedsValue));
        }
    }

    @IsTest
    static void thePreviewNeedsTheImportPermission() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = false;
            Boolean refused = false;
            Test.startTest();
            try {
                ImportController.previewChanges('First', '[]', '[]');
            } catch (AuraHandledException e) {
                refused = true;
            }
            Test.stopTest();
            Assert.isTrue(refused, 'Only someone who may import previews changes.');
        }
    }

    @IsTest
    static void theDryRunShowsEachChangedValueOfTheFirstRows() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                changingMapping().serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 7; i++) {
                Map<String, String> one = row(i);
                one.put('Born', 'not a date');
                values.add(one);
            }
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            List<ImportController.ChangedValue> changed = ImportController.getChangedValues(
                batch.Id
            );
            Test.stopTest();

            Assert.areEqual(
                10,
                changed.size(),
                'Email and surname of five rows; the date did not change.'
            );
            Assert.areEqual(2, changed[0].rowNumber);
            Assert.areEqual('E-mail', changed[0].column);
            Assert.areEqual('PERSON0 AT Example.org', changed[0].before, 'As staged, trimmed.');
            Assert.areEqual('person0@example.org', changed[0].after);
            Assert.areEqual('Rivera-Lopez', changed[1].after);
        }
    }

    @IsTest
    static void aMappingWithoutChangesShowsNone() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Rivera', 'ana@example.org', null)
                }
            );
            Assert.isTrue(ImportController.getChangedValues(batch.Id).isEmpty());
            Assert.isTrue(ImportController.getChangedValues(null).isEmpty(), 'No batch, nothing.');
        }
    }
}
