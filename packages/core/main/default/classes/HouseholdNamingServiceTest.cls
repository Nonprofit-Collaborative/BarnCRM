/**
 * One rule from canonical model R-H4 to R-H9 per test method.
 */
@IsTest(testFor='ApexClass:HouseholdNamingService')
private class HouseholdNamingServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String NAME_PATTERN = 'The {LastName} Family';
    private static final String FORMAL_PATTERN = '{Salutation} {FirstName} {LastName}';
    private static final String INFORMAL_PATTERN = '{FirstName}';

    @IsTest
    static void sharedSurnameGivesTheFamilyName() {
        System.runAs(TestUsers.admin()) {
            String name = HouseholdNamingService.computeName(
                HouseholdTestDataFactory.smithCouple(),
                NAME_PATTERN,
                false
            );
            Assert.areEqual(
                'The Smith Family',
                name,
                'Two people called Smith are the Smith family'
            );
        }
    }

    @IsTest
    static void oneMemberGivesTheFamilyName() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Ms.', 'Maria', 'Garcia', 'Head')
            };
            Assert.areEqual(
                'The Garcia Family',
                HouseholdNamingService.computeName(members, NAME_PATTERN, false),
                'Maria on her own is still a family'
            );
        }
    }

    @IsTest
    static void differingSurnamesAreListed() {
        System.runAs(TestUsers.admin()) {
            String name = HouseholdNamingService.computeName(
                HouseholdTestDataFactory.garciaAndLee(),
                NAME_PATTERN,
                false
            );
            Assert.areEqual(
                'Garcia and Lee Household',
                name,
                'Two surnames are listed, not patterned'
            );
        }
    }

    @IsTest
    static void threeSurnamesUseCommasAndAnAnd() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.garciaAndLee();
            members.add(HouseholdTestDataFactory.person('Mr.', 'Tom', 'Smith', 'Other'));
            Assert.areEqual(
                'Garcia, Lee, and Smith Household',
                HouseholdNamingService.computeName(members, NAME_PATTERN, false),
                'Three surnames read as a list'
            );
        }
    }

    @IsTest
    static void hyphenatedSurnameIsNeverSplit() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Ms.', 'Priya', 'Garcia-Lee', 'Head'),
                HouseholdTestDataFactory.person('Mr.', 'Wei', 'Garcia-Lee', 'Spouse or Partner')
            };
            Assert.areEqual(
                'The Garcia-Lee Family',
                HouseholdNamingService.computeName(members, NAME_PATTERN, false),
                'A hyphenated surname is one surname'
            );
        }
    }

    @IsTest
    static void preferredNameReplacesFirstName() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Dr.', 'David', 'Okonkwo', 'Head')
            };
            members[0].preferredName = 'Dave';
            Assert.areEqual(
                'Dave',
                HouseholdNamingService.computeInformalGreeting(members, INFORMAL_PATTERN),
                'David prefers Dave'
            );
        }
    }

    @IsTest
    static void informalGreetingListsLivingMembers() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'John and Jane',
                HouseholdNamingService.computeInformalGreeting(
                    HouseholdTestDataFactory.smithCouple(),
                    INFORMAL_PATTERN
                ),
                'Both first names appear'
            );
        }
    }

    @IsTest
    static void deceasedMemberIsLeftOutOfGreetings() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.smithCouple();
            members[1].isDeceased = true;
            Assert.areEqual(
                'John',
                HouseholdNamingService.computeInformalGreeting(members, INFORMAL_PATTERN),
                'Jane has died and is not greeted'
            );
            Assert.areEqual(
                'Mr. John Smith',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'The formal greeting names John alone'
            );
        }
    }

    @IsTest
    static void deceasedMemberLeavesTheNameWhenTheSettingIsOff() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.garciaAndLee();
            members[1].isDeceased = true;
            Assert.areEqual(
                'The Garcia Family',
                HouseholdNamingService.computeName(members, NAME_PATTERN, false),
                'Wei has died and is not in the name'
            );
        }
    }

    @IsTest
    static void deceasedMemberStaysInTheNameWhenTheSettingIsOn() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.garciaAndLee();
            members[1].isDeceased = true;
            Assert.areEqual(
                'Garcia and Lee Household',
                HouseholdNamingService.computeName(members, NAME_PATTERN, true),
                'Wei stays in the name when the org asks for that'
            );
            Assert.areEqual(
                'Ms. Maria Garcia and the late Mr. Wei Lee',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, true),
                'The formal greeting says the late'
            );
        }
    }

    @IsTest
    static void excludeFromHouseholdNameLeavesTheGreetingsAlone() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.garciaAndLee();
            members[1].excludeFromName = true;
            Assert.areEqual(
                'The Garcia Family',
                HouseholdNamingService.computeName(members, NAME_PATTERN, false),
                'Wei is out of the name'
            );
            Assert.areEqual(
                'Maria and Wei',
                HouseholdNamingService.computeInformalGreeting(members, INFORMAL_PATTERN),
                'Wei is still greeted'
            );
        }
    }

    @IsTest
    static void excludeFromGreetingsLeavesTheNameAlone() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.garciaAndLee();
            members[1].excludeFromGreetings = true;
            Assert.areEqual(
                'Garcia and Lee Household',
                HouseholdNamingService.computeName(members, NAME_PATTERN, false),
                'Wei is still in the name'
            );
            Assert.areEqual(
                'Maria',
                HouseholdNamingService.computeInformalGreeting(members, INFORMAL_PATTERN),
                'Wei is not greeted'
            );
        }
    }

    @IsTest
    static void formalGreetingListsEachPersonWhenATitleIsProfessional() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = HouseholdTestDataFactory.smithCouple();
            members[0].salutation = 'Dr.';
            Assert.areEqual(
                'Dr. John Smith and Mrs. Jane Smith',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'A professional title is not merged onto one shared first name'
            );
            members[1].salutation = 'Dr.';
            Assert.areEqual(
                'Dr. John Smith and Dr. Jane Smith',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'Two doctors are each named'
            );
        }
    }

    @IsTest
    static void formalGreetingNamesEachPersonUnlessThePairIsOneMrAndOneMrs() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Ms.', 'Rosa', 'Hall', 'Head'),
                HouseholdTestDataFactory.person('Ms.', 'Ana', 'Hall', 'Spouse or Partner')
            };
            Assert.areEqual(
                'Ms. Rosa Hall and Ms. Ana Hall',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'Two Ms. are each named'
            );
            members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Mrs.', 'Camila', 'Perez-Reyes', 'Head'),
                HouseholdTestDataFactory.person('Mr.', 'Luis', 'Perez-Reyes', 'Spouse or Partner')
            };
            Assert.areEqual(
                'Mr. and Mrs. Luis Perez-Reyes',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'One Mrs. and one Mr. combine under the Mr. first name, whichever is listed first'
            );
            members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Mr.', 'Luis', 'Mensah-Sato', 'Head'),
                HouseholdTestDataFactory.person('Ms.', 'Ana', 'Mensah-Sato', 'Spouse or Partner')
            };
            Assert.areEqual(
                'Mr. Luis Mensah-Sato and Ms. Ana Mensah-Sato',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'A Mr. and a Ms. are each named'
            );
            members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Mrs.', 'Lucia', 'Costa', 'Head'),
                HouseholdTestDataFactory.person('Mrs.', 'Eva', 'Costa', 'Spouse or Partner')
            };
            Assert.areEqual(
                'Mrs. Lucia Costa and Mrs. Eva Costa',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'Two Mrs. are each named'
            );
            members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Dr.', 'Priya', 'Nguyen', 'Head'),
                HouseholdTestDataFactory.person('Mr.', 'Thomas', 'Nguyen', 'Spouse or Partner')
            };
            Assert.areEqual(
                'Dr. Priya Nguyen and Mr. Thomas Nguyen',
                HouseholdNamingService.computeFormalGreeting(members, FORMAL_PATTERN, false),
                'A Dr. is never combined'
            );
        }
    }

    @IsTest
    static void formalGreetingCombinesTitlesForACouple() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Mr. and Mrs. John Smith',
                HouseholdNamingService.computeFormalGreeting(
                    HouseholdTestDataFactory.smithCouple(),
                    FORMAL_PATTERN,
                    false
                ),
                'One surname and two titles read as one greeting'
            );
        }
    }

    @IsTest
    static void formalGreetingNamesBothWhenSurnamesDiffer() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Ms. Maria Garcia and Mr. Wei Lee',
                HouseholdNamingService.computeFormalGreeting(
                    HouseholdTestDataFactory.garciaAndLee(),
                    FORMAL_PATTERN,
                    false
                ),
                'Different surnames are greeted one by one'
            );
        }
    }

    @IsTest
    static void membersAreOrderedByRole() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person('Ms.', 'Chidi', 'Okonkwo', 'Child'),
                HouseholdTestDataFactory.person('Dr.', 'David', 'Okonkwo', 'Head')
            };
            Assert.areEqual(
                'David and Chidi',
                HouseholdNamingService.computeInformalGreeting(members, INFORMAL_PATTERN),
                'The head of the household is greeted first'
            );
        }
    }

    @IsTest
    static void bangTokenSpellingIsAccepted() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'The Smith Family',
                HouseholdNamingService.computeName(
                    HouseholdTestDataFactory.smithCouple(),
                    'The {!LastName} Family',
                    false
                ),
                'A pattern copied from a formula still works'
            );
        }
    }

    @IsTest
    static void aBlankPatternFallsBackToTheShippedOne() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'The Smith Family',
                HouseholdNamingService.computeName(
                    HouseholdTestDataFactory.smithCouple(),
                    null,
                    false
                ),
                'A missing pattern does not produce a blank name'
            );
        }
    }

    @IsTest
    static void aHouseholdWithNoOneLeftHasNoName() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                null,
                HouseholdNamingService.computeName(
                    new List<HouseholdService.Person>(),
                    NAME_PATTERN,
                    false
                ),
                'No members means no computed name'
            );
        }
    }

    @IsTest
    static void applyNamingWritesTheNameAndGreetings() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            // Household Role is what decides the order members are named in, so the couple are
            // given theirs: without a role these two are ordered by the tie breaks that follow
            // it, and the greeting would name whichever of them those happen to put first.
            insert new List<Contact>{
                new Contact(
                    Salutation = 'Mr.',
                    FirstName = 'John',
                    LastName = 'Smith',
                    Household_Role__c = 'Head',
                    AccountId = household.Id
                ),
                new Contact(
                    Salutation = 'Mrs.',
                    FirstName = 'Jane',
                    LastName = 'Smith',
                    Household_Role__c = 'Spouse or Partner',
                    AccountId = household.Id
                )
            };

            Test.startTest();
            HouseholdNamingService.applyNaming(new Set<Id>{ household.Id });
            Test.stopTest();

            Account saved = [
                SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(
                'The Smith Family',
                saved.Name,
                'The household is renamed from its members'
            );
            Assert.areEqual(
                'Mr. and Mrs. John Smith',
                saved.Household_Formal_Greeting__c,
                'Formal greeting'
            );
            Assert.areEqual(
                'John and Jane',
                saved.Household_Informal_Greeting__c,
                'Informal greeting'
            );
        }
    }

    @IsTest
    static void aHouseholdLeftEmptyKeepsItsLastNameAndGreetings() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            Account elsewhere = HouseholdTestDataFactory.newHousehold('Elsewhere');
            Database.insert(new List<Account>{ household, elsewhere }, AccessLevel.SYSTEM_MODE);
            Contact john = new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );
            insert john;
            Account named = [
                SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual('The Smith Family', named.Name, 'Named from its member first');

            Test.startTest();
            update new Contact(Id = john.Id, AccountId = elsewhere.Id);
            HouseholdNamingService.applyNaming(new Set<Id>{ household.Id });
            Test.stopTest();

            Account kept = [
                SELECT
                    Name,
                    Member_Count__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(0, kept.Member_Count__c, 'Nobody is left in it');
            Assert.areEqual(
                named.Name,
                kept.Name,
                'Still says which family it was, not the placeholder name'
            );
            Assert.areEqual(
                named.Household_Formal_Greeting__c,
                kept.Household_Formal_Greeting__c,
                'Formal greeting kept'
            );
            Assert.areEqual(
                named.Household_Informal_Greeting__c,
                kept.Household_Informal_Greeting__c,
                'Informal greeting kept'
            );
        }
    }

    /** R-H4 in membership mode: the last current membership ends and the household keeps its words. */
    @IsTest
    static void aJunctionHouseholdWhoseLastMembershipEndsKeepsItsNameAndGreetings() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            settings.Auto_Create_Households__c = false;
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            Contact john = new Contact(Salutation = 'Mr.', FirstName = 'John', LastName = 'Smith');
            insert john;
            Household_Member__c member = new Household_Member__c(
                Household__c = household.Id,
                Contact__c = john.Id,
                Is_Primary__c = true
            );
            insert member;
            HouseholdNamingService.applyNaming(new Set<Id>{ household.Id });
            Account named = [
                SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual('The Smith Family', named.Name, 'Named from its member first');

            Test.startTest();
            update new Household_Member__c(Id = member.Id, End_Date__c = Date.today());
            HouseholdNamingService.applyNaming(new Set<Id>{ household.Id });
            Test.stopTest();

            Account kept = [
                SELECT
                    Name,
                    Member_Count__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(0, kept.Member_Count__c, 'Nobody is a current member');
            Assert.areEqual(named.Name, kept.Name, 'Still says which family it was');
            Assert.areEqual(
                named.Household_Formal_Greeting__c,
                kept.Household_Formal_Greeting__c,
                'Formal greeting kept'
            );
            Assert.areEqual(
                named.Household_Informal_Greeting__c,
                kept.Household_Informal_Greeting__c,
                'Informal greeting kept'
            );
        }
    }

    @IsTest
    static void customNameStopsEveryRecomputation() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold(
                'The Reverend and Mrs. Smith'
            );
            household.Custom_Name__c = true;
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            insert new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );

            Test.startTest();
            HouseholdNamingService.applyNaming(new Set<Id>{ household.Id });
            Test.stopTest();

            Account saved = [SELECT Name FROM Account WHERE Id = :household.Id];
            Assert.areEqual(
                'The Reverend and Mrs. Smith',
                saved.Name,
                'A household David worded himself is never rewritten'
            );
        }
    }

    @IsTest
    static void upkeepFillsBlankGreetingsOnACustomNamedHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold(
                'The Reverend and Mrs. Smith'
            );
            household.Custom_Name__c = true;
            Database.insert(household, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            insert smith(household.Id);
            Test.stopTest();

            Account saved = wordingOf(household.Id);
            Assert.areEqual('The Reverend and Mrs. Smith', saved.Name, 'Custom name kept (R-H8)');
            Assert.areEqual(
                'Mr. John Smith',
                saved.Household_Formal_Greeting__c,
                'A blank formal greeting is filled from the members'
            );
            Assert.areEqual(
                'John',
                saved.Household_Informal_Greeting__c,
                'A blank informal greeting is filled from the members'
            );
        }
    }

    @IsTest
    static void upkeepKeepsTheCustomNameAndEveryGreetingWithAValue() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account oneTyped = HouseholdTestDataFactory.newHousehold('The Reverend Smith');
            oneTyped.Custom_Name__c = true;
            oneTyped.Household_Formal_Greeting__c = 'The Reverend John Smith';
            Account bothTyped = HouseholdTestDataFactory.newHousehold('The Smith Clan');
            bothTyped.Custom_Name__c = true;
            bothTyped.Household_Formal_Greeting__c = 'Dear Smith Clan';
            bothTyped.Household_Informal_Greeting__c = 'Smiths';
            Database.insert(new List<Account>{ oneTyped, bothTyped }, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            insert new List<Contact>{ smith(oneTyped.Id), smith(bothTyped.Id) };
            Test.stopTest();

            Account one = wordingOf(oneTyped.Id);
            Assert.areEqual('The Reverend Smith', one.Name, 'Custom name kept');
            Assert.areEqual(
                'The Reverend John Smith',
                one.Household_Formal_Greeting__c,
                'A typed formal greeting is never replaced'
            );
            Assert.areEqual(
                'John',
                one.Household_Informal_Greeting__c,
                'Only the blank one filled'
            );

            Account both = wordingOf(bothTyped.Id);
            Assert.areEqual('The Smith Clan', both.Name, 'Custom name kept');
            Assert.areEqual('Dear Smith Clan', both.Household_Formal_Greeting__c, 'Kept');
            Assert.areEqual('Smiths', both.Household_Informal_Greeting__c, 'Kept');
        }
    }

    @IsTest
    static void upkeepStillRewordsAHouseholdThatIsNotCustomNamed() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
            household.Household_Formal_Greeting__c = 'Stale formal';
            household.Household_Informal_Greeting__c = 'Stale informal';
            Database.insert(household, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            insert smith(household.Id);
            Test.stopTest();

            Account saved = wordingOf(household.Id);
            Assert.areEqual('The Smith Family', saved.Name, 'Named from its members');
            Assert.areEqual('Mr. John Smith', saved.Household_Formal_Greeting__c, 'Recomputed');
            Assert.areEqual('John', saved.Household_Informal_Greeting__c, 'Recomputed');
        }
    }

    @IsTest
    static void upkeepFillsBlankGreetingsOnTwoHundredAndOneCustomNamedHouseholds() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < 201; i++) {
                Account household = HouseholdTestDataFactory.newHousehold('Typed ' + i);
                household.Custom_Name__c = true;
                household.Household_Formal_Greeting__c = 'Typed formal ' + i;
                households.add(household);
            }
            Database.insert(households, AccessLevel.SYSTEM_MODE);
            List<Contact> people = new List<Contact>();
            for (Account household : households) {
                people.add(smith(household.Id));
            }

            Test.startTest();
            insert people;
            Test.stopTest();

            Map<Id, Account> saved = new Map<Id, Account>(
                [
                    SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
                    FROM Account
                    WHERE Id IN :households
                    WITH SYSTEM_MODE
                ]
            );
            for (Integer i = 0; i < 201; i++) {
                Account household = saved.get(households[i].Id);
                Assert.areEqual('Typed ' + i, household.Name, 'Custom name kept');
                Assert.areEqual(
                    'Typed formal ' + i,
                    household.Household_Formal_Greeting__c,
                    'Typed formal greeting kept'
                );
                Assert.areEqual(
                    'John',
                    household.Household_Informal_Greeting__c,
                    'Blank informal greeting filled'
                );
            }
        }
    }

    /** Mr. John Smith, saved into `householdId`. */
    private static Contact smith(Id householdId) {
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.AccountId = householdId;
        return john;
    }

    private static Account wordingOf(Id householdId) {
        return [
            SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
            FROM Account
            WHERE Id = :householdId
            WITH SYSTEM_MODE
        ];
    }

    /** A Smith couple in a new household, saved and named as the running user. */
    private static Account namedSmithHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
        Database.insert(household, AccessLevel.SYSTEM_MODE);
        insert new List<Contact>{
            new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                Household_Role__c = 'Head',
                AccountId = household.Id
            ),
            new Contact(
                Salutation = 'Mrs.',
                FirstName = 'Jane',
                LastName = 'Smith',
                Household_Role__c = 'Spouse or Partner',
                AccountId = household.Id
            )
        };
        Test.startTest();
        HouseholdNamingService.applyNaming(new Set<Id>{ household.Id });
        Test.stopTest();
        return [
            SELECT Household_Formal_Greeting__c, Household_Informal_Greeting__c
            FROM Account
            WHERE Id = :household.Id
            WITH SYSTEM_MODE
        ];
    }

    /** The admin test user, switched to French, so their own labels differ from the org's. */
    private static User frenchSpeakingAdmin() {
        User admin = TestUsers.admin();
        admin.LanguageLocaleKey = 'fr';
        update admin;
        return admin;
    }

    @IsTest
    static void storedWordsUseTheOrgLanguageNotTheSaver() {
        OrgLanguageSelector.languageOverride = 'de';
        HouseholdNamingService.translationsForTest = new Map<String, String>{
            'de|Core_Households_Conjunction' => 'und'
        };
        System.runAs(frenchSpeakingAdmin()) {
            Assert.areEqual('fr', UserInfo.getLanguage(), 'The person saving reads French.');

            Account saved = namedSmithHousehold();

            Assert.areEqual(
                'Mr. und Mrs. John Smith',
                saved.Household_Formal_Greeting__c,
                'The greeting is worded in the org language, not the saver language.'
            );
            Assert.areEqual(
                'John und Jane',
                saved.Household_Informal_Greeting__c,
                'So is the informal greeting.'
            );
        }
    }

    @IsTest
    static void aMissingTranslationFallsBackToTheOrdinaryLabel() {
        OrgLanguageSelector.languageOverride = 'de';
        HouseholdNamingService.translationsForTest = new Map<String, String>();
        System.runAs(TestUsers.admin()) {
            Account saved = namedSmithHousehold();

            Assert.areEqual(
                'John ' + Label.Core_Households_Conjunction + ' Jane',
                saved.Household_Informal_Greeting__c,
                'With no word in the org language, the ordinary label is used.'
            );
        }
    }

    @IsTest
    static void anUnknownOrgLanguageFallsBackWithoutFailingTheSave() {
        OrgLanguageSelector.languageOverride = 'not_a_language';
        System.runAs(TestUsers.admin()) {
            Account saved = namedSmithHousehold();

            Assert.areEqual(
                'John ' + Label.Core_Households_Conjunction + ' Jane',
                saved.Household_Informal_Greeting__c,
                'A language the platform does not know still names the household.'
            );
        }
    }

    @IsTest
    static void theOrgLanguageLabelIsReadWithThePackageNamespace() {
        System.runAs(TestUsers.admin()) {
            Assert.isNotNull(OrgLanguageSelector.defaultLanguage(), 'Every org has a language.');
            Assert.areNotEqual(
                'fallback used',
                HouseholdNamingService.storedLabel('Core_Households_Conjunction', 'fallback used'),
                'The label is found by name in the org language, so the namespace is right.'
            );
        }
    }

    // ------------------------------------------------------------------ large households

    /** Thirty people, Mr. First01 Surname01 to Mr. First30 Surname30, in that order. */
    private static List<HouseholdService.Person> thirtySurnames() {
        List<HouseholdService.Person> members = new List<HouseholdService.Person>();
        for (Integer i = 1; i <= 30; i++) {
            String n = String.valueOf(i).leftPad(2, '0');
            members.add(HouseholdTestDataFactory.person('Mr.', 'First' + n, 'Surname' + n, null));
        }
        return members;
    }

    private static String othersEnding() {
        return Label.Core_Households_ListAndOthers.substringAfter('{1}');
    }

    @IsTest
    static void aLongSurnameListNamesTheFirstAndCountsTheRest() {
        System.runAs(TestUsers.admin()) {
            String name = HouseholdNamingService.computeName(thirtySurnames(), NAME_PATTERN, false);

            List<String> kept = new List<String>();
            for (Integer i = 1; i <= 21; i++) {
                kept.add('Surname' + String.valueOf(i).leftPad(2, '0'));
            }
            String expected =
                Label.Core_Households_ListAndOthers.replace('{1}', '9')
                    .replace('{0}', String.join(kept, Label.Core_Households_ListSeparator + ' ')) +
                ' ' +
                Label.Core_Households_NameSuffix;
            Assert.areEqual(
                expected,
                name,
                'As many surnames as fit are named and the rest counted, within the field'
            );
            Assert.isTrue(name.length() <= 255, 'The name fits Account Name: ' + name.length());
        }
    }

    @IsTest
    static void aLongPerPersonNameAndBothGreetingsFitTheirFields() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>();
            for (HouseholdService.Person person : thirtySurnames()) {
                person.lastName = 'Fitzgerald';
                members.add(person);
            }
            String name = HouseholdNamingService.computeName(
                members,
                '{FirstName} {LastName}',
                false
            );
            String formal = HouseholdNamingService.computeFormalGreeting(
                members,
                FORMAL_PATTERN,
                false
            );
            String informal = HouseholdNamingService.computeInformalGreeting(
                members,
                '{FirstName} {LastName}'
            );

            for (String value : new List<String>{ name, formal, informal }) {
                Assert.isTrue(value.length() <= 255, 'Fits its field: ' + value);
                Assert.isTrue(value.endsWith(othersEnding()), 'Counts who is left out: ' + value);
            }
            Assert.isTrue(name.startsWith('First01 Fitzgerald, First02 Fitzgerald'), name);
            Assert.isTrue(
                formal.startsWith('Mr. First01 Fitzgerald, Mr. First02 Fitzgerald'),
                formal
            );
        }
    }

    @IsTest
    static void oneLeftOutReadsAsOneOther() {
        System.runAs(TestUsers.admin()) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>{
                HouseholdTestDataFactory.person(null, 'Ann', 'A'.repeat(80), null),
                HouseholdTestDataFactory.person(null, 'Bob', 'B'.repeat(80), null),
                HouseholdTestDataFactory.person(null, 'Cal', 'C'.repeat(80), null)
            };
            String name = HouseholdNamingService.computeName(members, NAME_PATTERN, false);

            String kept =
                'A'.repeat(80) +
                Label.Core_Households_ListSeparator +
                ' ' +
                'B'.repeat(80);
            Assert.areEqual(
                Label.Core_Households_ListAndOneOther.replace('{0}', kept) +
                    ' ' +
                    Label.Core_Households_NameSuffix,
                name,
                'A single person left out is counted in the singular'
            );
        }
    }

    @IsTest
    static void aLongPatternIsCutAtAWordNeverInsideOne() {
        System.runAs(TestUsers.admin()) {
            String pattern = 'The {LastName} Family' + ' wordy'.repeat(60);
            String name = HouseholdNamingService.computeName(
                new List<HouseholdService.Person>{
                    HouseholdTestDataFactory.person('Ms.', 'Maria', 'Garcia', 'Head')
                },
                pattern,
                false
            );

            Assert.isTrue(name.length() <= 255, 'Fits Account Name: ' + name.length());
            Assert.isTrue(name.endsWith(' wordy'), 'Ends on a whole word: ' + name);
        }
    }

    /** Thirty contacts with differing surnames, saved into one contact-mode household. */
    private static Id householdOfThirty() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('Placeholder');
        Database.insert(household, AccessLevel.SYSTEM_MODE);
        List<Contact> people = new List<Contact>();
        for (HouseholdService.Person person : thirtySurnames()) {
            people.add(
                new Contact(
                    Salutation = person.salutation,
                    FirstName = person.firstName,
                    LastName = person.lastName,
                    AccountId = household.Id
                )
            );
        }
        insert people;
        return household.Id;
    }

    @IsTest
    static void aHouseholdOfThirtyIsSavedByMembershipUpkeep() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id householdId = householdOfThirty();
            Test.stopTest();

            Account saved = [
                SELECT
                    Name,
                    Member_Count__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :householdId
            ];
            Assert.areEqual(30, saved.Member_Count__c, 'The count is saved with the wording');
            Assert.isTrue(saved.Name.startsWith('Surname01, Surname02'), saved.Name);
            Assert.isTrue(
                saved.Household_Formal_Greeting__c.endsWith(othersEnding()),
                saved.Household_Formal_Greeting__c
            );
            Assert.isTrue(
                saved.Household_Informal_Greeting__c.startsWith('First01, First02'),
                saved.Household_Informal_Greeting__c
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing was refused');
        }
    }

    @IsTest
    static void aHouseholdOfThirtyIsSavedByApplyNaming() {
        System.runAs(TestUsers.admin()) {
            Id householdId = householdOfThirty();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Informal_Greeting_Pattern__c = '{FirstName} {LastName}';
            HouseholdTestDataFactory.save(settings);

            Test.startTest();
            Integer changed = HouseholdNamingService.applyNaming(new Set<Id>{ householdId });
            Test.stopTest();

            Account saved = [
                SELECT Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :householdId
            ];
            Assert.areEqual(1, changed, 'The new pattern is saved');
            Assert.isTrue(
                saved.Household_Informal_Greeting__c.startsWith('First01 Surname01, '),
                saved.Household_Informal_Greeting__c
            );
            Assert.isTrue(
                saved.Household_Informal_Greeting__c.endsWith(othersEnding()),
                saved.Household_Informal_Greeting__c
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Nothing was refused');
        }
    }
}
