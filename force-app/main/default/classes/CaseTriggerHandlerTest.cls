@IsTest
private class CaseTriggerHandlerTest {

    private static final String REVIEW_TASK_SUBJECT = 'Review escalated case';
    private static final String MISSING_ACCOUNT_MESSAGE =
        'AccountId is required when changing Status to Escalated.';
    private static final String TEST_DESCRIPTION = 'Test Description';
    private static final String FLOW_UPDATED_DESCRIPTION = 'Flow Updated';
    private static final String HANDLER_NAME = 'CaseTriggerHandler';

    @IsTest
    private static void update_nonEscalatedToEscalated_setsPriorityAndCreatesTask() {
        Account accountRecord = insertTestAccount('Single Escalation');
        Case caseRecord = buildTestCase(
            accountRecord.Id,
            'Single Escalation Test',
            TEST_DESCRIPTION
        );
        List<Case> insertedCases = insertTestCases(new List<Case>{ caseRecord });
        Case insertedCase = insertedCases[0];
        insertedCase.Status = 'Escalated';

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        update insertedCase;
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(2, 2, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        List<Task> reviewTasks = queryReviewTasksByCaseIds(
            new Set<Id>{ insertedCase.Id }
        );

        Assert.areEqual('Escalated', actualCase.Status, 'Status must be Escalated.');
        Assert.areEqual('High', actualCase.Priority, 'Priority must be changed to High.');
        Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
        Assert.areEqual(accountRecord.Id, actualCase.AccountId, 'AccountId must remain unchanged.');
        Assert.areEqual(UserInfo.getUserId(), actualCase.OwnerId, 'OwnerId must remain unchanged.');
        Assert.areEqual(1, reviewTasks.size(), 'Exactly one review Task must be created.');
        assertReviewTask(reviewTasks[0], actualCase);
    }

    @IsTest
    private static void update_twoHundredCasesToEscalated_processesAllRecords() {
        Account accountRecord = insertTestAccount('Bulk 200');
        List<Case> caseRecords = new List<Case>();

        for (Integer caseIndex = 0; caseIndex < 200; caseIndex++) {
            caseRecords.add(
                buildTestCase(
                    accountRecord.Id,
                    'Bulk Escalation Test ' + caseIndex,
                    TEST_DESCRIPTION
                )
            );
        }

        List<Case> insertedCases = insertTestCases(caseRecords);
        Set<Id> caseIds = collectCaseIds(insertedCases);
        for (Case caseRecord : insertedCases) {
            caseRecord.Status = 'Escalated';
        }

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        update insertedCases;
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(2, 400, beforeCall, afterCall);

        Map<Id, Case> actualCasesById = queryCasesByIds(caseIds);
        List<Task> reviewTasks = queryReviewTasksByCaseIds(caseIds);
        Map<Id, List<Task>> tasksByCaseId = groupTasksByWhatId(reviewTasks);

        Assert.areEqual(200, actualCasesById.size(), 'All 200 Cases must be saved.');
        Assert.areEqual(200, reviewTasks.size(), 'Exactly 200 review Tasks must be saved.');
        Assert.areEqual(200, tasksByCaseId.size(), 'Every Case must have a Task group.');

        for (Case inputCase : insertedCases) {
            Assert.isTrue(
                actualCasesById.containsKey(inputCase.Id),
                'The updated Case must exist. caseId=' + inputCase.Id
            );

            Case actualCase = actualCasesById.get(inputCase.Id);
            Assert.areEqual('Escalated', actualCase.Status, 'Status must be Escalated.');
            Assert.areEqual('High', actualCase.Priority, 'Priority must be High.');
            Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
            Assert.areEqual(accountRecord.Id, actualCase.AccountId, 'AccountId must remain unchanged.');
            Assert.areEqual(UserInfo.getUserId(), actualCase.OwnerId, 'OwnerId must remain unchanged.');

            Assert.isTrue(
                tasksByCaseId.containsKey(inputCase.Id),
                'Each Case must have a review Task. caseId=' + inputCase.Id
            );
            Assert.areEqual(
                1,
                tasksByCaseId.get(inputCase.Id).size(),
                'Each Case must have exactly one review Task. caseId=' + inputCase.Id
            );
            assertReviewTask(tasksByCaseId.get(inputCase.Id)[0], actualCase);
        }
    }

    @IsTest
    private static void update_toEscalatedWithoutAccount_failsWithAddError() {
        Case caseRecord = buildTestCase(
            null,
            'Missing Account Test',
            TEST_DESCRIPTION
        );
        Case insertedCase = insertTestCases(new List<Case>{ caseRecord })[0];
        insertedCase.Status = 'Escalated';
        DmlException actualException;

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        try {
            update insertedCase;
        } catch (DmlException exceptionValue) {
            actualException = exceptionValue;
        } catch (Exception exceptionValue) {
            Assert.fail('Unexpected exception type: ' + exceptionValue.getTypeName());
        }
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.isNotNull(actualException, 'The Case update must throw DmlException.');
        Assert.areEqual(1, actualException.getNumDml(), 'Exactly one Case must fail.');
        Assert.areEqual(0, actualException.getDmlIndex(0), 'The failed Case must be at inputIndex=0.');
        Assert.areEqual(
            System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
            actualException.getDmlType(0),
            'The addError StatusCode must match.'
        );
        Assert.areEqual(
            MISSING_ACCOUNT_MESSAGE,
            actualException.getDmlMessage(0),
            'The addError message must match the contract.'
        );
        assertDmlIncrease(1, 1, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        Assert.areEqual('New', actualCase.Status, 'The failed Case Status must be rolled back.');
        Assert.areEqual('Low', actualCase.Priority, 'The failed Case Priority must remain Low.');
        Assert.areEqual(
            0,
            queryReviewTasksByCaseIds(new Set<Id>{ insertedCase.Id }).size(),
            'No Task must be created for the failed Case.'
        );
    }

    @IsTest
    private static void update_validAndInvalidCasesWithPartialSuccess_savesOnlyValidCase() {
        Account accountRecord = insertTestAccount('Partial Success');
        List<Case> insertedCases = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'Partial Valid Test', TEST_DESCRIPTION),
            buildTestCase(null, 'Partial Invalid Test', TEST_DESCRIPTION)
        });
        for (Case caseRecord : insertedCases) {
            caseRecord.Status = 'Escalated';
        }

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        Database.SaveResult[] saveResults = Database.update(insertedCases, false);
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.areEqual(2, saveResults.size(), 'One SaveResult is required per input Case.');
        Assert.isTrue(saveResults[0].isSuccess(), 'The valid Case must succeed.');
        Assert.areEqual(insertedCases[0].Id, saveResults[0].getId(), 'The valid Case Id must be returned.');
        Assert.areEqual(0, saveResults[0].getErrors().size(), 'The valid Case must have no errors.');

