/**
 * One rule from canonical model R-H4 to R-H9 per test method.
 */
@IsTest
private class HouseholdNamingServiceTest {
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
            insert household;
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
    static void customNameStopsEveryRecomputation() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold(
                'The Reverend and Mrs. Smith'
            );
            household.Custom_Name__c = true;
            insert household;
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
}
