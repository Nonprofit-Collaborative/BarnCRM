/**
 * The Funder Report card on a grant's page (F-06, canonical model 29ZO, ADR-0163
 * `0163-funders-reporting-links.md` decision 3): the active templates and everything their tokens
 * need, as plain JSON. The merge and the printable document are the framework-free
 * `grantReportModel`'s; nothing is saved. Everything runs as the person.
 */
public with sharing class GrantReportController {
	private static final String CONTEXT = 'GrantReportController';
	private static final Integer TEMPLATE_LIMIT = 100;

	/** What the card needs. */
	public class ReportData {
		@AuraEnabled
		public List<Map<String, String>> templates = new List<Map<String, String>>();
		/** The grant's values by token name, unformatted (amounts as numbers, dates as dates). */
		@AuraEnabled
		public Map<String, Object> grant = new Map<String, Object>();
		@AuraEnabled
		public List<Map<String, Object>> requirements = new List<Map<String, Object>>();
		/** The requirement table's column headings, from the field labels. */
		@AuraEnabled
		public Map<String, String> requirementLabels = new Map<String, String>();
		/** The outcomes the requirements report on, as `GrantOutcomeService.outcomes` gives them. */
		@AuraEnabled
		public List<Map<String, Object>> outcomes = new List<Map<String, Object>>();
		@AuraEnabled
		public String currencyCode;
	}

	/** The report data for one grant; empty templates and grant when the person cannot see it. */
	@AuraEnabled
	public static ReportData getReportData(Id grantId) {
		try {
			ReportData data = new ReportData();
			data.currencyCode = UserInfo.getDefaultCurrency();
			for (Funder_Report_Template__c template : [
				SELECT Id, Name, Body__c
				FROM Funder_Report_Template__c
				WHERE Active__c = TRUE
				WITH USER_MODE
				ORDER BY Name
				LIMIT :TEMPLATE_LIMIT
			]) {
				if (String.isNotBlank(template.Body__c)) {
					data.templates.add(
						new Map<String, String>{
							'id' => template.Id,
							'name' => template.Name,
							'body' => template.Body__c
						}
					);
				}
			}
			List<Grant__c> grants = [
				SELECT
					Name,
					Funder__r.Name,
					Funder_Contact__r.Name,
					Owner.Name,
					toLabel(Stage__c),
					toLabel(Funding_Source__c),
					Amount_Requested__c,
					Amount_Awarded__c,
					Application_Deadline__c,
					Award_Start_Date__c,
					Award_End_Date__c,
					Purpose__c,
					Program_Id__c,
					Assistance_Listing_Number__c,
					Award_Number__c,
					Federal_Agency__c,
					(
						SELECT
							Name,
							toLabel(Type__c),
							Due_Date__c,
							toLabel(Status__c),
							Submitted_Date__c,
							Outcome_Id__c
						FROM Requirements__r
						ORDER BY Due_Date__c, Name
					)
				FROM Grant__c
				WHERE Id = :grantId
				WITH USER_MODE
				LIMIT 1
			];
			if (grants.isEmpty()) {
				data.templates.clear();
				return data;
			}
			Grant__c grant = grants[0];
			data.grant = grantValues(grant);
			Set<String> linked = new Set<String>();
			for (Grant_Requirement__c requirement : grant.Requirements__r) {
				data.requirements.add(
					new Map<String, Object>{
						'name' => requirement.Name,
						'type' => requirement.Type__c,
						'dueDate' => requirement.Due_Date__c,
						'status' => requirement.Status__c,
						'submittedDate' => requirement.Submitted_Date__c
					}
				);
				if (String.isNotBlank(requirement.Outcome_Id__c)) {
					linked.add(requirement.Outcome_Id__c);
				}
			}
			data.requirementLabels = requirementLabels();
			data.outcomes = GrantOutcomeService.outcomes(
					linked,
					grant.Award_Start_Date__c,
					grant.Award_End_Date__c
				)
				.values();
			return data;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getReportData', grantId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Report_LoadFailed'));
		}
	}

	private static Map<String, Object> grantValues(Grant__c grant) {
		String organization = BarnCRM_Settings__c.getOrgDefaults().Organization_Legal_Name__c;
		return new Map<String, Object>{
			'OrganizationName' => String.isBlank(organization)
				? UserInfo.getOrganizationName()
				: organization,
			'Today' => Date.today(),
			'GrantName' => grant.Name,
			'FunderName' => grant.Funder__r?.Name,
			'FunderContactName' => grant.Funder_Contact__r?.Name,
			'OwnerName' => grant.Owner?.Name,
			'Stage' => grant.Stage__c,
			'FundingSource' => grant.Funding_Source__c,
			'AmountRequested' => grant.Amount_Requested__c,
			'AmountAwarded' => grant.Amount_Awarded__c,
			'ApplicationDeadline' => grant.Application_Deadline__c,
			'AwardStartDate' => grant.Award_Start_Date__c,
			'AwardEndDate' => grant.Award_End_Date__c,
			'Purpose' => grant.Purpose__c,
			'ProgramName' => GrantService.programName(grant.Program_Id__c),
			'AssistanceListingNumber' => grant.Assistance_Listing_Number__c,
			'AwardNumber' => grant.Award_Number__c,
			'FederalAgency' => grant.Federal_Agency__c
		};
	}

	private static Map<String, String> requirementLabels() {
		return new Map<String, String>{
			'name' => Schema.SObjectType.Grant_Requirement__c.fields.Name.getLabel(),
			'type' => Schema.SObjectType.Grant_Requirement__c.fields.Type__c.getLabel(),
			'dueDate' => Schema.SObjectType.Grant_Requirement__c.fields.Due_Date__c.getLabel(),
			'status' => Schema.SObjectType.Grant_Requirement__c.fields.Status__c.getLabel(),
			'submittedDate' => Schema.SObjectType.Grant_Requirement__c.fields.Submitted_Date__c.getLabel()
		};
	}
}
