/**
 * Applies Case escalation rules and creates review Tasks for valid escalations.
 */
public with sharing class CaseEscalationService {

    private static final String MISSING_ACCOUNT_MESSAGE =
        'AccountId is required when changing Status to Escalated.';

    private static final String REVIEW_TASK_SUBJECT =
        'Review escalated case';

    @TestVisible
    private static Id reviewTaskOwnerIdOverride;

    private CaseEscalationService() {
    }

    /**
     * Validates escalating Cases and sets valid records to High priority.
     *
     * @param newCases Cases in their updated state.
     * @param oldCasesById Cases in their state before the update, keyed by Id.
     */
    public static void validateAndSetPriorityForEscalations(List<Case> newCases, Map<Id, Case> oldCasesById){
        validateCaseUpdateInputs(newCases, oldCasesById);
        if(newCases.isEmpty()){
            return;
        }

        List<Case> escalationCases = selectCasesTransitioningToEscalated(newCases, oldCasesById);
        if(escalationCases.isEmpty()){
            return;
        }

        List<Case> validTargetCases = validateAccountIdsAndSelectValidCases(escalationCases);

        for(Case caseRecord: validTargetCases){
            caseRecord.Priority = 'High';
        }
    }

    /**
     * Creates one review Task for each valid Case transitioning to Escalated.
     *
     * @param newCases Cases in their saved state.
     * @param oldCasesById Cases in their state before the update, keyed by Id.
     */
    public static void createReviewTasksForEscalations(List<Case> newCases, Map<Id, Case> oldCasesById){
        validateCaseUpdateInputs(newCases, oldCasesById);
        if(newCases.isEmpty()){
            return;
        }

        List<Case> escalationCases = selectCasesTransitioningToEscalated(newCases, oldCasesById);
        if(escalationCases.isEmpty()){
            return;
        }

        List<Case> validTargetCases = validateAccountIdsAndSelectValidCases(escalationCases);
        if(validTargetCases.isEmpty()){
            return;
        }

        List<Task> reviewTasks = new List<Task>();
        for(Case caseRecord : validTargetCases){
            reviewTasks.add(
                new Task(
                    WhatId = caseRecord.Id,
                    OwnerId = reviewTaskOwnerIdOverride == null
                        ? caseRecord.OwnerId
                        : reviewTaskOwnerIdOverride,
                    Subject = REVIEW_TASK_SUBJECT
                )
            );
        }

        Database.insert(
            reviewTasks,
            true,
            System.AccessLevel.SYSTEM_MODE
        );
    }

    //new List、old Map、各要素とId対応の構造検証
    private static void validateCaseUpdateInputs(List<Case> newCases, Map<Id, Case> oldCasesById){

        if(newCases == null){
            throw new IllegalArgumentException('New Case list must not be null.');
        }
        if(oldCasesById == null){
            throw new IllegalArgumentException('Old Case map must not be null.');
        }
        for(Integer inputIndex = 0 ; inputIndex < newCases.size() ; inputIndex++){
            Case newCase = newCases[inputIndex];

            //List内null
            if(newCase == null){
                throw new IllegalArgumentException(
                    'New Case must not be null. inputIndex='
                    + inputIndex
                );
            }
            //CaseIdがnull
            if(newCase.Id == null){
                throw new IllegalArgumentException(
                    'New Case Id must not be null. inputIndex='
                    + inputIndex
                );
            }
            //old Mapに new Case Idのキーがない
            if(!oldCasesById.containsKey(newCase.Id)){
                throw new IllegalArgumentException(
                    'Old Case map does not contain the new Case Id. inputIndex='
                    + inputIndex
                    + ', caseId='
                    + newCase.Id
                );
            }

            //old Mapの対応Caseがnull(先にCase Idのキーがあることを確認する必要あり)
            Case oldCase = oldCasesById.get(newCase.Id);
            if(oldCase == null){
                throw new IllegalArgumentException(
                    'Old Case must not be null. inputIndex='
                    + inputIndex
                    + ', caseId='
                    + newCase.Id
                );
            }
        }
    }

    //Status遷移対象を入力順で抽出。対象なしは空List
    private static List<Case> selectCasesTransitioningToEscalated(List<Case> newCases, Map<Id, Case> oldCasesById){
        List<Case> escalationCases = new List<Case>();
        for(Case caseRecord : newCases){
            if(oldCasesById.get(caseRecord.Id).Status != 'Escalated' && caseRecord.Status == 'Escalated'){
               escalationCases.add(caseRecord);
            }
        }
        return escalationCases;
    }

    //AccountIdの検証
    private static List<Case> validateAccountIdsAndSelectValidCases(List<Case> escalationCases){
        List<Case> validTargetCases = new List<Case>();
        for(Case caseRecord : escalationCases){
            if(caseRecord.AccountId == null){
                caseRecord.addError(MISSING_ACCOUNT_MESSAGE);
                continue;
            }
            validTargetCases.add(caseRecord);
        }
        return validTargetCases;
    }
}
