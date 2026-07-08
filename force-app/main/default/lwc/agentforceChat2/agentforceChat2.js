import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import CONVERSATION_ENDUSER_MESSAGE from '@salesforce/messageChannel/lightning__conversationEndUserMessage';
import askAgent from '@salesforce/apex/AgentforceChatController2.askAgent';

const DEFAULT_AGENT = 'Agentforce_Employee_Agent';

export default class AgentforceChat2 extends LightningElement {
    @api recordId;
    @api agentApiName = DEFAULT_AGENT;
    @api cardTitle = 'Agent Assist Hub';
    @api height = '500';
    @api manualOnly = false;
    @api showDiagnostics = false;
    @api supervisorChatUrl;
    @api supervisorTabLabel = 'Supervisor Chat';

    @track messages = [];
    draft = '';
    isLoading = false;
    sessionId = null;
    _keySeed = 0;
    _subscription = null;

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.subscribeToConversation();
    }

    disconnectedCallback() {
        this.unsubscribeFromConversation();
    }

    subscribeToConversation() {
        if (this._subscription) {
            return;
        }
        this._subscription = subscribe(
            this.messageContext,
            CONVERSATION_ENDUSER_MESSAGE,
            (message) => this.handleEndUserMessage(message)
        );
    }

    unsubscribeFromConversation() {
        if (this._subscription) {
            unsubscribe(this._subscription);
            this._subscription = null;
        }
    }

    handleEndUserMessage(message) {
        if (!message) {
            return;
        }
        // Only react to messages for the session this component is bound to.
        if (this.recordId && message.recordId && message.recordId !== this.recordId) {
            return;
        }
        const text = this.extractMessageText(message);
        if (!text) {
            return;
        }
        // Customer messages drive the recommendations but are not shown in the panel.
        if (!this.manualOnly) {
            this.sendToAgent(text, 'enduser');
        }
    }

    extractMessageText(message) {
        const raw =
            message.content ||
            message.text ||
            message.messageBody ||
            message.value ||
            '';
        return typeof raw === 'string' ? raw.trim() : '';
    }

    get effectiveAgent() {
        return this.agentApiName || DEFAULT_AGENT;
    }

    get containerStyle() {
        return `height:${this.height}px`;
    }

    get iframeStyle() {
        return `height:${this.height}px;width:100%;border:none;`;
    }

    get hasSupervisorUrl() {
        return !!this.supervisorChatUrl;
    }

    get isSendDisabled() {
        return this.isLoading || !this.draft || this.draft.trim().length === 0;
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    handleInput(event) {
        this.draft = event.target.value;
    }

    handleKeyUp(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }

    handleSend() {
        const text = (this.draft || '').trim();
        if (!text || this.isLoading) {
            return;
        }
        this.addMessage('salesforceuser', text);
        this.draft = '';
        this.sendToAgent(text, 'salesforceuser');
    }

    async sendToAgent(text, senderRole) {
        this.isLoading = true;
        try {
            const result = await askAgent({
                userMessage: text,
                agentApiName: this.effectiveAgent,
                sessionId: this.sessionId,
                senderRole
            });
            if (result && result.sessionId) {
                this.sessionId = result.sessionId;
            }
            const reply =
                result && result.reply
                    ? result.reply
                    : this.placeholderForStatus(result);
            this.addMessage('agent', reply, {
                triggerRole: senderRole,
                diagnostic: this.buildDiagnostic(result)
            });
        } catch (error) {
            this.showError(this.reduceError(error));
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    placeholderForStatus(result) {
        if (result && result.status === 'EMPTY') {
            return '(agent returned an empty reply)';
        }
        if (result && result.status === 'ERROR') {
            return '(agent error)';
        }
        return '(no response)';
    }

    buildDiagnostic(result) {
        if (!result) {
            return null;
        }
        const parts = [];
        if (result.agentApiName) {
            parts.push(`agent: ${result.agentApiName}`);
        }
        if (result.status) {
            parts.push(`status: ${result.status}`);
        }
        if (result.runningUser) {
            parts.push(`running as: ${result.runningUser}`);
        }
        if (result.promptInfo) {
            parts.push(`prompt: ${result.promptInfo}`);
        }
        if (this.sessionId) {
            parts.push(`session: ${this.sessionId}`);
        }
        if (result.outputKeys) {
            parts.push(`output keys: [${result.outputKeys}]`);
        }
        if (result.errorDetail && result.errorDetail !== '[]') {
            parts.push(`errors: ${result.errorDetail}`);
        }
        return parts.length ? parts.join('\n') : null;
    }

    handleCopy(event) {
        const text = event.currentTarget.dataset.text || '';
        if (navigator.clipboard && text) {
            navigator.clipboard.writeText(text);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Copied',
                    message: 'Suggested reply copied to clipboard.',
                    variant: 'success'
                })
            );
        }
    }

    addMessage(role, text, options) {
        const opts = options || {};
        this._keySeed += 1;
        const isRecommendation = role === 'agent';
        const isRepPrompt = role === 'salesforceuser';
        let caption = '';
        if (isRecommendation) {
            caption =
                opts.triggerRole === 'salesforceuser'
                    ? 'In response to your question'
                    : 'Based on the customer conversation';
        }
        this.messages = [
            ...this.messages,
            {
                key: `${role}-${this._keySeed}`,
                role,
                text,
                isRecommendation,
                isRepPrompt,
                caption,
                diagnostic: opts.diagnostic || null,
                showDiagnostic: this.showDiagnostics && !!opts.diagnostic
            }
        ];
        this.scrollToBottom();
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => {
            const log = this.template.querySelector('.message-log');
            if (log) {
                log.scrollTop = log.scrollHeight;
            }
        });
    }

    showError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Agent error',
                message,
                variant: 'error'
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return 'Something went wrong contacting the agent.';
    }
}
