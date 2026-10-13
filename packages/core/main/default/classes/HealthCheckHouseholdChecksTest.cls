/**
 * Health Check's orphan findings (C-21, ADR-0048): people in no household and households
 * with nobody in them, in both membership modes, with the cases the canonical model says are
 * not orphans, and a Platform-only shape where no person type exists.
 *
 * The people are saved with automatic household creation suspended, which is how an orphan
 * arises in a real org (a load with automation off), and Health Check is then run as Maria,
 * who holds the permission these checks are shown under. Every test states the org shape it
 * runs in, so none depends on whether the org has Person Accounts or Nonprofit Cloud.
 */
@IsTest
private class HealthCheckHouseholdChecksTest {
    private static final String PEOPLE = 'people_without_household';
    private static final String HOUSEHOLDS = 'households_without_members';

    private static void platformOnlyShape() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNativeHouseholdGroups = false;
        OrgShapeDetector.overrideShape = shape;
    }

    private static Id organizationRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static Account newOrganization(String name) {
        return new Account(Name = name, RecordTypeId = organizationRecordTypeId());
    }

    /** Contacts saved the way a load with automation off saves them: with no household made. */
    private static List<Contact> insertWithoutAutomaticHouseholds(List<Contact> contacts) {
        HouseholdService.suspendAutomaticCreation();
        insert contacts;
        HouseholdService.resumeAutomaticCreation();
        return contacts;
    }

    private static HealthCheckService.Finding runAsMaria(String key) {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        HealthCheckService.Finding found;
        System.runAs(maria) {
            for (HealthCheckService.Finding finding : HealthCheckService.run()) {
                if (key.equals(finding.key)) {
                    found = finding;
                }
            }
        }
        return found;
    }

    /** Junction mode, keeping empty households, so a test can leave one empty on purpose. */
    private static void junctionModeKeepingEmptyHouseholds() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_JUNCTION
        );
        settings.Delete_Empty_Households__c = false;
        HouseholdTestDataFactory.save(settings);
    }

    private static Household_Member__c membership(Id contactId, Id householdId, Date ended) {
        return new Household_Member__c(
            Contact__c = contactId,
            Household__c = householdId,
            End_Date__c = ended
        );
    }

    // ------------------------------------------------------------------------ contact mode

    @IsTest
    static void contactModeCountsContactsWithNoAccountAndLinksThem() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account organization = newOrganization('Acme Foundation');
            insert organization;
            Contact staff = HouseholdTestDataFactory.newContact('Sam', 'Staff');
            staff.AccountId = organization.Id;
            List<Contact> orphans = insertWithoutAutomaticHouseholds(
                new List<Contact>{
                    HouseholdTestDataFactory.newContact('Ann', 'Lee'),
                    HouseholdTestDataFactory.newContact('Bo', 'Diaz'),
                    staff
                }
            );
            // Saved with automation on: gets a household, so is not an orphan.
            insert HouseholdTestDataFactory.newContact('Cy', 'Housed');
            platformOnlyShape();

            HealthCheckService.Finding finding = runAsMaria(PEOPLE);

            Assert.isNotNull(finding, 'Contacts with no account are reported.');
            Assert.isTrue(
                finding.title.startsWith('2 '),
                'Two of them: the organization contact belongs to its organization. ' +
                finding.title
            );
            Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning.');
            Assert.isNull(finding.fixTarget, 'Detection only: there is no fix button.');
            Assert.areEqual(2, finding.links.size(), 'Each one is linked.');
            Assert.areEqual(
                '/lightning/r/Contact/' + orphans[0].Id + '/view',
                finding.links[0].url,
                'To its record page, oldest first.'
            );
        }
    }

    @IsTest
    static void contactModeReportsAHouseholdNoContactPointsAt() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account empty = HouseholdTestDataFactory.newHousehold('The Empty Family');
            Account lived = HouseholdTestDataFactory.newHousehold('The Lived Family');
            insert new List<Account>{ empty, lived };
            Contact member = HouseholdTestDataFactory.newContact('Dee', 'Lived');
            member.AccountId = lived.Id;
            insert member;
            platformOnlyShape();

            HealthCheckService.Finding finding = runAsMaria(HOUSEHOLDS);

            Assert.isNotNull(finding, 'A household with nobody in it is reported.');
            Assert.isTrue(finding.title.startsWith('1 '), 'Only the empty one. ' + finding.title);
            Assert.areEqual(HealthCheckService.SEVERITY_INFO, finding.severity, 'Information.');
            Assert.isNull(finding.fixTarget, 'Detection only.');
            Assert.areEqual('The Empty Family', finding.links[0].label, 'It is linked by name.');
        }
    }

    @IsTest
    static void withAutomaticCreationOffAPersonWithNoHouseholdIsExpected() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            insert HouseholdTestDataFactory.newContact('Eve', 'Loose');
            platformOnlyShape();

            Assert.isNull(
                runAsMaria(PEOPLE),
                'With automatic creation off, a person with no household is the org choice (R-C1).'
            );
        }
    }

    @IsTest
    static void nobodyWithoutAHouseholdSaysNothing() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insert HouseholdTestDataFactory.newContact('Flo', 'Housed');
            platformOnlyShape();

            Assert.isNull(runAsMaria(PEOPLE), 'Everyone is in a household.');
            Assert.isNull(runAsMaria(HOUSEHOLDS), 'And the household made for Flo has Flo in it.');
        }
    }

    // ----------------------------------------------------------------------- junction mode

    @IsTest
    static void junctionModeCountsPeopleWithNoCurrentMembership() {
        System.runAs(TestUsers.admin()) {
            junctionModeKeepingEmptyHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Kept Family');
            Account organization = newOrganization('Acme Foundation');
            insert new List<Account>{ household, organization };

            Contact noAccount = HouseholdTestDataFactory.newContact('Gus', 'Alone');
            Contact atOrganization = HouseholdTestDataFactory.newContact('Hal', 'Staff');
            atOrganization.AccountId = organization.Id;
            Contact left = HouseholdTestDataFactory.newContact('Ida', 'Left');
            Contact current = HouseholdTestDataFactory.newContact('Jo', 'Kept');
            Contact linkedDirectly = HouseholdTestDataFactory.newContact('Kai', 'Linked');
            linkedDirectly.AccountId = household.Id;
            insertWithoutAutomaticHouseholds(
                new List<Contact>{ noAccount, atOrganization, left, current, linkedDirectly }
            );
            insert new List<Household_Member__c>{
                membership(left.Id, household.Id, Date.today().addDays(-1)),
                membership(current.Id, household.Id, null)
            };
            platformOnlyShape();

            HealthCheckService.Finding finding = runAsMaria(PEOPLE);

            Assert.isNotNull(finding, 'People with no current membership are reported.');
            Assert.isTrue(
                finding.title.startsWith('3 '),
                'No account, an organization contact, and a membership that ended: three. A ' +
                    'current member is in a household, and a contact linked straight to one is ' +
                    'the membership check to report. ' +
                    finding.title
            );
            Set<String> named = new Set<String>();
            for (HealthCheckService.Link link : finding.links) {
                named.add(link.label);
            }
            Assert.isTrue(
                named.contains('Ida Left'),
                'An ended membership is not a household (R-M2).'
            );
            Assert.isFalse(named.contains('Jo Kept'), 'A current member is not an orphan.');
        }
    }

    @IsTest
    static void junctionModeReportsAHouseholdWhoseMembershipsHaveAllEnded() {
        System.runAs(TestUsers.admin()) {
            junctionModeKeepingEmptyHouseholds();
            Account ended = HouseholdTestDataFactory.newHousehold('The Ended Family');
            Account kept = HouseholdTestDataFactory.newHousehold('The Kept Family');
            insert new List<Account>{ ended, kept };
            Contact former = HouseholdTestDataFactory.newContact('Lu', 'Former');
            Contact present = HouseholdTestDataFactory.newContact('Mo', 'Present');
            insertWithoutAutomaticHouseholds(new List<Contact>{ former, present });
            insert new List<Household_Member__c>{
                membership(former.Id, ended.Id, Date.today().addDays(-1)),
                membership(present.Id, kept.Id, Date.today().addDays(30))
            };
            platformOnlyShape();

            HealthCheckService.Finding finding = runAsMaria(HOUSEHOLDS);

            Assert.isNotNull(finding, 'A household with only ended memberships is reported.');
            Assert.isTrue(finding.title.startsWith('1 '), 'Only that one. ' + finding.title);
            // Upkeep renames a household nobody is in, so it is identified by its record.
            Assert.areEqual(
                '/lightning/r/Account/' + ended.Id + '/view',
                finding.links[0].url,
                'It is the one linked.'
            );
        }
    }

    @IsTest
    static void junctionModeCountsPeopleStoredAsAccountsByTheirPersonType() {
        System.runAs(TestUsers.admin()) {
            junctionModeKeepingEmptyHouseholds();
            // Stands in for a person account type: the selector only ever sees the record type
            // ids the org shape hands it, which is what keeps it free of person account fields.
            Account storedAsAccount = newOrganization('Nia Person');
            insert storedAsAccount;
            Contact itsContact = HouseholdTestDataFactory.newContact('Nia', 'Person');
            itsContact.AccountId = storedAsAccount.Id;
            insertWithoutAutomaticHouseholds(new List<Contact>{ itsContact });
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = false;
            shape.hasPersonAccounts = true;
            shape.personAccountRecordTypeIds = new Set<Id>{ organizationRecordTypeId() };
            OrgShapeDetector.overrideShape = shape;

            HealthCheckService.Finding finding = runAsMaria(PEOPLE);

            Assert.isNotNull(
                finding,
                'A person stored as an account with no membership is reported.'
            );
            Assert.isTrue(
                finding.title.startsWith('1 '),
                'Counted once, as the account, and not again as its contact. ' + finding.title
            );
            Assert.isTrue(
                finding.links[0].url.startsWith('/lightning/r/Account/'),
                'Linked to the account that is the person.'
            );
        }
    }

    // ------------------------------------------------------------------ shape and wording

    @IsTest
    static void aLargeCountIsCappedAndSaidAsMoreThan() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insertWithoutAutomaticHouseholds(
                new List<Contact>{
                    HouseholdTestDataFactory.newContact('Oz', 'One'),
                    HouseholdTestDataFactory.newContact('Pia', 'Two'),
                    HouseholdTestDataFactory.newContact('Quin', 'Three')
                }
            );
            platformOnlyShape();
            HealthCheckHouseholdChecks.countCap = 2;

            HealthCheckService.Finding finding = runAsMaria(PEOPLE);

            Assert.isTrue(
                finding.title.startsWith(
                    String.format(
                        System.Label.Core_HealthCheck_OrphansMoreThan,
                        new List<Object>{ '2' }
                    )
                ),
                'Past the cap the count is not taken: it says more than. ' + finding.title
            );
        }
    }

    @IsTest
    static void anOrgWithNonprofitCloudHouseholdsIsToldSomeMayBeInOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insertWithoutAutomaticHouseholds(
                new List<Contact>{ HouseholdTestDataFactory.newContact('Rae', 'Native') }
            );
            OrgShapeDetector.overrideShape = new OrgShapeDetector.OrgShape();

            HealthCheckService.Finding finding = runAsMaria(PEOPLE);

            Assert.isTrue(
                finding.detail.contains(System.Label.Core_HealthCheck_OrphansNativeNote),
                'BarnCRM cannot see native membership, and says so (R-H12).'
            );
        }
    }

    @IsTest
    static void theOrphanCountsAreShownOnlyToSomebodyWhoManagesSettings() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insertWithoutAutomaticHouseholds(
                new List<Contact>{ HouseholdTestDataFactory.newContact('Sol', 'Loose') }
            );
            platformOnlyShape();
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                for (HealthCheckService.Finding finding : HealthCheckService.run()) {
                    Assert.areNotEqual(
                        PEOPLE,
                        finding.key,
                        'A count from her access would be wrong.'
                    );
                    Assert.areNotEqual(HOUSEHOLDS, finding.key, 'So neither is shown.');
                }
            }

        }
    }
}
