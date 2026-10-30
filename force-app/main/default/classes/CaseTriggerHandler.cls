/**
 * Routes Case update trigger contexts to the escalation service.
 */
public with sharing class CaseTriggerHandler extends TriggerHandler {

    private final List<Case> newCases;
    private final Map<Id,Case> oldCasesById;

    /**
     * Captures the current Case trigger records and their previous values.
     */
    public CaseTriggerHandler() {
        this.newCases = (List<Case>) Trigger.new;
        this.oldCasesById = (Map<Id,Case>) Trigger.oldMap;
    }

    protected override void beforeUpdate(){
        CaseEscalationService.validateAndSetPriorityForEscalations(newCases, oldCasesById);
    }

    protected override void afterUpdate(){
        CaseEscalationService.createReviewTasksForEscalations(newCases, oldCasesById);
    }
}
