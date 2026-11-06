/**
 * The Logic Model Outcomes card on a grant's page (L-06, canonical model 29ZI R-GQ6): each
 * requirement of the grant with the outcome it reports on and that outcome's indicator results for
 * the award period, the outcomes to choose from where Logic Models is installed, and saving a
 * choice.
 *
 * Thin by design (plan Section 9.9): plain shapes out, the reads and rules in
 * `GrantOutcomeService`. Everything runs as the person.
 */
public with sharing class GrantOutcomeController {
	private static final String CONTEXT = 'GrantOutcomeController';

	/** What the card draws. */
	public class OutcomeCard {
		/** Whether Logic Models is installed and the person can read it. */
		@AuraEnabled
		public Boolean available = false;
		@AuraEnabled
		public Boolean canEdit = false;
		@AuraEnabled
		public List<Map<String, String>> options = new List<Map<String, String>>();
		@AuraEnabled
		public List<Row> rows = new List<Row>();
	}

	/** One requirement of the grant. */
	public class Row {
		@AuraEnabled
		public String requirementId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public String outcomeId;
		/** The outcome with its indicators and periods, as `GrantOutcomeService.outcomes` gives it. */
		@AuraEnabled
		public Map<String, Object> outcome;
		/** An outcome is named but cannot be found: deleted, or not visible to the person. */
		@AuraEnabled
		public Boolean missing = false;
	}

	/** The card for one grant. */
	@AuraEnabled
	public static OutcomeCard getOutcomes(Id grantId) {
		try {
			OutcomeCard card = new OutcomeCard();
			List<Grant__c> grants = [
				SELECT
					Id,
					Award_Start_Date__c,
					Award_End_Date__c,
					(
						SELECT Id, Name, Type__c, Due_Date__c, Outcome_Id__c
						FROM Requirements__r
						ORDER BY Due_Date__c, Name
					)
				FROM Grant__c
				WHERE Id = :grantId
				WITH USER_MODE
				LIMIT 1
			];
			card.available = GrantOutcomeService.available();
			if (grants.isEmpty() || !card.available) {
				return card;
			}
			Grant__c grant = grants[0];
			card.canEdit = Schema.SObjectType.Grant_Requirement__c.fields.Outcome_Id__c.isUpdateable();
			card.options = GrantOutcomeService.outcomeOptions();
			Set<String> linked = new Set<String>();
			for (Grant_Requirement__c requirement : grant.Requirements__r) {
				if (String.isNotBlank(requirement.Outcome_Id__c)) {
					linked.add(requirement.Outcome_Id__c);
				}
			}
			Map<String, Map<String, Object>> outcomes = GrantOutcomeService.outcomes(
				linked,
				grant.Award_Start_Date__c,
				grant.Award_End_Date__c
			);
			for (Grant_Requirement__c requirement : grant.Requirements__r) {
				Row row = new Row();
				row.requirementId = requirement.Id;
				row.name = requirement.Name;
				row.type = requirement.Type__c;
				row.dueDate = requirement.Due_Date__c;
				row.outcomeId = requirement.Outcome_Id__c;
				row.outcome = outcomes.get(requirement.Outcome_Id__c);
				row.missing = String.isNotBlank(row.outcomeId) && row.outcome == null;
				card.rows.add(row);
			}
			return card;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getOutcomes', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Outcomes_LoadFailed'));
		}
	}

	/** Names the outcome a requirement reports on, or clears it when `outcomeId` is blank. */
	@AuraEnabled
	public static void setOutcome(Id requirementId, String outcomeId) {
		if (!Schema.SObjectType.Grant_Requirement__c.fields.Outcome_Id__c.isUpdateable()) {
			throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
		}
		try {
			GrantOutcomeService.setOutcome(requirementId, outcomeId);
		} catch (GrantOutcomeService.GrantOutcomeException e) {
			throw UserErrors.message(e.getMessage());
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.setOutcome', requirementId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
		}
	}
}