        Assert.isFalse(saveResults[1].isSuccess(), 'The Case without AccountId must fail.');
        Assert.areEqual(
            insertedCases[1].Id,
            saveResults[1].getId(),
            'A failed update must still identify the existing Case Id.'
        );
        Assert.areEqual(1, saveResults[1].getErrors().size(), 'Exactly one validation error is expected.');
        Assert.areEqual(
            System.StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
            saveResults[1].getErrors()[0].getStatusCode(),
            'The failed Case StatusCode must match.'
        );
        Assert.areEqual(
            MISSING_ACCOUNT_MESSAGE,
            saveResults[1].getErrors()[0].getMessage(),
            'The failed Case message must match the contract.'
        );
        assertDmlIncrease(2, 3, beforeCall, afterCall);

        Set<Id> caseIds = collectCaseIds(insertedCases);
        Map<Id, Case> actualCasesById = queryCasesByIds(caseIds);
        Assert.areEqual('Escalated', actualCasesById.get(insertedCases[0].Id).Status, 'The valid Case must be saved.');
        Assert.areEqual('High', actualCasesById.get(insertedCases[0].Id).Priority, 'The valid Case must become High.');
        Assert.areEqual('New', actualCasesById.get(insertedCases[1].Id).Status, 'The invalid Case must remain New.');
        Assert.areEqual('Low', actualCasesById.get(insertedCases[1].Id).Priority, 'The invalid Case must remain Low.');

