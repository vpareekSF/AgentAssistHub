public without sharing class AgentforceChatController2 {

    @TestVisible
    private static final String DEFAULT_AGENT_API_NAME = 'Agentforce_Employee_Agent';

    public class AgentReply {
        @AuraEnabled public String reply { get; set; }
        @AuraEnabled public String sessionId { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String status { get; set; }       // 'OK' | 'EMPTY' | 'ERROR'
        @AuraEnabled public String errorDetail { get; set; }  // serialized getErrors()
        @AuraEnabled public String outputKeys { get; set; }   // keys returned by the action
        @AuraEnabled public String runningUser { get; set; }  // UserInfo name/id
        @AuraEnabled public String agentApiName { get; set; } // resolved agent invoked
        @AuraEnabled public String senderRole { get; set; }   // 'enduser' | 'salesforceuser'
        @AuraEnabled public String promptInfo { get; set; }   // diagnostic note
    }

    /**
     * The generateAiAgentResponse action returns agentResponse as a JSON envelope
     * (e.g. {"type":"Text","value":"..."}). Unwrap the human-readable text, falling
     * back to the raw string if it is not a recognized envelope.
     */
    @TestVisible
    private static String extractResponseText(String rawResponse) {
        if (String.isBlank(rawResponse)) {
            return rawResponse;
        }
        try {
            Object parsed = JSON.deserializeUntyped(rawResponse);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> envelope = (Map<String, Object>) parsed;
                Object value = envelope.get('value');
                if (value instanceof String) {
                    return (String) value;
                }
                Object msg = envelope.get('message');
                if (msg instanceof String) {
                    return (String) msg;
                }
            }
        } catch (Exception ignored) {
            // Not JSON - treat as plain text below.
        }
        return rawResponse;
    }

    /**
     * Formats the message sent to the agent so the sender role travels as structured
     * context. End-user (customer) and Salesforce-user (rep) turns are prefixed with an
     * explicit role label; anything else is sent unchanged.
     */
    @TestVisible
    private static String formatMessageWithRole(String userMessage, String senderRole) {
        if (String.isBlank(senderRole)) {
            return userMessage;
        }
        String label;
        if (senderRole == 'enduser') {
            label = 'End User';
        } else if (senderRole == 'salesforceuser') {
            label = 'Salesforce User';
        } else {
            label = senderRole;
        }
        return '[Sender: ' + label + '] ' + userMessage;
    }

    /**
     * Invokes the agent. The sender role is passed to the agent's 'senderRole' context
     * variable when present, so the agent can branch on customer vs internal-user turns.
     */
    private static List<Invocable.Action.Result> invokeAgentAction(
        String agentApiName, String userMessage, String sessionId, String senderRole
    ) {
        Invocable.Action action =
            Invocable.Action.createCustomAction('generateAiAgentResponse', agentApiName);
        action.setInvocationParameter('userMessage', userMessage);
        if (String.isNotBlank(sessionId)) {
            action.setInvocationParameter('sessionId', sessionId);
        }
        if (String.isNotBlank(senderRole)) {
            // Parameter name must match the agent context variable API name.
            action.setInvocationParameter('senderRole', senderRole);
        }
        return action.invoke();
    }

    private static String appendNote(String existing, String note) {
        return String.isBlank(existing) ? note : existing + ' | ' + note;
    }

    @AuraEnabled
    public static AgentReply askAgent(String userMessage, String agentApiName, String sessionId, String senderRole) {
        if (String.isBlank(userMessage)) {
            throw new AuraHandledException('A message is required.');
        }
        String resolvedAgent = String.isBlank(agentApiName) ? DEFAULT_AGENT_API_NAME : agentApiName;
        String runningUser = UserInfo.getName() + ' (' + UserInfo.getUserId() + ')';

        AgentReply r = new AgentReply();
        r.runningUser = runningUser;
        r.agentApiName = resolvedAgent;
        r.senderRole = senderRole;

        // Tag the sender role inline so Agentforce can tell a customer turn from an
        // internal-user turn. No agent/App Builder configuration required.
        String outboundMessage = formatMessageWithRole(userMessage, senderRole);

        try {
            List<Invocable.Action.Result> results;
            try {
                results = invokeAgentAction(resolvedAgent, outboundMessage, sessionId, senderRole);
            } catch (Exception invokeEx) {
                // The agent may not accept the senderRole context variable; retry without it
                // so the role is still conveyed via the inline message tag.
                if (String.isNotBlank(senderRole)) {
                    r.promptInfo = appendNote(r.promptInfo,
                        'senderRole context var not accepted (' + invokeEx.getMessage() + '); retried without it');
                    System.debug(LoggingLevel.WARN, '[AgentforceChat2] senderRole var rejected: ' + invokeEx.getMessage());
                    results = invokeAgentAction(resolvedAgent, outboundMessage, sessionId, null);
                } else {
                    throw invokeEx;
                }
            }

            if (results.isEmpty()) {
                r.success = false;
                r.status = 'ERROR';
                r.errorDetail = 'No result returned from the action.';
                System.debug(LoggingLevel.INFO, '[AgentforceChat2] agent=' + resolvedAgent
                    + ' user=' + runningUser + ' -> no results returned');
                return r;
            }

            Invocable.Action.Result result = results[0];
            Map<String, Object> outputs = result.getOutputParameters();
            r.success = result.isSuccess();
            r.outputKeys = outputs == null ? '' : String.join(new List<String>(outputs.keySet()), ', ');
            r.errorDetail = JSON.serialize(result.getErrors());

            System.debug(LoggingLevel.INFO, '[AgentforceChat2] agent=' + resolvedAgent
                + ' user=' + runningUser
                + ' success=' + r.success
                + ' outputKeys=[' + r.outputKeys + ']'
                + ' errors=' + r.errorDetail
                + ' outputs=' + JSON.serialize(outputs));

            if (result.isSuccess()) {
                String rawResponse = outputs == null ? null : (String) outputs.get('agentResponse');
                r.reply = extractResponseText(rawResponse);
                r.sessionId = outputs == null ? null : (String) outputs.get('sessionId');
                r.status = String.isBlank(r.reply) ? 'EMPTY' : 'OK';
                return r;
            }

            r.status = 'ERROR';
            return r;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[AgentforceChat2] exception agent=' + resolvedAgent
                + ' user=' + runningUser + ' msg=' + e.getMessage());
            r.success = false;
            r.status = 'ERROR';
            r.errorDetail = 'Unable to reach the agent: ' + e.getMessage();
            return r;
        }
    }
}
