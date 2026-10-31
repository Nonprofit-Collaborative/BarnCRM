@IsTest(testFor='ApexClass:MessagingEmailSender, ApexClass:EmailSendOutcome')
private class MessagingEmailSenderTest {
    @IsTest
    static void answersOncePerMessageAndSaysWhyOneFailed() {
        System.runAs(TestUsers.admin()) {
            MessagingEmailSender sender = new MessagingEmailSender();
            Assert.isTrue(sender.send(null).isEmpty(), 'No messages, no answers');
            Assert.isTrue(
                sender.send(new List<Messaging.SingleEmailMessage>()).isEmpty(),
                'An empty list is the same'
            );

            Messaging.SingleEmailMessage noRecipient = new Messaging.SingleEmailMessage();
            noRecipient.setSubject('Thank you');
            noRecipient.setPlainTextBody('Thank you for your gift.');
            Messaging.SingleEmailMessage reachable = new Messaging.SingleEmailMessage();
            reachable.setSubject('Thank you');
            reachable.setPlainTextBody('Thank you for your gift.');
            reachable.setToAddresses(new List<String>{ 'donor@example.org' });

            List<EmailSendOutcome> outcomes = sender.send(
                new List<Messaging.SingleEmailMessage>{ noRecipient, reachable }
            );

            Assert.areEqual(2, outcomes.size(), 'One answer for each message, in order');
            Assert.isFalse(outcomes[0].sent, 'A message with nobody to send to did not go');
            Assert.isTrue(
                String.isNotBlank(outcomes[0].error) && outcomes[0].error.length() <= 255,
                'And says why in no more than 255 characters'
            );
        }
    }
}
