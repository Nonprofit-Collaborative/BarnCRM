/**
 * The Health Check questions about household data: is everyone in a household, and does
 * every household have somebody in it (plan Section 4.8, "orphaned records"; C-21, ADR-0048).
 *
 * A fourth group beside the three ADR-0039 names, because those three ask about what the org
 * is, who can use it and how it is configured, and these ask about the records in it. They
 * detect and link; they never fix. Deciding what a person with no household or an empty
 * household should become is a question about the organization's data, which a button cannot
 * answer, and bulk cleanup belongs to the data hygiene console (C-28).
 *
 * What counts follows the canonical model: a person is expected to be in a household only
 * while automatic household creation is on (R-C1), and a contact whose account is an
 * organization belongs to that organization, not to no household (Section 7). The reads are in
 * HouseholdOrphanSelector, in user mode and capped, so a large org gets "more than" and five
 * links rather than a count of every row.
 */
public with sharing class HealthCheckHouseholdChecks {
    /** Counts stop here, and the finding says "more than" this many. A test lowers it. */
    @TestVisible
    private static Integer countCap = 1000;

    /** How many records a finding links to. */
    private static final Integer LINKS_SHOWN = 5;

    /** People with no household while every person is meant to have one. */
    public class PeopleWithoutHouseholdCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return peopleWithoutHouseholdFinding();
        }
    }

    /** Households nobody is currently a member of. */
    public class HouseholdsWithoutMembersCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return householdsWithoutMembersFinding();
        }
    }

    /** Relationships whose person on either side was deleted (PEOPLE-19). */
    public class RelationshipsWithoutPersonCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return orphanFinding(
                'relationships_without_person',
                PersonLinkOrphanSelector.countRelationships(countCap + 1),
                PersonLinkOrphanSelector.relationships(LINKS_SHOWN),
                System.Label.Core_HealthCheck_RelationshipsNoPersonTitle,
                System.Label.Core_HealthCheck_RelationshipsNoPersonDetail,
                HealthCheckService.SEVERITY_WARNING,
                false
            );
        }
    }

    /** Affiliations whose person was deleted (PEOPLE-19). */
    public class AffiliationsWithoutPersonCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return orphanFinding(
                'affiliations_without_person',
                PersonLinkOrphanSelector.countAffiliations(countCap + 1),
                PersonLinkOrphanSelector.affiliations(LINKS_SHOWN),
                System.Label.Core_HealthCheck_AffiliationsNoPersonTitle,
                System.Label.Core_HealthCheck_AffiliationsNoPersonDetail,
                HealthCheckService.SEVERITY_WARNING,
                false
            );
        }
    }

    private static HealthCheckService.Finding peopleWithoutHouseholdFinding() {
        Id householdType = HouseholdService.householdRecordTypeId();
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        Boolean expected = settings != null && settings.Auto_Create_Households__c == true;
        if (householdType == null || !expected) {
            return null;
        }
        Integer count;
        List<SObject> first = new List<SObject>();
        String detail;
        if (HouseholdService.isJunctionMode()) {
            Set<Id> personTypes = personRecordTypeIds();
            Set<Id> excluded = new Set<Id>(personTypes);
            excluded.add(householdType);
            count = HouseholdOrphanSelector.countContactsWithoutMembership(excluded, countCap + 1);
            first.addAll(HouseholdOrphanSelector.contactsWithoutMembership(excluded, LINKS_SHOWN));
            if (!personTypes.isEmpty()) {
                count += HouseholdOrphanSelector.countPersonAccountsWithoutMembership(
                    personTypes,
                    countCap + 1
                );
                if (first.size() < LINKS_SHOWN) {
                    first.addAll(
                        HouseholdOrphanSelector.personAccountsWithoutMembership(
                            personTypes,
                            LINKS_SHOWN - first.size()
                        )
                    );
                }
            }
            detail = System.Label.Core_HealthCheck_PeopleWithoutHouseholdJunctionDetail;
        } else {
            count = HouseholdOrphanSelector.countContactsWithoutAccount(countCap + 1);
            first.addAll(HouseholdOrphanSelector.contactsWithoutAccount(LINKS_SHOWN));
            detail = System.Label.Core_HealthCheck_PeopleWithoutHouseholdContactDetail;
        }
        return orphanFinding(
            'people_without_household',
            count,
            first,
            System.Label.Core_HealthCheck_PeopleWithoutHouseholdTitle,
            detail,
            HealthCheckService.SEVERITY_WARNING,
            true
        );
    }

    private static HealthCheckService.Finding householdsWithoutMembersFinding() {
        Id householdType = HouseholdService.householdRecordTypeId();
        if (householdType == null) {
            return null;
        }
        Boolean junction = HouseholdService.isJunctionMode();
        Integer count = junction
            ? HouseholdOrphanSelector.countHouseholdsWithoutMembers(householdType, countCap + 1)
            : HouseholdOrphanSelector.countHouseholdsWithoutContacts(householdType, countCap + 1);
        List<SObject> first = junction
            ? HouseholdOrphanSelector.householdsWithoutMembers(householdType, LINKS_SHOWN)
            : HouseholdOrphanSelector.householdsWithoutContacts(householdType, LINKS_SHOWN);
        return orphanFinding(
            'households_without_members',
            count,
            first,
            System.Label.Core_HealthCheck_EmptyHouseholdsTitle,
            System.Label.Core_HealthCheck_EmptyHouseholdsDetail,
            HealthCheckService.SEVERITY_INFO,
            true
        );
    }

    /**
     * One finding for a count of orphans, or null when there are none. No fix: the links are
     * the records to open. In an org that also has Nonprofit Cloud households the detail says
     * that some may belong to one, because BarnCRM cannot see that membership (R-H12); that
     * note is left off the person-link findings, which are about BarnCRM's own records.
     */
    private static HealthCheckService.Finding orphanFinding(
        String key,
        Integer count,
        List<SObject> first,
        String title,
        String detail,
        String severity,
        Boolean mayBeNativeHousehold
    ) {
        if (count == null || count <= 0) {
            return null;
        }
        String counted = count > countCap
            ? String.format(
                  System.Label.Core_HealthCheck_OrphansMoreThan,
                  new List<Object>{ countCap.format() }
              )
            : count.format();
        String text = detail;
        if (!first.isEmpty()) {
            text +=
                ' ' +
                String.format(
                    System.Label.Core_HealthCheck_OrphansFirstListed,
                    new List<Object>{ String.valueOf(first.size()) }
                );
        }
        if (mayBeNativeHousehold && hasNativeHouseholds()) {
            text += ' ' + System.Label.Core_HealthCheck_OrphansNativeNote;
        }
        List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
        for (SObject record : first) {
            links.add(new HealthCheckService.Link(record));
        }
        return new HealthCheckService.Finding(
                key,
                String.format(title, new List<Object>{ counted }),
                text,
                severity,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withLinks(links);
    }

    private static Set<Id> personRecordTypeIds() {
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        return shape == null ||
            shape.personAccountRecordTypeIds == null
            ? new Set<Id>()
            : shape.personAccountRecordTypeIds;
    }

    private static Boolean hasNativeHouseholds() {
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        return shape != null && shape.hasNativeHouseholdGroups == true;
    }
}
