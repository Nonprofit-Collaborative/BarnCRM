/**
 * Donor segments (feature G-28, canonical model Section 25O): the starter templates, saving one
 * as a segment, its count, list and exports, and every refusal the page can meet.
 */
@IsTest(testFor='ApexClass:DonorSegmentController')
private class DonorSegmentControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    /** A person with giving rollups set as the engine would leave them. */
    private static Contact donor(String lastName, Decimal lastYear, Decimal thisYear) {
        return new Contact(
            FirstName = 'Pat',
            LastName = lastName,
            Email = lastName.toLowerCase() + '@example.org',
            Giving_Last_Year__c = lastYear,
            Giving_This_Year__c = thisYear
        );
    }

    private static void insertDonors(List<SObject> records) {
        // Rollup fields are read only to every packaged set: the engine writes them.
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static String messageOf(Exception caught) {
        return caught.getMessage();
    }

    @IsTest
    static void everyTemplateBuildsAQueryFindCanRunForPeopleAndOrganizations() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<DonorSegmentTemplates.Template> templates = DonorSegmentTemplates.all();
            Assert.areEqual(5, templates.size(), 'Five starter templates ship (R-DS2).');
            for (DonorSegmentTemplates.Template template : templates) {
                Assert.isTrue(String.isNotBlank(template.label), 'Each template has a name.');
                Assert.isTrue(String.isNotBlank(template.description), 'And says what it finds.');
                for (String objectName : new List<String>{ 'Contact', 'Account' }) {
                    QueryCompiler.compile(DonorSegmentTemplates.document(template.key, objectName));
                }
            }

            Map<String, Object> people = (Map<String, Object>) JSON.deserializeUntyped(
                DonorSegmentTemplates.document('lapsed', 'Contact')
            );
            List<Object> fields = (List<Object>) people.get('fields');
            Assert.areEqual('Email', fields[1], 'People carry their email after their name.');
            Map<String, Object> filter = (Map<String, Object>) people.get('filter');
            Assert.areEqual(
                '(1 AND (2 OR 3)) AND 4',
                filter.get('logic'),
                'The added condition is joined by AND and keeps the template logic intact.'
            );
            Map<String, Object> organizations = (Map<String, Object>) JSON.deserializeUntyped(
                DonorSegmentTemplates.document('new', 'Account')
            );
            Assert.isFalse(
                ((List<Object>) organizations.get('fields')).contains('Email'),
                'An account has no Email field.'
            );
        }
    }

    @IsTest
    static void aTemplateSavedAsASegmentIsCountedListedAndReplacedByName() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact lapsed = donor('Lapsed', 100, 0);
            Contact blankThisYear = donor('Blank', 40, null);
            Contact stillGiving = donor('Giving', 100, 50);
            Contact deceased = donor('Gone', 100, 0);
            deceased.Deceased__c = true;
            insertDonors(new List<SObject>{ lapsed, blankThisYear, stillGiving, deceased });

            DonorSegmentController.PageModel page = DonorSegmentController.saveFromTemplate(
                'lapsed',
                'Contact',
                '  Lapsed people  '
            );
            Assert.isNotNull(page.savedId, 'The page is told which segment was written.');
            Assert.areEqual(5, page.templates.size(), 'The page offers the templates.');
            Assert.isTrue(String.isNotBlank(page.findTabApiName), 'And says where Find is.');
            Assert.isTrue(page.exportLimit > 0, 'And how many rows an export may hold.');
            DonorSegmentService.Segment listed;
            for (DonorSegmentService.Segment segment : page.segments) {
                if (segment.recordId == page.savedId) {
                    listed = segment;
                }
            }
            Assert.isNotNull(listed, 'The new segment is listed.');
            Assert.areEqual('Lapsed people', listed.name, 'Saved under the trimmed name.');
            Assert.isTrue(listed.people && listed.mine, 'A segment of the person own people.');
            Assert.isFalse(listed.shared, 'Saved unshared.');

            DonorSegmentService.SegmentCount counted = DonorSegmentController.countSegment(
                page.savedId
            );
            Assert.areEqual(
                2,
                counted.count,
                'Lapsed counts gave-last-year donors with nothing or a blank this year, never the deceased.'
            );
            Assert.isFalse(counted.more, 'Well under the count cap.');

            DonorSegmentService.Rows rows = DonorSegmentController.listSegment(page.savedId);
            Assert.areEqual(2, rows.rows.size(), 'The list shows the same people.');
            Assert.areEqual('Name', rows.columns[0].path, 'Columns follow the segment.');
            Assert.areEqual(
                'Lapsed',
                String.valueOf(rows.rows[0].get('Name')).substringAfter(' '),
                'Ordered by giving last year, largest first.'
            );

            DonorSegmentController.PageModel again = DonorSegmentController.saveFromTemplate(
                'upgraders',
                'Contact',
                'Lapsed people'
            );
            Assert.areEqual(
                page.savedId,
                again.savedId,
                'Saving under a name the person already used replaces that query (R-DS1).'
            );
            Assert.areEqual(
                0,
                DonorSegmentController.countSegment(again.savedId).count,
                'It now holds the upgraders, and nobody gave more this year than last.'
            );
        }
    }

    @IsTest
    static void aFindQueryOfTheSameNameOnAnotherObjectIsNotReplaced() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Saved_Query__c giftSearch = new Saved_Query__c(
                Name = 'Lapsed',
                Object_Name__c = 'Gift__c',
                Query_JSON__c = '{"object":"Gift__c"}',
                Shared__c = false
            );
            insert giftSearch;

            DonorSegmentController.PageModel page = DonorSegmentController.saveFromTemplate(
                'lapsed',
                'Contact',
                'Lapsed'
            );

            Assert.areNotEqual(giftSearch.Id, page.savedId, 'A new segment, not the gift search.');
            Assert.areEqual(
                'Gift__c',
                [SELECT Object_Name__c FROM Saved_Query__c WHERE Id = :giftSearch.Id]
                .Object_Name__c,
                'The gift search is untouched.'
            );
        }
    }

    @IsTest
    static void emailExportsLeaveOutWhoCannotBeEmailedAndAllColumnsKeepsTheSegment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact reachable = donor('Reachable', 100, 0);
            Contact optedOut = donor('OptedOut', 100, 0);
            optedOut.HasOptedOutOfEmail = true;
            Contact noEmail = donor('NoEmail', 100, 0);
            noEmail.Email = null;
            insertDonors(new List<SObject>{ reachable, optedOut, noEmail });
            Id segmentId = DonorSegmentController.saveFromTemplate('lapsed', 'Contact', 'Lapsed')
                .savedId;

            for (String layout : new List<String>{ 'mailchimp', 'constantContact' }) {
                DonorSegmentService.Rows page = DonorSegmentController.exportPage(
                    segmentId,
                    layout,
                    null
                );
                Assert.areEqual(1, page.rows.size(), 'Only the emailable person: ' + layout);
                Assert.areEqual('reachable@example.org', page.rows[0].get('Email'), layout);
                Assert.areEqual(
                    DonorSegmentService.EMAIL_FIELDS.size(),
                    page.columns.size(),
                    'The email columns the page lays out per tool.'
                );
                Assert.isTrue(page.done, 'One page holds them all.');
                Assert.areEqual(String.valueOf(reachable.Id), page.lastId, 'Paged by Id.');
            }

            DonorSegmentService.Rows all = DonorSegmentController.exportPage(segmentId, 'all', '');
            Assert.areEqual(3, all.rows.size(), 'All Columns is the whole segment.');
            Assert.areEqual(6, all.columns.size(), 'With the segment own columns.');

            DonorSegmentService.Rows after = DonorSegmentController.exportPage(
                segmentId,
                'all',
                all.lastId
            );
            Assert.areEqual(0, after.rows.size(), 'Nothing after the last Id read.');
            Assert.areEqual(all.lastId, after.lastId, 'An empty page keeps the last Id.');
        }
    }

    @IsTest
    static void organizationSegmentsExportAllColumnsOnly() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account organization = AccountKindsTestData.organization('Acme Foundation');
            organization.Giving_Last_Year__c = 500;
            insertDonors(new List<SObject>{ organization });
            Id segmentId = DonorSegmentController.saveFromTemplate(
                    'lapsed',
                    'Account',
                    'Lapsed organizations'
                )
                .savedId;
            Integer expected = [
                SELECT COUNT()
                FROM Account
                WHERE Id = :organization.Id AND Is_Organization__c = TRUE
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(
                expected,
                DonorSegmentController.countSegment(segmentId).count,
                'An account counts only when it is an organization.'
            );
            Assert.areEqual(
                expected,
                DonorSegmentController.exportPage(segmentId, 'all', null).rows.size(),
                'All Columns exports organizations.'
            );
            try {
                DonorSegmentController.exportPage(segmentId, 'mailchimp', null);
                Assert.fail('An email layout needs people.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(System.Label.Giving_Segments_ErrorPeopleOnly, messageOf(refused));
            }
            try {
                DonorSegmentController.exportPage(segmentId, 'fax', null);
                Assert.fail('Only the three layouts exist.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(System.Label.Giving_Segments_ErrorLayout, messageOf(refused));
            }
        }
    }

    @IsTest
    static void whatThePageRefusesItSaysWhy() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Saved_Query__c gifts = new Saved_Query__c(
                Name = 'Big gifts',
                Object_Name__c = 'Gift__c',
                Query_JSON__c = '{"version":1,"object":"Gift__c","fields":["Name"]}'
            );
            insert gifts;
            Map<String, String> expected = new Map<String, String>{
                'gifts' => System.Label.Giving_Segments_ErrorNotSegment,
                'missing' => System.Label.Giving_Segments_ErrorNotFound,
                'name' => System.Label.Giving_Segments_ErrorName,
                'template' => System.Label.Giving_Segments_ErrorTemplate
            };
            for (String attempt : expected.keySet()) {
                try {
                    switch on attempt {
                        when 'gifts' {
                            DonorSegmentController.countSegment(gifts.Id);
                        }
                        when 'missing' {
                            DonorSegmentController.listSegment('not an id');
                        }
                        when 'name' {
                            DonorSegmentController.saveFromTemplate('lapsed', 'Contact', ' ');
                        }
                        when else {
                            DonorSegmentController.saveFromTemplate('lapsed', 'Gift__c', 'Gifts');
                        }
                    }
                    Assert.fail('Refused: ' + attempt);
                } catch (AuraHandledException refused) {
                    Assert.areEqual(expected.get(attempt), messageOf(refused), attempt);
                }
            }
        }
    }

    @IsTest
    static void withoutFindThePageIsClosed() {
        User staffOnly = TestUsers.withPermissionSets(
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
        System.runAs(staffOnly) {
            try {
                DonorSegmentController.getPage();
                Assert.fail('Segments are Find queries, so Find is required (R-DS6).');
            } catch (AuraHandledException refused) {
                Assert.areEqual(System.Label.Giving_Segments_ErrorNoPermission, messageOf(refused));
            }
        }
    }

    // runs-as: deploying user (pure logic: joins conditions to a filter map, no DML or SOQL)
    @IsTest
    static void aJoinedConditionTakesTheNextNumberAndKeepsAnyLogic() {
        Map<String, Object> plain = new Map<String, Object>{ 'version' => 1 };
        DonorSegmentService.andCondition(
            plain,
            DonorSegmentService.condition('Email', 'is not null', null)
        );
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) plain.get(
            'conditions'
        ))[0];
        Assert.areEqual(1, first.get('id'), 'An empty filter starts at 1.');
        Assert.isFalse(first.containsKey('value'), 'A null test carries no value.');
        Assert.isNull(plain.get('logic'), 'No logic means every condition is joined by AND.');

        Map<String, Object> withLogic = (Map<String, Object>) JSON.deserializeUntyped(
            '{"version":1,"logic":"1 OR 7","conditions":[{"id":1},{"id":7}]}'
        );
        DonorSegmentService.andCondition(
            withLogic,
            DonorSegmentService.condition('Email', 'equals', 'a')
        );
        Assert.areEqual('(1 OR 7) AND 8', withLogic.get('logic'), 'Numbered after the highest.');
    }
}
