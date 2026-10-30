@IsTest
private class CaseEscalationServiceTest {

    private static final String MISSING_ACCOUNT_MESSAGE =
        'AccountId is required when changing Status to Escalated.';
    private static final String REVIEW_TASK_SUBJECT =
        'Review escalated case';
    private static final String PREPARATION_DESCRIPTION =
        'Service test preparation';

    private enum ServiceOperation {
        BEFORE,
        AFTER
    }

    // ============================================================
    // Before business behavior
    // ============================================================

    @IsTest
    static void validateAndSetPriorityForEscalations_singleTransition_setsPriorityHigh() {
        Account accountRecord = insertTestAccount('Before Single');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated' }
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual('High', inputs.newCases[0].Priority, 'Priority must be changed to High.');
        assertNoErrors(inputs.newCases[0], 'The valid escalation Case must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_multipleTransitions_setsAllPrioritiesHigh() {
        Account accountRecord = insertTestAccount('Before Multiple');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low'),
            buildTestCase(accountRecord.Id, 'Working', 'Medium'),
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated', 'Escalated', 'Escalated' }
        );
        List<Case> originalReferences = new List<Case>();
        originalReferences.addAll(inputs.newCases);

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(3, inputs.newCases.size(), 'The input List size must remain unchanged.');
        for (Integer inputIndex = 0; inputIndex < inputs.newCases.size(); inputIndex++) {
            Assert.isTrue(
                inputs.newCases[inputIndex] === originalReferences[inputIndex],
                'The Case reference and input order must remain unchanged. inputIndex=' + inputIndex
            );
            Assert.areEqual(
                'High',
                inputs.newCases[inputIndex].Priority,
                'Every target Case must have High priority. inputIndex=' + inputIndex
            );
            assertNoErrors(
                inputs.newCases[inputIndex],
                'A valid target Case must not have errors. inputIndex=' + inputIndex
            );
        }
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_twoHundredTransitions_setsAllPrioritiesHigh() {
        Account accountRecord = insertTestAccount('Before 200');
        List<Case> casesToInsert = new List<Case>();
        List<String> newStatuses = new List<String>();
        for (Integer inputIndex = 0; inputIndex < 200; inputIndex++) {
            casesToInsert.add(buildTestCase(accountRecord.Id, 'New', 'Low'));
            newStatuses.add('Escalated');
        }
        List<Case> persistedCases = insertTestCases(casesToInsert);
        CaseUpdateInputs inputs = createUpdateInputs(persistedCases, newStatuses);

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(200, inputs.newCases.size(), 'The service must process all 200 Cases.');
        for (Integer inputIndex = 0; inputIndex < inputs.newCases.size(); inputIndex++) {
            Assert.areEqual(
                'High',
                inputs.newCases[inputIndex].Priority,
                'Every target Case must have High priority. inputIndex=' + inputIndex
            );
            assertNoErrors(
                inputs.newCases[inputIndex],
                'A valid target Case must not have errors. inputIndex=' + inputIndex
            );
        }
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_nonTargetTransitions_doesNotChangePriority() {
        Account accountRecord = insertTestAccount('Before Non Target');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low'),
            buildTestCase(accountRecord.Id, 'Escalated', 'Medium'),
            buildTestCase(accountRecord.Id, 'Escalated', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Working', 'Escalated', 'Working' }
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual('Low', inputs.newCases[0].Priority, 'New to Working must remain Low.');
        Assert.areEqual('Medium', inputs.newCases[1].Priority, 'Escalated to Escalated must remain Medium.');
        Assert.areEqual('Low', inputs.newCases[2].Priority, 'Escalated to Working must remain Low.');
        for (Case caseRecord : inputs.newCases) {
            assertNoErrors(caseRecord, 'A non-target Case must not have errors.');
        }
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_missingAccount_addsErrorAndPreservesPriority() {
        Account accountRecord = insertTestAccount('Before Missing Account');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated' }
        );
        inputs.newCases[0].AccountId = null;

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual('Low', inputs.newCases[0].Priority, 'An invalid target Case must preserve Priority.');
        assertMissingAccountError(inputs.newCases[0]);
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_validAndMissingAccounts_processesEachCase() {
        Account accountRecord = insertTestAccount('Before Mixed');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low'),
            buildTestCase(accountRecord.Id, 'Working', 'Medium'),
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated', 'Escalated', 'Working' }
        );
        inputs.newCases[1].AccountId = null;
        inputs.newCases[2].AccountId = null;

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual('High', inputs.newCases[0].Priority, 'The valid target Case must become High.');
        assertNoErrors(inputs.newCases[0], 'The valid target Case must not have errors.');
        Assert.areEqual('Medium', inputs.newCases[1].Priority, 'The invalid target Case must remain Medium.');
        assertMissingAccountError(inputs.newCases[1]);
        Assert.areEqual('Low', inputs.newCases[2].Priority, 'The non-target Case must remain Low.');
        assertNoErrors(
            inputs.newCases[2],
            'A non-target Case must not be AccountId-validated even when AccountId is null.'
        );
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    // ============================================================
    // Before structural input validation
    // ============================================================

    @IsTest
    static void validateAndSetPriorityForEscalations_nullNewCases_throwsIllegalArgumentException() {
        Account accountRecord = insertTestAccount('Before Null New');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        Case oldCase = persistedCases[0].clone(true, false, false, false);
        Map<Id, Case> oldCasesById = new Map<Id, Case>{ oldCase.Id => oldCase };

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.BEFORE,
            null,
            oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'New Case list must not be null.',
            actualException.getMessage(),
            'The null new List message must match the contract.'
        );
        Assert.areEqual('Low', oldCase.Priority, 'The old Case Priority must remain unchanged.');
        assertNoErrors(oldCase, 'The old Case must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_nullOldCasesById_throwsIllegalArgumentException() {
        List<Case> newCases = new List<Case>();

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.BEFORE,
            newCases,
            null
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'Old Case map must not be null.',
            actualException.getMessage(),
            'The old Map null check must run before the empty List return.'
        );
        Assert.areEqual(0, newCases.size(), 'The empty input List must remain empty.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_emptyNewCases_returnsWithoutChanges() {
        List<Case> newCases = new List<Case>();
        Map<Id, Case> oldCasesById = new Map<Id, Case>();

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.validateAndSetPriorityForEscalations(newCases, oldCasesById);
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(0, newCases.size(), 'The empty input List must remain empty.');
        Assert.areEqual(0, oldCasesById.size(), 'The empty old Map must remain empty.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_containingNullCase_throwsBeforeModification() {
        Account accountRecord = insertTestAccount('Before List Null');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low'),
            buildTestCase(accountRecord.Id, 'Working', 'Medium')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated', 'Escalated' }
        );
        Case firstCase = inputs.newCases[0];
        Case thirdCase = inputs.newCases[1];
        inputs.newCases = new List<Case>{ firstCase, null, thirdCase };

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.BEFORE,
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'New Case must not be null. inputIndex=1',
            actualException.getMessage(),
            'The List-contained null message and inputIndex must match.'
        );
        Assert.areEqual('Low', firstCase.Priority, 'The Case before null must not be modified.');
        Assert.areEqual('Medium', thirdCase.Priority, 'The Case after null must not be modified.');
        assertNoErrors(firstCase, 'The Case before null must not have errors.');
        assertNoErrors(thirdCase, 'The Case after null must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_caseWithoutId_throwsIllegalArgumentException() {
        Account accountRecord = insertTestAccount('Before Missing Id');
        Case caseWithoutId = buildTestCase(accountRecord.Id, 'Escalated', 'Low');
        List<Case> newCases = new List<Case>{ caseWithoutId };
        Map<Id, Case> oldCasesById = new Map<Id, Case>();

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.BEFORE,
            newCases,
            oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'New Case Id must not be null. inputIndex=0',
            actualException.getMessage(),
            'The missing new Case Id message must match the contract.'
        );
        Assert.areEqual('Low', caseWithoutId.Priority, 'Priority must remain unchanged.');
        assertNoErrors(caseWithoutId, 'The Case without Id must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_oldMapMissingCaseId_throwsIllegalArgumentException() {
        Account accountRecord = insertTestAccount('Before Missing Map Key');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated' }
        );
        inputs.oldCasesById.clear();

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.BEFORE,
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'Old Case map does not contain the new Case Id. inputIndex=0, caseId='
                + inputs.newCases[0].Id,
            actualException.getMessage(),
            'The missing old Map key message must contain the actual Case Id.'
        );
        Assert.areEqual('Low', inputs.newCases[0].Priority, 'Priority must remain unchanged.');
        assertNoErrors(inputs.newCases[0], 'The new Case must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void validateAndSetPriorityForEscalations_oldMapContainingNullValue_throwsIllegalArgumentException() {
        Account accountRecord = insertTestAccount('Before Null Map Value');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated' }
        );
        Id caseId = inputs.newCases[0].Id;
        inputs.oldCasesById.put(caseId, null);

        Assert.isTrue(
            inputs.oldCasesById.containsKey(caseId),
            'The old Map must contain the key before invoking the service.'
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.BEFORE,
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'Old Case must not be null. inputIndex=0, caseId=' + caseId,
            actualException.getMessage(),
            'The null old Case message must contain the actual Case Id.'
        );
        Assert.areEqual('Low', inputs.newCases[0].Priority, 'Priority must remain unchanged.');
        assertNoErrors(inputs.newCases[0], 'The new Case must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    // ============================================================
    // After business behavior
    // ============================================================

    @IsTest
    static void createReviewTasksForEscalations_singleTransition_createsReviewTask() {
        Account accountRecord = insertTestAccount('After Single');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated' }
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.createReviewTasksForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertNoErrors(inputs.newCases[0], 'The valid target Case must not have errors.');
        assertDmlIncrease(1, 1, beforeCall, afterCall);

        List<Task> reviewTasks = queryReviewTasks(new Set<Id>{ inputs.newCases[0].Id });
        Assert.areEqual(1, reviewTasks.size(), 'Exactly one review Task must be saved.');
        assertReviewTask(reviewTasks[0], inputs.newCases[0]);
    }

    @IsTest
    static void createReviewTasksForEscalations_twoHundredTransitions_createsAllTasksInOneDml() {
        Account accountRecord = insertTestAccount('After 200');
        List<Case> casesToInsert = new List<Case>();
        List<String> newStatuses = new List<String>();
        for (Integer inputIndex = 0; inputIndex < 200; inputIndex++) {
            casesToInsert.add(buildTestCase(accountRecord.Id, 'New', 'Low'));
            newStatuses.add('Escalated');
        }
        List<Case> persistedCases = insertTestCases(casesToInsert);
        CaseUpdateInputs inputs = createUpdateInputs(persistedCases, newStatuses);

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.createReviewTasksForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(1, 200, beforeCall, afterCall);
        Set<Id> caseIds = new Map<Id, Case>(persistedCases).keySet();
        List<Task> reviewTasks = queryReviewTasks(caseIds);
        Assert.areEqual(200, reviewTasks.size(), 'All 200 review Tasks must be saved.');

        Map<Id, List<Task>> tasksByWhatId = new Map<Id, List<Task>>();
        for (Task taskRecord : reviewTasks) {
            if (!tasksByWhatId.containsKey(taskRecord.WhatId)) {
                tasksByWhatId.put(taskRecord.WhatId, new List<Task>());
            }
            tasksByWhatId.get(taskRecord.WhatId).add(taskRecord);
        }

        Assert.areEqual(200, tasksByWhatId.size(), 'The Task Map must have one key per Case.');
        for (Case caseRecord : inputs.newCases) {
            Assert.isTrue(
                tasksByWhatId.containsKey(caseRecord.Id),
                'Each Case must have a review Task. caseId=' + caseRecord.Id
            );
            Assert.areEqual(
                1,
                tasksByWhatId.get(caseRecord.Id).size(),
                'Each Case must have exactly one review Task. caseId=' + caseRecord.Id
            );
            assertReviewTask(tasksByWhatId.get(caseRecord.Id)[0], caseRecord);
            assertNoErrors(caseRecord, 'A valid target Case must not have errors.');
        }
    }

    @IsTest
    static void createReviewTasksForEscalations_nonTargetTransitions_doesNotCreateTasks() {
        Account accountRecord = insertTestAccount('After Non Target');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(null, 'New', 'Low'),
            buildTestCase(null, 'Escalated', 'Medium'),
            buildTestCase(accountRecord.Id, 'Escalated', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Working', 'Escalated', 'Working' }
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.createReviewTasksForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        for (Case caseRecord : inputs.newCases) {
            assertNoErrors(
                caseRecord,
                'A non-target Case must not be AccountId-validated or receive errors.'
            );
        }
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void createReviewTasksForEscalations_missingAccount_addsErrorWithoutDml() {
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(null, 'New', 'Low')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated' }
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.createReviewTasksForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertMissingAccountError(inputs.newCases[0]);
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void createReviewTasksForEscalations_validAndMissingAccounts_createsTasksForValidCases() {
        Account accountRecord = insertTestAccount('After Mixed');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low'),
            buildTestCase(null, 'Working', 'Medium')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated', 'Escalated' }
        );

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.createReviewTasksForEscalations(
            inputs.newCases,
            inputs.oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertNoErrors(inputs.newCases[0], 'The valid target Case must not have errors.');
        assertMissingAccountError(inputs.newCases[1]);
        assertDmlIncrease(1, 1, beforeCall, afterCall);

        List<Task> reviewTasks = queryReviewTasks(
            new Set<Id>{ inputs.newCases[0].Id, inputs.newCases[1].Id }
        );
        Assert.areEqual(1, reviewTasks.size(), 'Only the valid Case must receive a review Task.');
        assertReviewTask(reviewTasks[0], inputs.newCases[0]);
    }

    @IsTest
    static void createReviewTasksForEscalations_taskInsertFailure_rollsBackAllTasks() {
        Account accountRecord = insertTestAccount('After Task Failure');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low'),
            buildTestCase(accountRecord.Id, 'Working', 'Medium')
        });
        CaseUpdateInputs inputs = createUpdateInputs(
            persistedCases,
            new List<String>{ 'Escalated', 'Escalated' }
        );
        inputs.newCases[1].OwnerId = accountRecord.Id;
        DmlException actualException;

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        try {
            CaseEscalationService.createReviewTasksForEscalations(
                inputs.newCases,
                inputs.oldCasesById
            );
        } catch (DmlException exceptionValue) {
            actualException = exceptionValue;
        } catch (Exception exceptionValue) {
            Assert.fail('Unexpected exception type: ' + exceptionValue.getTypeName());
        }
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.isNotNull(actualException, 'Task insert failure must throw DmlException.');
        Assert.areEqual(1, actualException.getNumDml(), 'Exactly one Task row must report a DML error.');
        Assert.areEqual(1, actualException.getDmlIndex(0), 'The invalid Task must be at inputIndex=1.');
        Assert.areEqual(
            System.StatusCode.FIELD_INTEGRITY_EXCEPTION,
            actualException.getDmlType(0),
            'The provisional API 67.0 StatusCode must be FIELD_INTEGRITY_EXCEPTION.'
        );
        Assert.isNull(actualException.getDmlId(0), 'The failed Task must not have an Id.');

        List<String> fieldNames = actualException.getDmlFieldNames(0);
        Assert.isNotNull(fieldNames, 'DmlException field names must not be null.');
        Assert.areEqual(1, fieldNames.size(), 'Exactly one field must cause the Task failure.');
        Assert.areEqual('OwnerId', fieldNames[0], 'OwnerId must be the failing field.');

        String dmlMessage = actualException.getDmlMessage(0);
        Assert.isTrue(String.isNotBlank(dmlMessage), 'The Task DML message must not be blank.');
        Assert.isTrue(
            dmlMessage.contains(String.valueOf(accountRecord.Id)),
            'The Task DML message must contain the invalid Account Id.'
        );

        assertNoErrors(inputs.newCases[0], 'The first Case must not receive an input error.');
        assertNoErrors(inputs.newCases[1], 'The second Case must not receive an input error.');
        assertDmlIncrease(1, 2, beforeCall, afterCall);
        Assert.areEqual(
            0,
            queryReviewTasks(new Map<Id, Case>(persistedCases).keySet()).size(),
            'allOrNothing=true must roll back every generated Task.'
        );
    }

    // ============================================================
    // After representative structural input validation
    // ============================================================

    @IsTest
    static void createReviewTasksForEscalations_nullNewCases_throwsIllegalArgumentException() {
        Account accountRecord = insertTestAccount('After Null New');
        List<Case> persistedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'New', 'Low')
        });
        Case oldCase = persistedCases[0].clone(true, false, false, false);
        Map<Id, Case> oldCasesById = new Map<Id, Case>{ oldCase.Id => oldCase };

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.AFTER,
            null,
            oldCasesById
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'New Case list must not be null.',
            actualException.getMessage(),
            'The null new List message must match the contract.'
        );
        Assert.areEqual('Low', oldCase.Priority, 'The old Case Priority must remain unchanged.');
        assertNoErrors(oldCase, 'The old Case must not have errors.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void createReviewTasksForEscalations_nullOldCasesById_throwsIllegalArgumentException() {
        List<Case> newCases = new List<Case>();

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        IllegalArgumentException actualException = expectIllegalArgumentException(
            ServiceOperation.AFTER,
            newCases,
            null
        );
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(
            'Old Case map must not be null.',
            actualException.getMessage(),
            'The old Map null check must run before the empty List return.'
        );
        Assert.areEqual(0, newCases.size(), 'The empty input List must remain empty.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    @IsTest
    static void createReviewTasksForEscalations_emptyNewCases_returnsWithoutDml() {
        List<Case> newCases = new List<Case>();
        Map<Id, Case> oldCasesById = new Map<Id, Case>();

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        CaseEscalationService.createReviewTasksForEscalations(newCases, oldCasesById);
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(0, newCases.size(), 'The empty input List must remain empty.');
        Assert.areEqual(0, oldCasesById.size(), 'The empty old Map must remain empty.');
        assertDmlIncrease(0, 0, beforeCall, afterCall);
        assertNoReviewTasks();
    }

    // ============================================================
    // Test support
    // ============================================================

    private static Account insertTestAccount(String suffix) {
        Account accountRecord = new Account(Name = 'CP4 Service Test ' + suffix);
        insert accountRecord;
        return accountRecord;
    }

    private static Case buildTestCase(Id accountId, String status, String priority) {
        return new Case(
            Subject = 'CP4 Service Test Case',
            Origin = 'Phone',
            Status = status,
            Priority = priority,
            Description = PREPARATION_DESCRIPTION,
            AccountId = accountId,
            OwnerId = UserInfo.getUserId()
        );
    }

    private static List<Case> insertTestCases(List<Case> caseRecords) {
        insert caseRecords;
        return caseRecords;
    }

    private static CaseUpdateInputs createUpdateInputs(
        List<Case> persistedCases,
        List<String> newStatuses
    ) {
        Assert.areEqual(
            persistedCases.size(),
            newStatuses.size(),
            'Test setup requires one new Status per persisted Case.'
        );

        CaseUpdateInputs inputs = new CaseUpdateInputs();
        for (Integer inputIndex = 0; inputIndex < persistedCases.size(); inputIndex++) {
            Case oldCase = persistedCases[inputIndex].clone(true, false, false, false);
            Case newCase = persistedCases[inputIndex].clone(true, false, false, false);
            newCase.Status = newStatuses[inputIndex];

            inputs.newCases.add(newCase);
            inputs.oldCasesById.put(oldCase.Id, oldCase);
        }
        return inputs;
    }

    private static IllegalArgumentException expectIllegalArgumentException(
        ServiceOperation operation,
        List<Case> newCases,
        Map<Id, Case> oldCasesById
    ) {
        try {
            if (operation == ServiceOperation.BEFORE) {
                CaseEscalationService.validateAndSetPriorityForEscalations(
                    newCases,
                    oldCasesById
                );
            } else {
                CaseEscalationService.createReviewTasksForEscalations(
                    newCases,
                    oldCasesById
                );
            }
        } catch (IllegalArgumentException exceptionValue) {
            return exceptionValue;
        } catch (Exception exceptionValue) {
            Assert.fail('Unexpected exception type: ' + exceptionValue.getTypeName());
        }

        Assert.fail('Expected IllegalArgumentException was not thrown.');
        return null;
    }

    private static void assertNoErrors(Case caseRecord, String message) {
        Assert.isFalse(caseRecord.hasErrors(), message);
        Assert.areEqual(0, caseRecord.getErrors().size(), message);
    }

    private static void assertMissingAccountError(Case caseRecord) {
        Assert.isTrue(caseRecord.hasErrors(), 'The Case must have an AccountId validation error.');
        List<Database.Error> errors = caseRecord.getErrors();
        Assert.areEqual(1, errors.size(), 'Exactly one AccountId validation error is expected.');

        Database.Error error = errors[0];
        Assert.areEqual(
            System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
            error.getStatusCode(),
            'addError() must produce FIELD_CUSTOM_VALIDATION_EXCEPTION.'
        );
        Assert.areEqual(
            MISSING_ACCOUNT_MESSAGE,
            error.getMessage(),
            'The AccountId validation message must match the contract.'
        );
        Assert.isNotNull(error.getFields(), 'The error fields List must not be null.');
        Assert.areEqual(0, error.getFields().size(), 'The AccountId addError() fields List must be empty.');
    }

    private static void assertReviewTask(Task taskRecord, Case expectedCase) {
        Assert.areEqual(expectedCase.Id, taskRecord.WhatId, 'Task.WhatId must be the Case Id.');
        Assert.areEqual(expectedCase.OwnerId, taskRecord.OwnerId, 'Task.OwnerId must be the Case OwnerId.');
        Assert.areEqual(REVIEW_TASK_SUBJECT, taskRecord.Subject, 'Task.Subject must match the contract.');
    }

    private static List<Task> queryReviewTasks(Set<Id> caseIds) {
        return [
            SELECT Id, WhatId, OwnerId, Subject
            FROM Task
            WHERE Subject = :REVIEW_TASK_SUBJECT
                AND WhatId IN :caseIds
        ];
    }

    private static void assertNoReviewTasks() {
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Task WHERE Subject = :REVIEW_TASK_SUBJECT],
            'No review Tasks must be saved.'
        );
    }

    private static void assertDmlIncrease(
        Integer expectedStatements,
        Integer expectedRows,
        DmlSnapshot beforeCall,
        DmlSnapshot afterCall
    ) {
        Assert.areEqual(
            expectedStatements,
            afterCall.statements - beforeCall.statements,
            'Unexpected DML statement increase.'
        );
        Assert.areEqual(
            expectedRows,
            afterCall.rows - beforeCall.rows,
            'Unexpected DML row increase.'
        );
    }

    private class CaseUpdateInputs {
        public List<Case> newCases = new List<Case>();
        public Map<Id, Case> oldCasesById = new Map<Id, Case>();
    }

    private class DmlSnapshot {
        public Integer statements;
        public Integer rows;

        public DmlSnapshot() {
            statements = Limits.getDmlStatements();
            rows = Limits.getDmlRows();
        }
    }
}
