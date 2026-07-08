@isTest
private class AgentforceChatControllerTest2 {

    @isTest
    static void askAgent_blankMessage_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgentforceChatController2.askAgent('', 'Some_Agent', null, 'enduser');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Blank message should raise an AuraHandledException.');
    }

    @isTest
    static void askAgent_blankAgent_returnsDiagnosticReply() {
        // With a blank agent name the controller falls back to the default agent.
        // The GenAI action cannot execute in a test context, so the invocation is
        // captured and returned as a diagnostic DTO (status ERROR/EMPTY) rather than thrown.
        Test.startTest();
        AgentforceChatController2.AgentReply r =
            AgentforceChatController2.askAgent('Hello', '', null, 'salesforceuser');
        Test.stopTest();

        System.assertNotEquals(null, r, 'A diagnostic reply should always be returned.');
        System.assertNotEquals(null, r.runningUser, 'Running user should be captured for diagnostics.');
        System.assertEquals('salesforceuser', r.senderRole, 'Sender role should be echoed back.');
        System.assert(
            r.status == 'ERROR' || r.status == 'EMPTY' || r.status == 'OK',
            'Status should be populated, was: ' + r.status
        );
    }

    @isTest
    static void formatMessageWithRole_prefixesKnownRoles() {
        System.assertEquals(
            '[Sender: End User] hello',
            AgentforceChatController2.formatMessageWithRole('hello', 'enduser'),
            'End user role should be labeled.'
        );
        System.assertEquals(
            '[Sender: Salesforce User] hello',
            AgentforceChatController2.formatMessageWithRole('hello', 'salesforceuser'),
            'Salesforce user role should be labeled.'
        );
        System.assertEquals(
            'hello',
            AgentforceChatController2.formatMessageWithRole('hello', null),
            'Blank role should pass the message through unchanged.'
        );
    }

    @isTest
    static void extractResponseText_unwrapsEnvelope() {
        String envelope = '{"type":"Text","value":"Hello from the agent"}';
        System.assertEquals(
            'Hello from the agent',
            AgentforceChatController2.extractResponseText(envelope),
            'Should unwrap the value from the JSON envelope.'
        );
    }

    @isTest
    static void extractResponseText_passthroughPlainText() {
        System.assertEquals(
            'just text',
            AgentforceChatController2.extractResponseText('just text'),
            'Plain text should pass through unchanged.'
        );
        System.assertEquals(
            null,
            AgentforceChatController2.extractResponseText(null),
            'Null should pass through.'
        );
    }

    @isTest
    static void agentReply_dto_holdsValues() {
        AgentforceChatController2.AgentReply r = new AgentforceChatController2.AgentReply();
        r.reply = 'Hi there';
        r.sessionId = 'abc-123';
        r.success = true;
        r.status = 'OK';
        r.runningUser = 'Tester (005000000000000)';
        r.outputKeys = 'agentResponse, sessionId';
        r.errorDetail = '[]';
        r.senderRole = 'enduser';
        r.promptInfo = 'diagnostic note';
        System.assertEquals('enduser', r.senderRole, 'Sender role should be retained.');
        System.assertNotEquals(null, r.promptInfo, 'Prompt info should be retained.');
        System.assertEquals('Hi there', r.reply, 'Reply should be retained.');
        System.assertEquals('abc-123', r.sessionId, 'Session id should be retained.');
        System.assertEquals('OK', r.status, 'Status should be retained.');
        System.assertEquals(true, r.success, 'Success flag should be retained.');
        System.assertNotEquals(null, r.runningUser, 'Running user should be retained.');
    }
}
