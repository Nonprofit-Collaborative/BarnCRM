/**
 * The member portal's action (PB-09, PAY-02; ADR-NEXT `NEXT-memberships-module.md`, decisions 6
 * and 7): `Memberships.PayDues` emails the member a link to pay their dues online. Portal Builder
 * calls it only for a verified person and a membership it found on that person's page; the term
 * is read again by that person before anything is queued. The checkout is started by a queued
 * job, since the portal has already written in this transaction and no callout may follow.
 */
@NamespaceAccessible
public with sharing class MembershipsPortalExtension implements PortalActionExtension {
	public static final String PAY_DUES = 'Memberships.PayDues';

	@NamespaceAccessible
	public MembershipsPortalExtension() {
		return;
	}

	public Set<String> actionNames() {
		return new Set<String>{ PAY_DUES };
	}

	public String run(String actionName, Id personId, Id recordId) {
		if (actionName != PAY_DUES) {
			throw new MembershipService.MembershipException(actionName);
		}
		return new Member().payDues(personId, recordId);
	}

	/**
	 * The portal's integration user has no record access of its own (ADR-0185 decision 9), so the
	 * term is read in system mode, and only when it is this person's.
	 */
	private without sharing class Member {
		String payDues(Id personId, Id termId) {
			if (
				[
					SELECT COUNT()
					FROM Membership_Term__c
					WHERE Id = :termId AND Contact__c = :personId
					WITH SYSTEM_MODE
				] == 0
			) {
				throw new MembershipService.MembershipException(
					BarnHelp.text('Memberships', 'Memberships_Error_NotFound')
				);
			}
			MembershipPayments.request(termId);
			return BarnHelp.text('Memberships', 'Memberships_Portal_LinkSent');
		}
	}
}
