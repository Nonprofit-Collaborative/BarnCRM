/**
 * What erasing a person does to the Programs module's records (canonical model R-ER8, R-EN5,
 * R-CN4; ADR-0110 `0110-erase-a-person-anonymizes-in-place.md`). Core finds this class by name in
 * `PersonErasureExtensions.EXTENSION_CLASSES` and calls it inside the erasure's own transaction,
 * so a refusal here takes the whole erasure back.
 *
 * The person's enrollments and service deliveries are kept, credited to the anonymized person,
 * so program counts stand; they hold no typed text. Their case notes and goals (with the goals'
 * steps, R-GL6) are deleted: each is typed text about the person and nothing else. Notes are read in system mode, so every note is
 * found whoever wrote it, and deleted as the user (R-ER5): someone erasing who may not delete
 * them all (Programs Admin may) is refused with that reason rather than leaving notes behind.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ProgramsErasureExtension implements PersonErasureExtension {
	@NamespaceAccessible
	public ProgramsErasureExtension() {
		return;
	}

	/** The module keeps nothing on the person's own record. */
	public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
		return new Set<Schema.SObjectField>();
	}

	public List<PersonErasure.Change> erase(Id personId) {
		List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
		List<Case_Note__c> notes = CaseNoteSelector.selectAllAbout(personId);
		if (!notes.isEmpty()) {
			List<Id> ids = new List<Id>();
			for (Case_Note__c note : notes) {
				ids.add(note.Id);
			}
			try {
				Database.delete(notes, true, AccessLevel.USER_MODE);
			} catch (Exception refused) {
				throw new PersonErasure.ErasureException(
					BarnHelp.text('Programs', 'Programs_Erase_NeedProgramsAdmin')
				);
			}
			changes.add(
				new PersonErasure.Change(
					PersonErasure.DELETED,
					Case_Note__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
						.getLabelPlural(),
					ids,
					null
				)
			);
		}
		List<Referral__c> referrals = ReferralSelector.selectAllAbout(personId);
		if (!referrals.isEmpty()) {
			List<Id> referralIds = new List<Id>();
			for (Referral__c referral : referrals) {
				referralIds.add(referral.Id);
			}
			try {
				Database.delete(referrals, true, AccessLevel.USER_MODE);
			} catch (Exception refused) {
				throw new PersonErasure.ErasureException(
					BarnHelp.text('Programs', 'Programs_Erase_NeedProgramsAdmin')
				);
			}
			changes.add(
				new PersonErasure.Change(
					PersonErasure.DELETED,
					Referral__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
						.getLabelPlural(),
					referralIds,
					null
				)
			);
		}
		// Goals are typed text about the person too (R-GL6); their steps go with them.
		List<Goal__c> goals = CaseNoteSelector.selectGoalsAbout(personId);
		if (!goals.isEmpty()) {
			List<Id> goalIds = new List<Id>();
			for (Goal__c goal : goals) {
				goalIds.add(goal.Id);
			}
			try {
				Database.delete(goals, true, AccessLevel.USER_MODE);
			} catch (Exception refused) {
				throw new PersonErasure.ErasureException(
					BarnHelp.text('Programs', 'Programs_Erase_NeedProgramsAdmin')
				);
			}
			changes.add(
				new PersonErasure.Change(
					PersonErasure.DELETED,
					Goal__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
						.getLabelPlural(),
					goalIds,
					null
				)
			);
		}
		Integer enrollments = CaseNoteSelector.countEnrollmentsOf(personId);
		if (enrollments > 0) {
			changes.add(
				new PersonErasure.Change(
					PersonErasure.KEPT,
					Enrollment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
						.getLabelPlural(),
					enrollments,
					BarnHelp.text('Programs', 'Programs_Erase_EnrollmentsKept')
				)
			);
		}
		return changes;
	}
}
