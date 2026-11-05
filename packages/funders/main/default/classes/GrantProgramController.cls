/**
 * The Program card on a grant's page (F-01, canonical model 29ZH R-GN4, ADR-0161
 * `0161-funders-module.md` decision 6): which program the grant pays for, the programs to choose
 * from where the Programs module is installed, and saving the choice.
 *
 * Thin by design (plan Section 9.9): plain shapes out, the rules in `GrantService`. Everything
 * runs as the person.
 */
public with sharing class GrantProgramController {
	private static final String CONTEXT = 'GrantProgramController';

	/** What the card draws. */
	public class ProgramCard {
		/** Whether the Programs module is installed and the person can read programs. */
		@AuraEnabled
		public Boolean available = false;
		@AuraEnabled
		public Boolean canEdit = false;
		@AuraEnabled
		public String programId;
		@AuraEnabled
		public String programName;
		/** A program is named but cannot be found: deleted, or not visible to the person. */
		@AuraEnabled
		public Boolean missing = false;
		@AuraEnabled
		public List<Option> options = new List<Option>();
	}

	/** One program to choose. */
	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		public Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	/** The card for one grant. */
	@AuraEnabled
	public static ProgramCard getProgram(Id grantId) {
		try {
			ProgramCard card = new ProgramCard();
			List<Grant__c> grants = [
				SELECT Id, Program_Id__c
				FROM Grant__c
				WHERE Id = :grantId
				WITH USER_MODE
				LIMIT 1
			];
			if (grants.isEmpty()) {
				return card;
			}
			card.programId = grants[0].Program_Id__c;
			card.available = GrantService.programsAvailable();
			card.canEdit =
				card.available && Schema.SObjectType.Grant__c.fields.Program_Id__c.isUpdateable();
			if (!card.available) {
				return card;
			}
			for (Map<String, String> program : GrantService.programs()) {
				card.options.add(new Option(program.get('label'), program.get('value')));
			}
			if (String.isNotBlank(card.programId)) {
				card.programName = GrantService.programName(card.programId);
				card.missing = card.programName == null;
			}
			return card;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getProgram', grantId);
			throw UserErrors.message(Label.Funders_Program_ErrorLoad);
		}
	}

	/** Names the program the grant pays for, or clears it when `programId` is blank. */
	@AuraEnabled
	public static void setProgram(Id grantId, String programId) {
		if (!Schema.SObjectType.Grant__c.fields.Program_Id__c.isUpdateable()) {
			throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
		}
		try {
			GrantService.setProgram(grantId, programId);
		} catch (GrantService.GrantException e) {
			throw UserErrors.message(e.getMessage());
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.setProgram', grantId);
			throw UserErrors.message(Label.Funders_Pipeline_ErrorUnexpected);
		}
	}
}
