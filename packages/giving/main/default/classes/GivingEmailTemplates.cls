/**
 * The email template plumbing acknowledgments and pledge reminders share: the templates a page
 * offers, the ids behind the developer names a rule or step names, and one message composed by
 * the platform from a template.
 *
 * A rule or step names a template by developer name because no custom lookup to a template is
 * possible (ADR-0032), so the page shows the two names together and the send looks the id up.
 */
public with sharing class GivingEmailTemplates {
    /** One email template the org has, so a rule or step can name it. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String developerName;
    }

    /** The org's active email templates, by label and developer name. */
    public static List<Option> options() {
        List<Option> options = new List<Option>();
        for (EmailTemplate template : AcknowledgmentSelector.activeTemplates()) {
            Option option = new Option();
            option.label = template.Name;
            option.developerName = template.DeveloperName;
            options.add(option);
        }
        return options;
    }

    /** Each option's label, by its developer name. */
    public static Map<String, String> labelsByDeveloperName(List<Option> options) {
        Map<String, String> labels = new Map<String, String>();
        for (Option option : options) {
            labels.put(option.developerName, option.label);
        }
        return labels;
    }

    /** The template ids behind these developer names; a name with no template is left out. */
    public static Map<String, Id> idsByDeveloperName(Set<String> developerNames) {
        Map<String, Id> byName = new Map<String, Id>();
        if (developerNames.isEmpty()) {
            return byName;
        }
        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :developerNames
            WITH SYSTEM_MODE
        ]) {
            byName.put(template.DeveloperName, template.Id);
        }
        return byName;
    }

    /**
     * One message, composed by the platform from the template. The contact is the target so that
     * `{!Contact.FirstName}` resolves, and the record is the `WhatId` so that its own merge
     * fields do. The package composes no HTML and merges no tokens of its own.
     *
     * The activity is not saved, because logging a task per email would make this feature
     * depend on a standard object the packages may not use (plan Section 4.2).
     */
    public static Messaging.SingleEmailMessage message(
        Id whatId,
        Id recipientContactId,
        Id templateId,
        Id fromAddressId
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTemplateId(templateId);
        message.setTargetObjectId(recipientContactId);
        message.setWhatId(whatId);
        message.setTreatTargetObjectAsRecipient(true);
        message.setSaveAsActivity(false);
        if (fromAddressId != null) {
            message.setOrgWideEmailAddressId(fromAddressId);
        }
        return message;
    }
}