        List<Task> reviewTasks = queryReviewTasksByCaseIds(caseIds);
        Assert.areEqual(1, reviewTasks.size(), 'Only the valid Case must receive a Task.');
        assertReviewTask(reviewTasks[0], actualCasesById.get(insertedCases[0].Id));
    }

    @IsTest
    private static void update_nonTargetStatusTransition_doesNotRunEscalationProcessing() {
        Account accountRecord = insertTestAccount('Non Target');
        Case insertedCase = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'Non Target Transition Test', TEST_DESCRIPTION)
        })[0];
        insertedCase.Status = 'Working';

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        update insertedCase;
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(1, 1, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        Assert.areEqual('Working', actualCase.Status, 'The requested non-target Status must be saved.');
        Assert.areEqual('Low', actualCase.Priority, 'A non-target Case must remain Low.');
        Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
        Assert.areEqual(
            0,
            queryReviewTasksByCaseIds(new Set<Id>{ insertedCase.Id }).size(),
            'A non-target transition must not create a Task.'
        );
    }

    @IsTest
    private static void update_alreadyEscalatedCase_doesNotCreateAnotherTask() {
        Account accountRecord = insertTestAccount('Already Escalated');
        Case caseRecord = buildTestCase(
            accountRecord.Id,
            'Already Escalated Test',
            TEST_DESCRIPTION
        );
        caseRecord.Status = 'Escalated';
        Case insertedCase = insertTestCases(new List<Case>{ caseRecord })[0];
        insertedCase.Subject = 'Already Escalated Test Updated';

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        update insertedCase;
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(1, 1, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        Assert.areEqual('Escalated', actualCase.Status, 'Status must remain Escalated.');
        Assert.areEqual('Low', actualCase.Priority, 'Priority must not be corrected without a transition.');
        Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
        Assert.areEqual('Already Escalated Test Updated', actualCase.Subject, 'The requested Subject must be saved.');
        Assert.areEqual(
            0,
            queryReviewTasksByCaseIds(new Set<Id>{ insertedCase.Id }).size(),
            'Updating an already Escalated Case must not create a Task.'
        );
    }

    @IsTest
    private static void insert_withEscalatedStatus_doesNotRunUpdateProcessing() {
        Account accountRecord = insertTestAccount('Escalated Insert');
        Case caseRecord = buildTestCase(
            accountRecord.Id,
            'Escalated Insert Test',
            TEST_DESCRIPTION
        );
        caseRecord.Status = 'Escalated';

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        insert caseRecord;
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(1, 1, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ caseRecord.Id }
        ).get(caseRecord.Id);
        Assert.areEqual('Escalated', actualCase.Status, 'The inserted Status must be Escalated.');
        Assert.areEqual('Low', actualCase.Priority, 'Insert must not run before update correction.');
        Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
        Assert.areEqual(
            0,
            queryReviewTasksByCaseIds(new Set<Id>{ caseRecord.Id }).size(),
            'Insert must not run after update Task creation.'
        );
    }

    @IsTest
    private static void update_withFlowReentry_createsOnlyOneTask() {
        Account accountRecord = insertTestAccount('Flow Reentry');
        Case insertedCase = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'Flow Reentry Test', null)
        })[0];
        insertedCase.Status = 'Escalated';

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        update insertedCase;
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        assertDmlIncrease(3, 3, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        List<Task> reviewTasks = queryReviewTasksByCaseIds(
            new Set<Id>{ insertedCase.Id }
        );

        Assert.areEqual('Escalated', actualCase.Status, 'Status must be Escalated.');
        Assert.areEqual('High', actualCase.Priority, 'Priority must be changed to High.');
        Assert.areEqual(
            FLOW_UPDATED_DESCRIPTION,
            actualCase.Description,
            'The final Description must prove that the Flow executed.'
        );
        Assert.areEqual(1, reviewTasks.size(), 'Trigger reentry must not create a duplicate Task.');
        assertReviewTask(reviewTasks[0], actualCase);
    }

    @IsTest
    private static void update_whenTaskInsertFails_rollsBackCaseAndTasks() {
        Account accountRecord = insertTestAccount('Task Failure Rollback');
        Case caseRecord = buildTestCase(
            accountRecord.Id,
            'Task Failure Rollback Test',
            TEST_DESCRIPTION
        );
        Case insertedCase = insertTestCases(new List<Case>{ caseRecord })[0];
        insertedCase.Status = 'Escalated';
        DmlException actualException;

        Test.startTest();
        DmlSnapshot beforeCall = new DmlSnapshot();
        try {
            CaseEscalationService.reviewTaskOwnerIdOverride = accountRecord.Id;
            update insertedCase;
        } catch (DmlException exceptionValue) {
            actualException = exceptionValue;
        } finally {
            CaseEscalationService.reviewTaskOwnerIdOverride = null;
        }
        DmlSnapshot afterCall = new DmlSnapshot();
        Test.stopTest();

        Assert.isNotNull(actualException, 'The outer Case update must throw DmlException.');
        Assert.areEqual(1, actualException.getNumDml(), 'Exactly one Case update must fail.');
        Assert.areEqual(0, actualException.getDmlIndex(0), 'The failed Case must be at inputIndex=0.');
        Assert.areEqual(
            System.StatusCode.CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY,
            actualException.getDmlType(0),
            'The outer DML StatusCode must identify Trigger failure.'
        );
        Assert.areEqual(
            String.valueOf(insertedCase.Id),
            actualException.getDmlId(0),
            'The outer exception must identify the failed Case.'
        );

        String dmlMessage = actualException.getDmlMessage(0);
        String lowerMessage = dmlMessage.toLowerCase();
        Assert.isTrue(String.isNotBlank(dmlMessage), 'The outer DML message must not be blank.');
        Assert.isTrue(lowerMessage.contains('casetrigger'), 'The message must identify CaseTrigger.');
        Assert.isTrue(
            lowerMessage.contains('afterupdate') || lowerMessage.contains('after update'),
            'The message must identify the after update failure.'
        );
        Assert.isTrue(
            lowerMessage.contains('field_integrity_exception'),
            'The message must include the measured internal Task StatusCode.'
        );
        Assert.isTrue(
            dmlMessage.contains(String.valueOf(accountRecord.Id)),
            'The message must identify the invalid Task OwnerId.'
        );
        assertDmlIncrease(1, 1, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        Assert.areEqual('New', actualCase.Status, 'The Case Status must be rolled back.');
        Assert.areEqual('Low', actualCase.Priority, 'The Case Priority must be rolled back.');
        Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
        Assert.areEqual(
            0,
            queryReviewTasksByCaseIds(new Set<Id>{ insertedCase.Id }).size(),
            'The failed Task insert must leave no review Tasks.'
        );
    }

    @IsTest
    private static void update_whenHandlerBypassed_skipsProcessingAndClearsBypass() {
        Account accountRecord = insertTestAccount('Handler Bypass');
        Case insertedCase = insertTestCases(new List<Case>{
            buildTestCase(accountRecord.Id, 'Handler Bypass Test', TEST_DESCRIPTION)
        })[0];
        insertedCase.Status = 'Escalated';
        DmlSnapshot beforeCall;
        DmlSnapshot afterCall;

        Test.startTest();
        try {
            TriggerHandler.bypass(HANDLER_NAME);
            Assert.isTrue(
                TriggerHandler.isBypassed(HANDLER_NAME),
                'CaseTriggerHandler must be bypassed before the update.'
            );
            beforeCall = new DmlSnapshot();
            update insertedCase;
            afterCall = new DmlSnapshot();
        } finally {
            TriggerHandler.clearBypass(HANDLER_NAME);
        }
        Test.stopTest();

        Assert.isFalse(
            TriggerHandler.isBypassed(HANDLER_NAME),
            'The Handler bypass must always be cleared.'
        );
        assertDmlIncrease(1, 1, beforeCall, afterCall);

        Case actualCase = queryCasesByIds(
            new Set<Id>{ insertedCase.Id }
        ).get(insertedCase.Id);
        Assert.areEqual('Escalated', actualCase.Status, 'The requested Status must still be saved.');
        Assert.areEqual('Low', actualCase.Priority, 'Bypass must skip Priority correction.');
        Assert.areEqual(TEST_DESCRIPTION, actualCase.Description, 'Description must remain unchanged.');
        Assert.areEqual(
            0,
            queryReviewTasksByCaseIds(new Set<Id>{ insertedCase.Id }).size(),
            'Bypass must skip Task creation.'
        );
    }

    private static Account insertTestAccount(String nameSuffix) {
        Account accountRecord = new Account(
            Name = 'CP4 Handler Test ' + nameSuffix
        );
        insert accountRecord;
        return accountRecord;
    }

    private static Case buildTestCase(
        Id accountId,
        String subject,
        String description
    ) {
        return new Case(
            AccountId = accountId,
            Subject = subject,
            Origin = 'Phone',
            Status = 'New',
            Priority = 'Low',
            Description = description,
            OwnerId = UserInfo.getUserId()
        );
    }

    private static List<Case> insertTestCases(List<Case> caseRecords) {
        insert caseRecords;
        return caseRecords;
    }

    private static Set<Id> collectCaseIds(List<Case> caseRecords) {
        Set<Id> caseIds = new Set<Id>();
        for (Case caseRecord : caseRecords) {
            caseIds.add(caseRecord.Id);
        }
        return caseIds;
    }

    private static Map<Id, Case> queryCasesByIds(Set<Id> caseIds) {
        return new Map<Id, Case>([
            SELECT Id, Subject, Status, Priority, Description, AccountId, OwnerId
            FROM Case
            WHERE Id IN :caseIds
        ]);
    }

    private static List<Task> queryReviewTasksByCaseIds(Set<Id> caseIds) {
        return [
            SELECT Id, WhatId, OwnerId, Subject
            FROM Task
            WHERE WhatId IN :caseIds
                AND Subject = :REVIEW_TASK_SUBJECT
        ];
    }

    private static Map<Id, List<Task>> groupTasksByWhatId(List<Task> taskRecords) {
        Map<Id, List<Task>> tasksByWhatId = new Map<Id, List<Task>>();
        for (Task taskRecord : taskRecords) {
            if (!tasksByWhatId.containsKey(taskRecord.WhatId)) {
                tasksByWhatId.put(taskRecord.WhatId, new List<Task>());
            }
            tasksByWhatId.get(taskRecord.WhatId).add(taskRecord);
        }
        return tasksByWhatId;
    }

    private static void assertReviewTask(Task taskRecord, Case expectedCase) {
        Assert.areEqual(expectedCase.Id, taskRecord.WhatId, 'Task.WhatId must be the Case Id.');
        Assert.areEqual(expectedCase.OwnerId, taskRecord.OwnerId, 'Task.OwnerId must match the Case OwnerId.');
        Assert.areEqual(REVIEW_TASK_SUBJECT, taskRecord.Subject, 'Task.Subject must match the contract.');
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

    private class DmlSnapshot {
        public Integer statements;
        public Integer rows;

        public DmlSnapshot() {
            statements = Limits.getDmlStatements();
            rows = Limits.getDmlRows();
        }
    }
}
