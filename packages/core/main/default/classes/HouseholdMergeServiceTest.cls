/**
 * Combining and separating households, in both membership modes.
 * Canonical model R-H11, R-H12, R-H13.
 */
@IsTest(testFor='ApexClass:HouseholdMergeService')
private class HouseholdMergeServiceTest {
    private static final String CONTACT_RELATION = 'AccountContactRelation'; // detection-only: describe key, so the real shared-relation merge runs only where Contacts to Multiple Accounts is on
    private static final String RELATION_COUNT_QUERY = 'SELECT COUNT() FROM AccountContactRelation WHERE Id = :relationId'; // detection-only: whether a refused merge left a relation in place, asked only where the object exists

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    // ------------------------------------------------------------------ preview

    @IsTest
    static void previewShowsWhereTheTwoHouseholdsDisagree() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            survivor.BillingCity = 'Oakland';
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            victim.BillingCity = 'Oakland';
            victim.Anniversary__c = Date.newInstance(2010, 6, 12);
            insert new List<Account>{ survivor, victim };

            Test.startTest();
            HouseholdMergeService.MergePreview preview = HouseholdMergeService.preview(
                survivor.Id,
                victim.Id
            );
            Test.stopTest();

            Assert.areEqual('The Garcia Family', preview.survivorName, 'The survivor is named');
            Assert.areEqual('Garcia Household', preview.victimName, 'The other household is named');
            Map<String, HouseholdMergeService.FieldChoice> byField = byFieldName(preview);
            Assert.isTrue(byField.get('Name').inConflict, 'The two names disagree');
            Assert.isTrue(byField.get('Anniversary__c').inConflict, 'Only one has an anniversary');
            Assert.isFalse(byField.get('BillingCity').inConflict, 'Both are in the same city');
            Assert.isFalse(
                byField.get('BillingStreet').inConflict,
                'Two empty values are not a disagreement'
            );
        }
    }

    @IsTest
    static void previewListsEveryoneFromBothHouseholds() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);

            Test.startTest();
            HouseholdMergeService.MergePreview preview = HouseholdMergeService.preview(
                survivorId,
                victimId
            );
            Test.stopTest();

            Assert.areEqual(2, preview.members.size(), 'Both people are listed');
            Set<String> names = new Set<String>();
            for (HouseholdMergeService.MemberChoice member : preview.members) {
                names.add(member.name);
            }
            Assert.isTrue(names.contains('Maria Garcia'), 'Maria is listed');
            Assert.isTrue(names.contains('Wei Lee'), 'Wei is listed');
        }
    }

    // ------------------------------------------------------------------ merge, contact mode

    /**
     * With Contacts to Multiple Accounts on, the platform refuses to merge two accounts that
     * share a related contact (ADR-NEXT). The rows are built in memory, since the object does
     * not exist in every org these tests run in.
     */
    @IsTest
    static void thePeopleRelatedToBothHouseholdsAreFound() {
        System.runAs(TestUsers.admin()) {
            Id survivorId = FakeIds.of(Account.SObjectType, 1);
            Id victimId = FakeIds.of(Account.SObjectType, 2);
            Id both = FakeIds.of(Contact.SObjectType, 1);
            Id onlyVictim = FakeIds.of(Contact.SObjectType, 2);
            Id onlySurvivor = FakeIds.of(Contact.SObjectType, 3);
            List<HouseholdSelector.NativeMembership> rows = new List<HouseholdSelector.NativeMembership>{
                new HouseholdSelector.NativeMembership(relation(1), survivorId, both, true),
                new HouseholdSelector.NativeMembership(relation(2), victimId, both, false),
                new HouseholdSelector.NativeMembership(relation(3), victimId, onlyVictim, true),
                new HouseholdSelector.NativeMembership(relation(4), survivorId, onlySurvivor, true)
            };

            Assert.areEqual(
                new Set<Id>{ both },
                HouseholdMergeService.sharedRelatedPeople(survivorId, rows),
                'Only a person related to both households blocks the platform merge'
            );
            Assert.isTrue(
                HouseholdMergeService.sharedRelatedPeople(
                        survivorId,
                        new List<HouseholdSelector.NativeMembership>()
                    )
                    .isEmpty(),
                'Without Contacts to Multiple Accounts nobody is shared'
            );
        }
    }

    /**
     * A shared relation somebody annotated (roles, dates) is not BarnCRM's to delete, so the
     * merge is refused and nothing changes (ADR-NEXT).
     */
    @IsTest
    static void aSharedRelationWithRolesStopsTheMergeAndChangesNothing() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);
            // After the move Wei is direct on the survivor, and the relation on the other
            // household carries roles, so the move leaves it and the merge has to refuse.
            HouseholdSelector.nativeMembershipRowsOverride = new List<HouseholdSelector.NativeMembership>{
                new HouseholdSelector.NativeMembership(relation(1), survivorId, wei.Id, true),
                new HouseholdSelector.NativeMembership(relation(2), victimId, wei.Id, false, true)
            };

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.mergeHouseholds(
                    survivorId,
                    victimId,
                    new HouseholdMergeService.MergeChoices(null)
                );
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorMergeFailed,
                message,
                'The person is told the merge did not happen'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :Label.Core_HouseholdMerge_ErrorContext
                ],
                'The reason is in the Error Log for a caller that catches the refusal'
            );
            Assert.areEqual(victimId, householdOf(wei.Id), 'Nobody was moved');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :victimId],
                'Both households are still there'
            );
        }
    }

    /**
     * Runs only where Contacts to Multiple Accounts is on: the relation the move leaves on the
     * household going away is removed, so the platform merge goes through.
     */
    @IsTest
    static void withRealContactRelationsTheMergeGoesThrough() {
        System.runAs(TestUsers.admin()) {
            if (!Schema.getGlobalDescribe().containsKey(CONTACT_RELATION)) {
                return; // Contacts to Multiple Accounts is off in this org.
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);

            Test.startTest();
            HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            Assert.areEqual(survivorId, householdOf(wei.Id), 'Wei moved to the survivor');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :victimId],
                'The other household is merged away'
            );
        }
    }

    /**
     * Runs only where Contacts to Multiple Accounts is on: a relation somebody made between a
     * person and the other household is not removed, so the merge is refused unchanged.
     */
    @IsTest
    static void withARealRelationSomebodyMadeTheMergeIsRefused() {
        System.runAs(TestUsers.admin()) {
            Schema.SObjectType relationType = Schema.getGlobalDescribe().get(CONTACT_RELATION);
            if (relationType == null) {
                return; // Contacts to Multiple Accounts is off in this org.
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);
            SObject indirect = relationType.newSObject();
            indirect.put('AccountId', victimId);
            indirect.put('ContactId', maria.Id);
            insert indirect;

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.mergeHouseholds(
                    survivorId,
                    victimId,
                    new HouseholdMergeService.MergeChoices(null)
                );
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_HouseholdMerge_ErrorMergeFailed, message, 'Refused');
            Assert.areEqual(victimId, householdOf(wei.Id), 'Nobody was moved');
            Assert.areEqual(
                1,
                Database.countQueryWithBinds(
                    RELATION_COUNT_QUERY,
                    new Map<String, Object>{ 'relationId' => indirect.Id },
                    AccessLevel.SYSTEM_MODE
                ),
                'The relation somebody made is still there'
            );
        }
    }

    private static Id relation(Integer n) {
        // Only compared, never queried; an Account prefix keeps it valid in every org.
        return FakeIds.of(Account.SObjectType, 100 + n);
    }

    @IsTest
    static void mergeMovesEveryoneAndRemovesTheOtherHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);

            Test.startTest();
            HouseholdMergeService.MergeResult result = HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            Assert.areEqual(survivorId, result.survivorId, 'The survivor is answered');
            Assert.isFalse(
                result.customNameKept,
                'Nobody chose a name and neither side was custom, so naming still owns it'
            );
            Assert.areEqual(
                survivorId,
                householdOf(wei.Id),
                'Wei now belongs to the surviving household'
            );
            Account survivor = [
                SELECT Name, Member_Count__c
                FROM Account
                WHERE Id = :survivorId
            ];
            Assert.areEqual(2, survivor.Member_Count__c, 'The survivor counts both people');
            Assert.areEqual(
                'Garcia and Lee Household',
                survivor.Name,
                'The name was recalculated from both members'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :victimId AND IsDeleted = FALSE],
                'The other household is gone'
            );
        }
    }

    @IsTest
    static void mergeKeepsTheChosenNameWhenTheCustomNameBoxIsTaken() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);
            update new Account(
                Id = victimId,
                Name = 'The Reverend and Mrs. Garcia',
                Custom_Name__c = true
            );

            Test.startTest();
            HouseholdMergeService.MergeResult result = HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(
                    new Map<String, String>{
                        'Name' => HouseholdMergeService.KEEP_VICTIM,
                        'Custom_Name__c' => HouseholdMergeService.KEEP_VICTIM
                    }
                )
            );
            Test.stopTest();

            Account survivor = [
                SELECT Name, Custom_Name__c, Member_Count__c
                FROM Account
                WHERE Id = :survivorId
            ];
            Assert.areEqual(
                'The Reverend and Mrs. Garcia',
                survivor.Name,
                'The wording the person chose stands'
            );
            Assert.isTrue(survivor.Custom_Name__c, 'The household is now one nothing recomputes');
            Assert.areEqual(2, survivor.Member_Count__c, 'The count is still brought up to date');
            Assert.isTrue(
                result.customNameKept,
                'The screen is told the name is now held as a custom one'
            );
        }
    }

    /**
     * The other household's name is offered as a choice, so choosing it has to mean
     * something. The settle-up after a merge rewrites an ordinary household's name from
     * everyone now in it, which would throw the choice away; a chosen name that naming
     * would not produce is therefore kept as a custom name (R-H8).
     */
    @IsTest
    static void mergeKeepsTheOtherHouseholdsNameWhenThePersonChoosesIt() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);

            Test.startTest();
            HouseholdMergeService.MergeResult result = HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(
                    new Map<String, String>{ 'Name' => HouseholdMergeService.KEEP_VICTIM }
                )
            );
            Test.stopTest();

            Account survivor = [
                SELECT Name, Custom_Name__c, Member_Count__c
                FROM Account
                WHERE Id = :survivorId
            ];
            Assert.areEqual('The Lee Family', survivor.Name, 'The name the person chose stands');
            Assert.isTrue(
                survivor.Custom_Name__c,
                'A chosen name that naming would not produce is kept as a custom name'
            );
            Assert.areEqual(2, survivor.Member_Count__c, 'The count is still brought up to date');
            Assert.isTrue(
                result.customNameKept,
                'The screen is told the name is now held as a custom one'
            );
        }
    }

    /**
     * A greeting is offered as a choice the same way a name is, so a chosen greeting is
     * kept too rather than recomputed straight over.
     */
    @IsTest
    static void mergeKeepsTheOtherHouseholdsGreetingWhenThePersonChoosesIt() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);
            update new Account(
                Id = victimId,
                Household_Formal_Greeting__c = 'Dr. Wei Lee and family'
            );

            Test.startTest();
            HouseholdMergeService.MergeResult result = HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(
                    new Map<String, String>{
                        'Household_Formal_Greeting__c' => HouseholdMergeService.KEEP_VICTIM
                    }
                )
            );
            Test.stopTest();

            Account survivor = [
                SELECT Household_Formal_Greeting__c, Custom_Name__c
                FROM Account
                WHERE Id = :survivorId
            ];
            Assert.areEqual(
                'Dr. Wei Lee and family',
                survivor.Household_Formal_Greeting__c,
                'The greeting the person chose stands'
            );
            Assert.isTrue(survivor.Custom_Name__c, 'It is held as custom wording (R-H8)');
            Assert.isTrue(result.customNameKept, 'The screen is told');
        }
    }

    /**
     * The counterpart: a chosen name that naming produces anyway is not frozen, so the
     * household stays one whose name follows its members.
     */
    @IsTest
    static void aChosenNameThatNamingWouldGiveAnywayStaysAnOrdinaryName() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            // The primary member's surname comes first (R-H5): Sam leads the other household
            // and Wei the survivor, so both read Lee first and the chosen name is the one
            // naming gives the merged household.
            Contact sam = HouseholdTestDataFactory.newContact('Mr.', 'Sam', 'Lee');
            insert sam;
            Id victimId = householdOf(sam.Id);
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert wei;
            Id survivorId = householdOf(wei.Id);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            maria.AccountId = victimId;
            insert maria;
            Assert.areEqual(
                'Lee and Garcia Household',
                [SELECT Name FROM Account WHERE Id = :victimId].Name,
                'The other household is named from both surnames before the merge'
            );

            Test.startTest();
            HouseholdMergeService.MergeResult result = HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(
                    new Map<String, String>{ 'Name' => HouseholdMergeService.KEEP_VICTIM }
                )
            );
            Test.stopTest();

            Account survivor = [SELECT Name, Custom_Name__c FROM Account WHERE Id = :survivorId];
            Assert.areEqual('Lee and Garcia Household', survivor.Name, 'The chosen name stands');
            Assert.isFalse(
                survivor.Custom_Name__c,
                'Naming gives that name anyway, so the household keeps following its members'
            );
            Assert.isFalse(
                result.customNameKept,
                'The screen is not told about a lock that did not happen'
            );
        }
    }

    /**
     * The preview is shown to somebody, so it is built from what that person may read
     * (ADR-0021): a deceased flag they cannot read on the record does not reach them
     * through the merge comparison.
     */
    /**
     * One field the person cannot read leaves that field out of the comparison; it does
     * not refuse the whole merge screen.
     */
    @IsTest
    static void previewLeavesOutAFieldThePersonCannotRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            User staff = HouseholdTestDataFactory.standardUser('mfls2');
            grantHouseholdFieldRead('C01_Merge_No_Anniversary', staff.Id, 'Anniversary__c');
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            System.runAs(staff) {
                insert new List<Contact>{ maria, wei };
            }
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);

            HouseholdMergeService.MergePreview shown;
            Boolean canRead;
            Test.startTest();
            System.runAs(staff) {
                canRead = Schema.SObjectType.Account.fields.Anniversary__c.isAccessible();
                shown = HouseholdMergeService.preview(survivorId, victimId);
            }
            Test.stopTest();

            Assert.isFalse(canRead, 'The person really cannot read the anniversary');
            Map<String, HouseholdMergeService.FieldChoice> fields = byFieldName(shown);
            Assert.isFalse(
                fields.containsKey('Anniversary__c'),
                'The field the person cannot read is left out'
            );
            Assert.isTrue(fields.containsKey('Name'), 'The rest of the comparison is shown');
            Assert.areEqual(2, shown.members.size(), 'Both people are listed');
        }
    }

    @IsTest
    static void previewShowsOnlyWhatThePersonCanRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            User staff = HouseholdTestDataFactory.standardUser('mfls');
            grantHouseholdFieldRead('C01_Merge_Display_Test', staff.Id);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            // Saved by the same user who will read them back, so that what this test measures
            // is field level access and not the org's sharing model.
            System.runAs(staff) {
                insert new List<Contact>{ maria, wei };
            }
            update new Contact(Id = wei.Id, Deceased__c = true);
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);
            Assert.isTrue(
                memberNamed(HouseholdMergeService.preview(survivorId, victimId), 'Wei Lee')
                    .isDeceased,
                'A user who can read the field is told that he died'
            );

            HouseholdMergeService.MergePreview shown;
            Test.startTest();
            System.runAs(staff) {
                shown = HouseholdMergeService.preview(survivorId, victimId);
            }
            Test.stopTest();

            Assert.areEqual(2, shown.members.size(), 'Both people are still listed');
            Assert.isFalse(
                memberNamed(shown, 'Wei Lee').isDeceased,
                'A user with no access to the deceased field is not told that he died'
            );
        }
    }

    @IsTest
    static void mergeTakesTheChosenAddressAndAnniversary() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            survivor.BillingCity = 'Oakland';
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            victim.BillingCity = 'Berkeley';
            victim.Anniversary__c = Date.newInstance(2010, 6, 12);
            insert new List<Account>{ survivor, victim };

            Test.startTest();
            HouseholdMergeService.mergeHouseholds(
                survivor.Id,
                victim.Id,
                new HouseholdMergeService.MergeChoices(
                    new Map<String, String>{
                        'BillingCity' => HouseholdMergeService.KEEP_VICTIM,
                        'Anniversary__c' => HouseholdMergeService.KEEP_VICTIM
                    }
                )
            );
            Test.stopTest();

            Account saved = [
                SELECT BillingCity, Anniversary__c
                FROM Account
                WHERE Id = :survivor.Id
            ];
            Assert.areEqual('Berkeley', saved.BillingCity, 'The chosen address survives');
            Assert.areEqual(
                Date.newInstance(2010, 6, 12),
                saved.Anniversary__c,
                'The chosen anniversary survives'
            );
            // Both households had a default address; the merge settlement (PEOPLE-15) keeps
            // the one matching the chosen billing address.
            List<Address__c> defaults = [
                SELECT City__c
                FROM Address__c
                WHERE Account__c = :survivor.Id AND Is_Default__c = TRUE
            ];
            Assert.areEqual(1, defaults.size(), 'The survivor has one default address');
            Assert.areEqual('Berkeley', defaults[0].City__c, 'The chosen one');
        }
    }

    // ------------------------------------------------------------------ merge, junction mode

    @IsTest
    static void mergeInJunctionModeLeavesNobodyInTheHouseholdTwice() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            insert new List<Account>{ survivor, victim };
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            // Maria belongs to both households already, which is what junction mode allows.
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = survivor.Id, Contact__c = maria.Id),
                new Household_Member__c(Household__c = victim.Id, Contact__c = maria.Id),
                new Household_Member__c(Household__c = victim.Id, Contact__c = wei.Id)
            };

            Test.startTest();
            HouseholdMergeService.mergeHouseholds(
                survivor.Id,
                victim.Id,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            Integer mariaRows = [
                SELECT COUNT()
                FROM Household_Member__c
                WHERE Household__c = :survivor.Id AND Contact__c = :maria.Id AND End_Date__c = NULL
            ];
            Assert.areEqual(1, mariaRows, 'Maria is in the surviving household exactly once');
            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :survivor.Id].Member_Count__c,
                'The survivor counts two people, not three'
            );
        }
    }

    @IsTest
    static void theOtherHouseholdIsMergedIntoTheSurvivorRatherThanJustDeleted() {
        System.runAs(TestUsers.admin()) {
            // Delete Empty Households is on, which is the case that used to empty the other
            // household and let the upkeep delete it before the platform merge could run. A
            // record that is merged away carries the survivor's id; one that is merely deleted
            // does not, so this is the difference between a merge and a loss.
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = householdOf(maria.Id);
            Id victimId = householdOf(wei.Id);

            Test.startTest();
            HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            Account gone = [SELECT MasterRecordId FROM Account WHERE Id = :victimId ALL ROWS];
            Assert.areEqual(
                survivorId,
                gone.MasterRecordId,
                'Everything hanging off the other household followed the merge to the survivor'
            );
        }
    }

    // ------------------------------------------------------------------ refusals

    @IsTest
    static void aNonprofitCloudHouseholdIsNeitherPreviewedNorMerged() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account ours = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            // Theirs carries a native household group, as in a Nonprofit Cloud org.
            Account theirs = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert new List<Account>{ ours, theirs };
            HouseholdSelector.accountsWithNativeHouseholdGroupsOverride = new Set<Id>{ theirs.Id };

            List<String> messages = new List<String>();
            Test.startTest();
            try {
                HouseholdMergeService.preview(ours.Id, theirs.Id);
            } catch (HouseholdException e) {
                messages.add(e.getMessage());
            }
            try {
                HouseholdMergeService.mergeHouseholds(
                    theirs.Id,
                    ours.Id,
                    new HouseholdMergeService.MergeChoices(null)
                );
            } catch (HouseholdException e) {
                messages.add(e.getMessage());
            }
            Test.stopTest();

            Assert.areEqual(
                new List<String>{
                    Label.Core_HouseholdMerge_ErrorNativeHousehold,
                    Label.Core_HouseholdMerge_ErrorNativeHousehold
                },
                messages,
                'Either direction is refused, before anything is moved.'
            );
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Account WHERE Id IN :new List<Id>{ ours.Id, theirs.Id }],
                'Both households are still there.'
            );
        }
    }

    @IsTest
    static void anOrganizationCannotBeMergedIntoAHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account organization = new Account(Name = 'Bay Area Food Bank');
            insert new List<Account>{ household, organization };

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.mergeHouseholds(
                    household.Id,
                    organization.Id,
                    new HouseholdMergeService.MergeChoices(null)
                );
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorNotHousehold,
                message,
                'The refusal names the problem in plain language'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :organization.Id],
                'The organization is untouched'
            );
        }
    }

    @IsTest
    static void aHouseholdCannotBeMergedIntoItself() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.mergeHouseholds(
                    household.Id,
                    household.Id,
                    new HouseholdMergeService.MergeChoices(null)
                );
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorSameRecord,
                message,
                'The refusal is clear'
            );
        }
    }

    @IsTest
    static void aPersonWithoutEditAccessCannotMerge() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            insert new List<Account>{ survivor, victim };
            User reader = readOnlyUser();

            String message;
            Test.startTest();
            System.runAs(reader) {
                try {
                    HouseholdMergeService.mergeHouseholds(
                        survivor.Id,
                        victim.Id,
                        new HouseholdMergeService.MergeChoices(null)
                    );
                } catch (Exception e) {
                    message = e.getMessage();
                }
            }
            Test.stopTest();

            Assert.isNotNull(message, 'A person who cannot edit these households is refused');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Account WHERE Id IN (:survivor.Id, :victim.Id)],
                'Both households are untouched'
            );
        }
    }

    // ------------------------------------------------------------------ split

    @IsTest
    static void splitToANewHouseholdRenamesBoth() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = householdOf(maria.Id);
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            wei.AccountId = householdId;
            insert wei;
            HouseholdService.afterMembershipChange(new Set<Id>{ householdId });

            Test.startTest();
            Id created = HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, null);
            Test.stopTest();

            Assert.isNotNull(created, 'A household was created for Wei');
            Assert.areEqual(created, householdOf(wei.Id), 'Wei belongs to the new household');
            Assert.areEqual(
                'The Lee Family',
                [SELECT Name FROM Account WHERE Id = :created].Name,
                'The new household is named from the person who moved'
            );
            Account source = [SELECT Name, Member_Count__c FROM Account WHERE Id = :householdId];
            Assert.areEqual(1, source.Member_Count__c, 'The household he left counts one');
            Assert.areEqual('The Garcia Family', source.Name, 'And it was renamed');
        }
    }

    @IsTest
    static void splitToAnExistingHouseholdMovesThePersonThere() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = householdOf(maria.Id);
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            wei.AccountId = householdId;
            insert wei;
            Account destination = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert destination;

            Test.startTest();
            Id result = HouseholdMergeService.split(
                householdId,
                new Set<Id>{ wei.Id },
                destination.Id
            );
            Test.stopTest();

            Assert.areEqual(destination.Id, result, 'The destination is answered');
            Assert.areEqual(
                destination.Id,
                householdOf(wei.Id),
                'Wei moved to the household chosen'
            );
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :destination.Id].Member_Count__c,
                'The destination counts him'
            );
        }
    }

    @IsTest
    static void theEmptiedHouseholdGoesAwayWhenTheOrgAsksForThat() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert wei;
            Id householdId = householdOf(wei.Id);
            Account destination = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert destination;

            Test.startTest();
            HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, destination.Id);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :householdId],
                'The household he was the last member of was tidied away'
            );
        }
    }

    @IsTest
    static void theEmptiedHouseholdStaysWhenTheOrgSaysSo() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert wei;
            Id householdId = householdOf(wei.Id);
            Account destination = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert destination;

            Test.startTest();
            HouseholdMergeService.split(householdId, new Set<Id>{ wei.Id }, destination.Id);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :householdId],
                'The empty household was kept, because the org asked for that'
            );
        }
    }

    @IsTest
    static void splittingSomebodyWhoIsNotInTheHouseholdIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.split(householdOf(maria.Id), new Set<Id>{ wei.Id }, null);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorSplitNotMembers,
                message,
                'The refusal says the people are not in this household'
            );
        }
    }

    @IsTest
    static void splittingNobodyIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.split(household.Id, new Set<Id>(), null);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorSplitNoMembers,
                message,
                'The refusal asks for at least one person'
            );
        }
    }

    // ------------------------------------------------------------------ bulk

    @IsTest
    static void fiftyPeopleCanBeSplitOutInOneGo() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Big Family');
            Account destination = HouseholdTestDataFactory.newHousehold('The Other Family');
            insert new List<Account>{ household, destination };
            List<Contact> people = HouseholdTestDataFactory.manyContacts(50, 'Member');
            for (Contact person : people) {
                person.AccountId = household.Id;
            }
            insert people;
            Set<Id> movers = new Map<Id, Contact>(people).keySet();

            Test.startTest();
            HouseholdMergeService.split(household.Id, movers, destination.Id);
            Test.stopTest();

            Assert.areEqual(
                50,
                [SELECT COUNT() FROM Contact WHERE AccountId = :destination.Id],
                'All fifty people moved in one pass'
            );
            Assert.areEqual(
                50,
                [SELECT Member_Count__c FROM Account WHERE Id = :destination.Id].Member_Count__c,
                'The destination counts all fifty'
            );
        }
    }

    @IsTest
    static void splittingIntoTheHouseholdPeopleAreAlreadyInIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = householdOf(maria.Id);

            String message;
            Test.startTest();
            try {
                HouseholdMergeService.split(householdId, new Set<Id>{ maria.Id }, householdId);
            } catch (HouseholdException e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorSplitSameHousehold,
                message,
                'The refusal says what to do instead'
            );
        }
    }

    @IsTest
    static void splittingIntoAHouseholdThisPersonCannotEditIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = householdOf(maria.Id);
            Account destination = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert destination;
            User reader = readOnlyUser();

            String message;
            Test.startTest();
            System.runAs(reader) {
                try {
                    HouseholdMergeService.split(
                        householdId,
                        new Set<Id>{ maria.Id },
                        destination.Id
                    );
                } catch (Exception e) {
                    message = e.getMessage();
                }
            }
            Test.stopTest();

            Assert.isNotNull(message, 'Both ends of a split need edit access, not just the source');
            Assert.areEqual(
                householdId,
                householdOf(maria.Id),
                'Nobody was moved into a household the person cannot edit'
            );
        }
    }

    // ------------------------------------------------------------------ a third household

    /**
     * Ana belongs to the household being merged away and to her other parent's household.
     * The merge moves her from the first only, keeps the date she joined, and leaves the
     * other household exactly as it was.
     */
    @IsTest
    static void mergeInJunctionModeLeavesAThirdHouseholdAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            Account other = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ survivor, victim, other };
            Contact ana = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ ana, wei };
            Date joined = Date.newInstance(2020, 1, 15);
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = victim.Id,
                    Contact__c = ana.Id,
                    Start_Date__c = joined
                ),
                new Household_Member__c(
                    Household__c = other.Id,
                    Contact__c = ana.Id,
                    Start_Date__c = joined
                ),
                new Household_Member__c(
                    Household__c = other.Id,
                    Contact__c = wei.Id,
                    Start_Date__c = joined
                )
            };

            Test.startTest();
            HouseholdMergeService.mergeHouseholds(
                survivor.Id,
                victim.Id,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            Assert.areEqual(
                2,
                currentMembers(other.Id),
                'Ana is still in the other household, with Wei'
            );
            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :other.Id].Member_Count__c,
                'The other household still counts both of them'
            );
            List<Household_Member__c> inSurvivor = [
                SELECT Start_Date__c
                FROM Household_Member__c
                WHERE Household__c = :survivor.Id AND Contact__c = :ana.Id AND End_Date__c = NULL
            ];
            Assert.areEqual(1, inSurvivor.size(), 'Ana is in the survivor once');
            Assert.areEqual(
                joined,
                inSurvivor[0].Start_Date__c,
                'A merge keeps the date she joined the family'
            );
        }
    }

    @IsTest
    static void splitInJunctionModeLeavesAThirdHouseholdAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account source = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account other = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert new List<Account>{ source, other };
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact ana = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Garcia');
            insert new List<Contact>{ maria, ana };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = source.Id, Contact__c = maria.Id),
                new Household_Member__c(Household__c = source.Id, Contact__c = ana.Id),
                new Household_Member__c(Household__c = other.Id, Contact__c = ana.Id)
            };

            Test.startTest();
            Id destination = HouseholdMergeService.split(source.Id, new Set<Id>{ ana.Id }, null);
            Test.stopTest();

            Assert.areEqual(1, currentMembers(source.Id), 'Maria stays where she was');
            Assert.areEqual(1, currentMembers(destination), 'Ana is in the new household');
            Assert.areEqual(
                1,
                currentMembers(other.Id),
                'Ana is still in the household the split did not name'
            );
        }
    }

    // ------------------------------------------------------------------ helpers

    private static Integer currentMembers(Id householdId) {
        return [
            SELECT COUNT()
            FROM Household_Member__c
            WHERE Household__c = :householdId AND (End_Date__c = NULL OR End_Date__c > TODAY)
        ];
    }

    private static Id householdOf(Id contactId) {
        return [SELECT AccountId FROM Contact WHERE Id = :contactId].AccountId;
    }

    private static HouseholdMergeService.MemberChoice memberNamed(
        HouseholdMergeService.MergePreview preview,
        String name
    ) {
        for (HouseholdMergeService.MemberChoice member : preview.members) {
            if (member.name == name) {
                return member;
            }
        }
        Assert.fail('The preview does not list ' + name);
        return null;
    }

    /**
     * Read access to the household fields the merge comparison reads, and nothing on
     * Contact: the shape of a user who can open the merge screen and still cannot read a
     * person's deceased flag on the record itself. Setup objects are saved on their own so
     * that granting access and creating records never mix in one transaction.
     */
    private static void grantHouseholdFieldRead(String name, Id userId) {
        grantHouseholdFieldRead(name, userId, null);
    }

    private static void grantHouseholdFieldRead(String name, Id userId, String leftOut) {
        List<String> fields = new List<String>{
            'Anniversary__c',
            'Custom_Name__c',
            'Household_Formal_Greeting__c',
            'Household_Informal_Greeting__c',
            'Member_Count__c',
            'Primary_Contact__c'
        };
        if (leftOut != null) {
            fields.remove(fields.indexOf(leftOut));
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet grant = new PermissionSet(Name = name, Label = name);
            insert grant;
            List<FieldPermissions> reads = new List<FieldPermissions>();
            for (String field : fields) {
                reads.add(
                    new FieldPermissions(
                        ParentId = grant.Id,
                        SobjectType = 'Account',
                        Field = 'Account.' + field,
                        PermissionsRead = true
                    )
                );
            }
            insert reads;
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = grant.Id);
        }
    }

    private static Map<String, HouseholdMergeService.FieldChoice> byFieldName(
        HouseholdMergeService.MergePreview preview
    ) {
        Map<String, HouseholdMergeService.FieldChoice> result = new Map<String, HouseholdMergeService.FieldChoice>();
        for (HouseholdMergeService.FieldChoice choice : preview.fields) {
            result.put(choice.fieldName, choice);
        }
        return result;
    }

    /**
     * A user on the most restricted standard profile, so that a merge attempted without
     * edit access is refused by the same record access check the screen asks about.
     */
    private static User readOnlyUser() {
        // Which standard profile gives a user no edit access is not the same in every org:
        // "Read Only" is absent from some editions and org shapes. The first of the known
        // ones that this org actually has is used, so the test measures the refusal rather
        // than the org's profile list.
        Map<String, Profile> byName = new Map<String, Profile>();
        for (Profile candidate : [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN ('Read Only', 'Minimum Access - Salesforce')
        ]) {
            byName.put(candidate.Name, candidate);
        }
        Profile readOnly = byName.containsKey('Read Only')
            ? byName.get('Read Only')
            : byName.get('Minimum Access - Salesforce');
        Assert.isNotNull(
            readOnly,
            'This org has no standard profile without edit access, so a merge refused for ' +
            'want of edit access cannot be exercised at all'
        );
        User reader = new User(
            ProfileId = readOnly.Id,
            LastName = 'Reader',
            Email = 'reader@barncrm.test.invalid',
            Username = 'reader' + DateTime.now().getTime() + '@barncrm.test.invalid',
            Alias = 'reader',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        // A user is a setup record, so it is saved on its own: these tests have already
        // saved households by the time they ask for a reader.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert reader;
        }
        return reader;
    }
}
