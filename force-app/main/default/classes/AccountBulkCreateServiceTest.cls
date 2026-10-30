@IsTest
private class AccountBulkCreateServiceTest {

    @IsTest
    static void createAccounts_withNullInput_throwsInputException() {
        Boolean expectedExceptionThrown = false;
        String actualMessage;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        try {
            AccountBulkCreateService.createAccounts(
                null,
                AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
            );
        } catch (AccountBulkCreateService.InvalidAccountCreateRequestException exceptionValue) {
            expectedExceptionThrown = true;
            actualMessage = exceptionValue.getMessage();
        } catch (Exception exceptionValue) {
            Assert.fail('想定外の例外が発生しました。型：' + exceptionValue.getTypeName());
        }
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isTrue(expectedExceptionThrown, '入力Listがnullの場合は独自例外を送出する必要があります。');
        Assert.areEqual(
            'Input Account list must not be null.',
            actualMessage,
            '例外メッセージが一致しません。'
        );
        assertDmlStatementIncrease(0, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(0, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    @IsTest
    static void createAccounts_withEmptyInput_returnsEmptyResults() {
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            new List<Account>(),
            AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isNotNull(results, '空入力ではnullではなく空の結果Listを返す必要があります。');
        Assert.areEqual(0, results.size(), '結果件数は0件の想定です。');
        assertDmlStatementIncrease(0, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(0, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    @IsTest
    static void createAccounts_withNullProcessingMode_throwsInputException() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Null Mode Account')
        };
        Boolean expectedExceptionThrown = false;
        String actualMessage;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        try {
            AccountBulkCreateService.createAccounts(accounts, null);
        } catch (AccountBulkCreateService.InvalidAccountCreateRequestException exceptionValue) {
            expectedExceptionThrown = true;
            actualMessage = exceptionValue.getMessage();
        } catch (Exception exceptionValue) {
            Assert.fail('想定外の例外が発生しました。型：' + exceptionValue.getTypeName());
        }
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isTrue(expectedExceptionThrown, 'ProcessingModeがnullの場合は独自例外を送出する必要があります。');
        Assert.areEqual(
            'ProcessingMode must not be null.',
            actualMessage,
            '例外メッセージが一致しません。'
        );
        assertDmlStatementIncrease(0, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(0, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    @IsTest
    static void createAccounts_allOrNoneContainingNull_rejectsEntireBatch() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'All Or None Valid A'),
            null,
            new Account(Name = 'All Or None Valid B')
        };
        Boolean expectedExceptionThrown = false;
        String actualMessage;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        try {
            AccountBulkCreateService.createAccounts(
                accounts,
                AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
            );
        } catch (AccountBulkCreateService.InvalidAccountCreateRequestException exceptionValue) {
            expectedExceptionThrown = true;
            actualMessage = exceptionValue.getMessage();
        } catch (Exception exceptionValue) {
            Assert.fail('想定外の例外が発生しました。型：' + exceptionValue.getTypeName());
        }
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isTrue(expectedExceptionThrown, 'List内nullがある場合はバッチ全体を拒否する必要があります。');
        Assert.areEqual(
            'Input Account must not be null. inputIndex=1',
            actualMessage,
            '例外メッセージとinputIndexが一致しません。'
        );
        assertDmlStatementIncrease(0, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(0, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], '有効なAccountも保存されない想定です。');
    }

    @IsTest
    static void createAccounts_partialSuccessContainingNull_insertsValidAccounts() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Partial Valid A'),
            null,
            new Account(Name = 'Partial Valid B')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(3, results.size(), '結果件数は元入力と同じ3件の想定です。');
        assertSuccessResult(results[0], 0);
        assertNullInputFailureResult(results[1], 1);
        assertSuccessResult(results[2], 2);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(2, dmlRowsBefore, dmlRowsAfter);

        Set<Id> createdIds = new Set<Id>{
            results[0].accountId,
            results[2].accountId
        };
        Map<Id, Account> savedAccountsById = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :createdIds
        ]);

        Assert.areEqual(2, savedAccountsById.size(), '有効なAccountだけ2件保存される想定です。');
        Assert.areEqual(
            'Partial Valid A',
            savedAccountsById.get(results[0].accountId).Name,
            'inputIndex=0のAccount名が一致しません。'
        );
        Assert.areEqual(
            'Partial Valid B',
            savedAccountsById.get(results[2].accountId).Name,
            'inputIndex=2のAccount名が一致しません。'
        );
    }

    @IsTest
    static void createAccounts_partialSuccessWithOnlyNulls_returnsInputFailuresWithoutDml() {
        List<Account> accounts = new List<Account>{ null, null, null };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(3, results.size(), '結果件数は元入力と同じ3件の想定です。');
        for (Integer inputIndex = 0; inputIndex < results.size(); inputIndex++) {
            assertNullInputFailureResult(results[inputIndex], inputIndex);
        }
        assertDmlStatementIncrease(0, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(0, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    @IsTest
    static void createAccounts_allOrNoneWithSingleValidAccount_succeeds() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Single All Or None')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(1, results.size(), '結果件数は1件の想定です。');
        assertSavedAccountsMatchInputs(accounts, results);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(1, dmlRowsBefore, dmlRowsAfter);
    }

    @IsTest
    static void createAccounts_partialSuccessWithSingleValidAccount_succeeds() {
        User testUser = TestDataFactory.createMinimumAccessUser();
        TestDataFactory.assignPermissionSets(
            testUser,
            new Set<String>{
                'Account_Create_Basic',
                'Account_Number_Write'
            }
        );
        List<Account> accounts = new List<Account>{
            new Account(
                Name = 'Single Partial Success',
                AccountNumber = 'PERMITTED-001'
            )
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        System.runAs(testUser) {
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            Assert.isTrue(
                Schema.sObjectType.Account.isCreateable(),
                'Account_Create_BasicによりAccount作成権限が必要です。'
            );
            Assert.isTrue(
                Schema.sObjectType.Account.fields.AccountNumber.isCreateable(),
                'Account_Number_WriteによりAccountNumber書込み権限が必要です。'
            );
            results = AccountBulkCreateService.createAccounts(
                accounts,
                AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
            );
            dmlStatementsAfter = Limits.getDmlStatements();
            dmlRowsAfter = Limits.getDmlRows();
        }
        Test.stopTest();

        Assert.areEqual(1, results.size(), '結果件数は1件の想定です。');
        assertSavedAccountsMatchInputs(accounts, results);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(1, dmlRowsBefore, dmlRowsAfter);

        Account savedAccount = [
            SELECT AccountNumber
            FROM Account
            WHERE Id = :results[0].accountId
        ];
        Assert.areEqual(
            accounts[0].AccountNumber,
            savedAccount.AccountNumber,
            'USER_MODEでAccountNumberを含むAccountが保存される想定です。'
        );
    }

    @IsTest
    static void createAccounts_withMultipleValidAccounts_succeeds() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Multiple Valid A'),
            new Account(Name = 'Multiple Valid B'),
            new Account(Name = 'Multiple Valid C')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(3, results.size(), '結果件数は3件の想定です。');
        assertSavedAccountsMatchInputs(accounts, results);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(3, dmlRowsBefore, dmlRowsAfter);
    }

    @IsTest
    static void createAccounts_withTwoHundredValidAccounts_succeeds() {
        List<Account> accounts = new List<Account>();
        for (Integer inputIndex = 0; inputIndex < 200; inputIndex++) {
            accounts.add(new Account(Name = 'Two Hundred Valid ' + inputIndex));
        }
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(200, results.size(), '結果件数は200件の想定です。');
        assertSavedAccountsMatchInputs(accounts, results);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(200, dmlRowsBefore, dmlRowsAfter);
    }

    @IsTest
    static void createAccounts_partialMixedTwoHundred_returnsOrderedResults() {
        List<Account> accounts = new List<Account>();
        for (Integer inputIndex = 0; inputIndex < 150; inputIndex++) {
            accounts.add(new Account(Name = 'Mixed Valid ' + inputIndex));
        }
        for (Integer inputIndex = 150; inputIndex < 180; inputIndex++) {
            accounts.add(null);
        }
        for (Integer inputIndex = 180; inputIndex < 200; inputIndex++) {
            accounts.add(new Account());
        }
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(200, results.size(), '結果件数は元入力と同じ200件の想定です。');

        Set<Id> createdIds = new Set<Id>();
        for (Integer inputIndex = 0; inputIndex < 150; inputIndex++) {
            assertSuccessResult(results[inputIndex], inputIndex);
            createdIds.add(results[inputIndex].accountId);
        }
        for (Integer inputIndex = 150; inputIndex < 180; inputIndex++) {
            assertNullInputFailureResult(results[inputIndex], inputIndex);
        }
        for (Integer inputIndex = 180; inputIndex < 200; inputIndex++) {
            assertMissingNameDmlFailureResult(results[inputIndex], inputIndex);
        }

        Assert.areEqual(150, createdIds.size(), '成功150件の作成Idはすべて異なる想定です。');
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(170, dmlRowsBefore, dmlRowsAfter);

        Map<Id, Account> createdAccountsById = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :createdIds
        ]);
        Assert.areEqual(150, createdAccountsById.size(), '正常Accountだけ150件保存される想定です。');
        for (Integer inputIndex = 0; inputIndex < 150; inputIndex++) {
            Assert.areEqual(
                accounts[inputIndex].Name,
                createdAccountsById.get(results[inputIndex].accountId).Name,
                '保存されたNameと元入力の対応が一致しません。inputIndex=' + inputIndex
            );
        }
    }

    @IsTest
    static void createAccounts_allOrNoneContainingMissingName_rollsBackAll() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Missing Name Valid A'),
            new Account(),
            new Account(Name = 'Missing Name Valid B')
        };
        Boolean expectedExceptionThrown = false;
        DmlException actualException;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        try {
            AccountBulkCreateService.createAccounts(
                accounts,
                AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
            );
        } catch (DmlException exceptionValue) {
            expectedExceptionThrown = true;
            actualException = exceptionValue;
        } catch (Exception exceptionValue) {
            Assert.fail('想定外の例外が発生しました。型：' + exceptionValue.getTypeName());
        }
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isTrue(expectedExceptionThrown, 'Nameなしを含む場合はDmlExceptionの想定です。');
        Assert.isNotNull(actualException, 'DmlExceptionを取得できていません。');
        Assert.areEqual(1, actualException.getNumDml(), 'DMLエラーは1件の想定です。');
        Assert.areEqual(1, actualException.getDmlIndex(0), 'NameなしはinputIndex=1です。');
        Assert.areEqual(
            'REQUIRED_FIELD_MISSING',
            actualException.getDmlStatusCode(0),
            'StatusCodeはREQUIRED_FIELD_MISSINGの想定です。'
        );
        assertMissingNameFields(actualException.getDmlFieldNames(0));
        Assert.isNull(
            actualException.getDmlId(0),
            'insertに失敗したNameなしAccountにIdは返らない想定です。'
        );
        Assert.isTrue(
            String.isNotBlank(actualException.getDmlMessage(0)),
            'DMLエラーメッセージが必要です。'
        );
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(3, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], '全3件とも保存されない想定です。');
    }

    @IsTest
    static void createAccounts_partialSuccessContainingMissingName_insertsValidAccounts() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Partial Missing Name Valid A'),
            new Account(),
            new Account(Name = 'Partial Missing Name Valid B')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(3, results.size(), '結果件数は元入力と同じ3件の想定です。');
        assertSuccessResult(results[0], 0);
        assertMissingNameDmlFailureResult(results[1], 1);
        assertSuccessResult(results[2], 2);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(3, dmlRowsBefore, dmlRowsAfter);

        Set<Id> createdIds = new Set<Id>{
            results[0].accountId,
            results[2].accountId
        };
        Map<Id, Account> savedAccountsById = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :createdIds
        ]);

        Assert.areEqual(2, savedAccountsById.size(), '有効なAccountだけ2件保存される想定です。');
        Assert.areEqual(
            accounts[0].Name,
            savedAccountsById.get(results[0].accountId).Name,
            'inputIndex=0のAccount名が一致しません。'
        );
        Assert.areEqual(
            accounts[2].Name,
            savedAccountsById.get(results[2].accountId).Name,
            'inputIndex=2のAccount名が一致しません。'
        );
    }

    @IsTest
    static void createAccounts_allOrNoneContainingExistingId_rejectsEntireBatch() {
        Account existingAccount = new Account(
            Name = 'Existing Original',
            AccountNumber = 'EXISTING-001'
        );
        insert existingAccount;

        List<Account> accounts = new List<Account>{
            new Account(Name = 'Existing Id Valid A'),
            new Account(
                Id = existingAccount.Id,
                Name = 'Existing Attempted Update',
                AccountNumber = 'CHANGED-001'
            ),
            new Account(Name = 'Existing Id Valid B')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Boolean expectedExceptionThrown = false;
        String actualMessage;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        try {
            results = AccountBulkCreateService.createAccounts(
                accounts,
                AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
            );
        } catch (AccountBulkCreateService.InvalidAccountCreateRequestException exceptionValue) {
            expectedExceptionThrown = true;
            actualMessage = exceptionValue.getMessage();
        } catch (Exception exceptionValue) {
            Assert.fail('想定外の例外が発生しました。型：' + exceptionValue.getTypeName());
        }
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isTrue(expectedExceptionThrown, 'Id付きAccountは独自例外でバッチ全体を拒否する想定です。');
        Assert.areEqual(
            'Account.Id must be null for create operations. inputIndex=1',
            actualMessage,
            '例外メッセージとinputIndexが一致しません。'
        );
        Assert.isNull(results, '例外送出時は結果Listを返さない想定です。');
        assertDmlStatementIncrease(0, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(0, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(1, [SELECT COUNT() FROM Account], '事前作成したAccount以外は保存されない想定です。');

        Account savedExistingAccount = [
            SELECT Name, AccountNumber
            FROM Account
            WHERE Id = :existingAccount.Id
        ];
        Assert.areEqual('Existing Original', savedExistingAccount.Name, '既存AccountのNameは更新されません。');
        Assert.areEqual(
            'EXISTING-001',
            savedExistingAccount.AccountNumber,
            '既存AccountのAccountNumberは更新されません。'
        );
    }

    @IsTest
    static void createAccounts_partialContainingExistingId_returnsInputFailure() {
        Account existingAccount = new Account(
            Name = 'Partial Existing Original',
            AccountNumber = 'EXISTING-002'
        );
        insert existingAccount;

        List<Account> accounts = new List<Account>{
            new Account(Name = 'Partial Existing Id Valid A'),
            new Account(
                Id = existingAccount.Id,
                Name = 'Partial Existing Attempted Update',
                AccountNumber = 'CHANGED-002'
            ),
            new Account(Name = 'Partial Existing Id Valid B')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(3, results.size(), '結果件数は元入力と同じ3件の想定です。');
        assertSuccessResult(results[0], 0);
        assertExistingIdInputFailureResult(results[1], 1);
        assertSuccessResult(results[2], 2);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(2, dmlRowsBefore, dmlRowsAfter);

        Set<Id> createdIds = new Set<Id>{
            results[0].accountId,
            results[2].accountId
        };
        Map<Id, Account> createdAccountsById = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :createdIds
        ]);
        Assert.areEqual(2, createdAccountsById.size(), '有効な新規Accountだけ2件保存される想定です。');
        Assert.areEqual(accounts[0].Name, createdAccountsById.get(results[0].accountId).Name, 'inputIndex=0のNameが一致しません。');
        Assert.areEqual(accounts[2].Name, createdAccountsById.get(results[2].accountId).Name, 'inputIndex=2のNameが一致しません。');

        Account savedExistingAccount = [
            SELECT Name, AccountNumber
            FROM Account
            WHERE Id = :existingAccount.Id
        ];
        Assert.areEqual('Partial Existing Original', savedExistingAccount.Name, '既存AccountのNameは更新されません。');
        Assert.areEqual(
            'EXISTING-002',
            savedExistingAccount.AccountNumber,
            '既存AccountのAccountNumberは更新されません。'
        );
        Assert.areEqual(3, [SELECT COUNT() FROM Account], '既存1件と新規2件の合3件の想定です。');
    }

    @IsTest
    static void createAccounts_doesNotModifyInputList() {
        Account existingAccount = new Account(Name = 'List Existing Original');
        insert existingAccount;

        Account validAccountA = new Account(Name = 'List Valid A');
        Account existingIdAccount = new Account(
            Id = existingAccount.Id,
            Name = 'List Existing Attempted Update'
        );
        Account validAccountB = new Account(Name = 'List Valid B');
        List<Account> accounts = new List<Account>{
            validAccountA,
            null,
            existingIdAccount,
            validAccountB
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.areEqual(4, accounts.size(), '入力Listの件数を変更してはいけません。');
        Assert.isTrue(accounts[0] === validAccountA, 'inputIndex=0の要素参照が変わっています。');
        Assert.isNull(accounts[1], 'inputIndex=1のnull位置を維持する必要があります。');
        Assert.isTrue(accounts[2] === existingIdAccount, 'inputIndex=2の要素参照が変わっています。');
        Assert.isTrue(accounts[3] === validAccountB, 'inputIndex=3の要素参照が変わっています。');

        Assert.areEqual(4, results.size(), '結果件数は元入力と同じ4件の想定です。');
        assertSuccessResult(results[0], 0);
        assertNullInputFailureResult(results[1], 1);
        assertExistingIdInputFailureResult(results[2], 2);
        assertSuccessResult(results[3], 3);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(2, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(3, [SELECT COUNT() FROM Account], '既存1件と新規2件の合3件の想定です。');
    }

    @IsTest
    static void createAccounts_doesNotModifyInputAccounts() {
        Account accountA = new Account(
            Name = 'Immutable Account A',
            AccountNumber = 'IMMUTABLE-001'
        );
        Account accountB = new Account(
            Name = 'Immutable Account B',
            AccountNumber = 'IMMUTABLE-002'
        );
        List<Account> accounts = new List<Account>{ accountA, accountB };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        dmlStatementsBefore = Limits.getDmlStatements();
        dmlRowsBefore = Limits.getDmlRows();
        results = AccountBulkCreateService.createAccounts(
            accounts,
            AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
        );
        dmlStatementsAfter = Limits.getDmlStatements();
        dmlRowsAfter = Limits.getDmlRows();
        Test.stopTest();

        Assert.isNull(accountA.Id, '元Account AのIdはnullのままである必要があります。');
        Assert.areEqual('Immutable Account A', accountA.Name, '元Account AのNameが変更されています。');
        Assert.areEqual('IMMUTABLE-001', accountA.AccountNumber, '元Account AのAccountNumberが変更されています。');
        Assert.isNull(accountB.Id, '元Account BのIdはnullのままである必要があります。');
        Assert.areEqual('Immutable Account B', accountB.Name, '元Account BのNameが変更されています。');
        Assert.areEqual('IMMUTABLE-002', accountB.AccountNumber, '元Account BのAccountNumberが変更されています。');

        Assert.areEqual(2, results.size(), '結果件数は2件の想定です。');
        assertSuccessResult(results[0], 0);
        assertSuccessResult(results[1], 1);
        Assert.areNotEqual(results[0].accountId, results[1].accountId, '作成Idは入力ごとに異なる想定です。');
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(2, dmlRowsBefore, dmlRowsAfter);

        Set<Id> createdIds = new Set<Id>{ results[0].accountId, results[1].accountId };
        Map<Id, Account> createdAccountsById = new Map<Id, Account>([
            SELECT Id, Name, AccountNumber
            FROM Account
            WHERE Id IN :createdIds
        ]);
        Assert.areEqual(2, createdAccountsById.size(), 'Accountは2件保存される想定です。');
        Assert.areEqual(accountA.Name, createdAccountsById.get(results[0].accountId).Name, '保存されたAccount AのNameが一致しません。');
        Assert.areEqual(accountA.AccountNumber, createdAccountsById.get(results[0].accountId).AccountNumber, '保存されたAccount AのAccountNumberが一致しません。');
        Assert.areEqual(accountB.Name, createdAccountsById.get(results[1].accountId).Name, '保存されたAccount BのNameが一致しません。');
        Assert.areEqual(accountB.AccountNumber, createdAccountsById.get(results[1].accountId).AccountNumber, '保存されたAccount BのAccountNumberが一致しません。');
    }

    @IsTest
    static void createAccounts_allOrNoneWithoutAccountCreatePermission_throwsException() {
        User testUser = TestDataFactory.createMinimumAccessUser();
        List<Account> accounts = new List<Account>{
            new Account(Name = 'No Create Permission All Or None')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Boolean expectedExceptionThrown = false;
        SecurityException actualException;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        System.runAs(testUser) {
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                Assert.isFalse(
                    Schema.sObjectType.Account.isCreateable(),
                    'テストユーザーにAccount作成権限がないことが前提です。'
                );
                results = AccountBulkCreateService.createAccounts(
                    accounts,
                    AccountBulkCreateService.ProcessingMode.ALL_OR_NONE
                );
            } catch (SecurityException exceptionValue) {
                expectedExceptionThrown = true;
                actualException = exceptionValue;
            } catch (Exception exceptionValue) {
                Assert.fail('想定外の例外が発生しました。型：' + exceptionValue.getTypeName());
            }
            dmlStatementsAfter = Limits.getDmlStatements();
            dmlRowsAfter = Limits.getDmlRows();
        }
        Test.stopTest();

        Assert.isTrue(expectedExceptionThrown, 'Account作成権限不足でSecurityExceptionを送出する想定です。');
        Assert.isNotNull(actualException, 'SecurityExceptionを取得できていません。');
        Assert.isNull(results, '例外送出時は結果Listを返さない想定です。');
        assertAccountCreatePermissionMessage(actualException.getMessage());
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(1, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    @IsTest
    static void createAccounts_partialSuccessWithoutAccountCreatePermission_returnsFailures() {
        User testUser = TestDataFactory.createMinimumAccessUser();
        List<Account> accounts = new List<Account>{
            new Account(Name = 'No Create Permission Partial A'),
            new Account(Name = 'No Create Permission Partial B')
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        System.runAs(testUser) {
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            Assert.isFalse(
                Schema.sObjectType.Account.isCreateable(),
                'テストユーザーにAccount作成権限がないことが前提です。'
            );
            results = AccountBulkCreateService.createAccounts(
                accounts,
                AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
            );
            dmlStatementsAfter = Limits.getDmlStatements();
            dmlRowsAfter = Limits.getDmlRows();
        }
        Test.stopTest();

        Assert.areEqual(2, results.size(), '結果件数は元入力と同じ2件の想定です。');
        for (Integer inputIndex = 0; inputIndex < results.size(); inputIndex++) {
            assertAccountCreatePermissionFailureResult(results[inputIndex], inputIndex);
        }
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(2, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    @IsTest
    static void createAccounts_partialWithoutAccountNumberAccess_returnsFailure() {
        User testUser = TestDataFactory.createMinimumAccessUser();
        TestDataFactory.assignPermissionSets(
            testUser,
            new Set<String>{ 'Account_Create_Basic' }
        );
        List<Account> accounts = new List<Account>{
            new Account(
                Name = 'No AccountNumber Access',
                AccountNumber = 'NO-FLS-001'
            )
        };
        List<AccountBulkCreateService.AccountCreateResult> results;
        Integer dmlStatementsBefore;
        Integer dmlStatementsAfter;
        Integer dmlRowsBefore;
        Integer dmlRowsAfter;

        Test.startTest();
        System.runAs(testUser) {
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            Assert.isTrue(
                Schema.sObjectType.Account.isCreateable(),
                'Account_Create_BasicによりAccount作成権限があることが前提です。'
            );
            Assert.isFalse(
                Schema.sObjectType.Account.fields.AccountNumber.isCreateable(),
                'AccountNumberの作成時書込み権限がないことが前提です。'
            );
            results = AccountBulkCreateService.createAccounts(
                accounts,
                AccountBulkCreateService.ProcessingMode.PARTIAL_SUCCESS
            );
            dmlStatementsAfter = Limits.getDmlStatements();
            dmlRowsAfter = Limits.getDmlRows();
        }
        Test.stopTest();

        Assert.areEqual(1, results.size(), '結果件数は1件の想定です。');
        assertAccountNumberAccessFailureResult(results[0], 0);
        assertDmlStatementIncrease(1, dmlStatementsBefore, dmlStatementsAfter);
        assertDmlRowIncrease(1, dmlRowsBefore, dmlRowsAfter);
        Assert.areEqual(0, [SELECT COUNT() FROM Account], 'Accountは保存されない想定です。');
    }

    private static void assertSuccessResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        Assert.isNotNull(result, '成功結果がnullです。inputIndex=' + expectedInputIndex);
        Assert.areEqual(expectedInputIndex, result.inputIndex, 'inputIndexが一致しません。');
        Assert.isTrue(result.success, '成功結果のsuccessはtrueの想定です。');
        Assert.isNotNull(result.accountId, '成功結果には作成Idが必要です。');
        Assert.isNotNull(result.errors, '成功結果のerrorsは空Listの想定です。');
        Assert.areEqual(0, result.errors.size(), '成功結果のerrorsは0件の想定です。');
    }

    private static void assertNullInputFailureResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        Assert.isNotNull(result, '入力失敗結果がnullです。inputIndex=' + expectedInputIndex);
        Assert.areEqual(expectedInputIndex, result.inputIndex, 'inputIndexが一致しません。');
        Assert.isFalse(result.success, '入力失敗結果のsuccessはfalseの想定です。');
        Assert.isNull(result.accountId, '入力失敗結果のaccountIdはnullの想定です。');
        Assert.isNotNull(result.errors, '入力失敗結果にはerrorsが必要です。');
        Assert.areEqual(1, result.errors.size(), 'List内nullのエラーは1件の想定です。');

        AccountBulkCreateService.AccountCreateError error = result.errors[0];
        Assert.areEqual(
            AccountBulkCreateService.AccountCreateErrorType.INPUT_VALIDATION,
            error.type,
            'エラー種別はINPUT_VALIDATIONの想定です。'
        );
        Assert.areEqual('Input Account must not be null.', error.message, 'エラーメッセージが一致しません。');
        Assert.isNull(error.statusCode, '事前検証エラーのstatusCodeはnullの想定です。');
        Assert.isNotNull(error.fields, '事前検証エラーのfieldsは空Listの想定です。');
        Assert.areEqual(0, error.fields.size(), 'List内nullのfieldsは0件の想定です。');
    }

    private static void assertSavedAccountsMatchInputs(
        List<Account> accounts,
        List<AccountBulkCreateService.AccountCreateResult> results
    ) {
        Assert.areEqual(accounts.size(), results.size(), '入力と結果の件数が一致しません。');
        Set<Id> createdIds = new Set<Id>();

        for (Integer inputIndex = 0; inputIndex < accounts.size(); inputIndex++) {
            assertSuccessResult(results[inputIndex], inputIndex);
            createdIds.add(results[inputIndex].accountId);
        }

        Assert.areEqual(accounts.size(), createdIds.size(), '作成Idは入力ごとに異なる想定です。');
        Map<Id, Account> savedAccountsById = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :createdIds
        ]);
        Assert.areEqual(accounts.size(), savedAccountsById.size(), '保存件数が入力件数と一致しません。');

        for (Integer inputIndex = 0; inputIndex < accounts.size(); inputIndex++) {
            Assert.areEqual(
                accounts[inputIndex].Name,
                savedAccountsById.get(results[inputIndex].accountId).Name,
                '保存されたNameが入力と一致しません。inputIndex=' + inputIndex
            );
        }
    }

    private static void assertMissingNameDmlFailureResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        Assert.isNotNull(result, 'DML失敗結果がnullです。');
        Assert.areEqual(expectedInputIndex, result.inputIndex, 'inputIndexが一致しません。');
        Assert.isFalse(result.success, 'DML失敗結果のsuccessはfalseの想定です。');
        Assert.isNull(result.accountId, 'DML失敗結果のaccountIdはnullの想定です。');
        Assert.isNotNull(result.errors, 'DML失敗結果にはerrorsが必要です。');
        Assert.areEqual(1, result.errors.size(), 'NameなしのDMLエラーは1件の想定です。');

        AccountBulkCreateService.AccountCreateError error = result.errors[0];
        Assert.areEqual(
            AccountBulkCreateService.AccountCreateErrorType.DML,
            error.type,
            'エラー種別はDMLの想定です。'
        );
        Assert.areEqual(
            System.StatusCode.REQUIRED_FIELD_MISSING,
            error.statusCode,
            'StatusCodeはREQUIRED_FIELD_MISSINGの想定です。'
        );
        assertMissingNameFields(error.fields);
        Assert.isTrue(String.isNotBlank(error.message), 'DMLエラーメッセージが必要です。');
    }

    private static void assertMissingNameFields(List<String> fields) {
        Assert.isNotNull(fields, 'fieldsがnullです。');
        Assert.areEqual(1, fields.size(), 'Nameなしのfieldsは1件の想定です。');
        Assert.areEqual('Name', fields[0], 'fieldsにNameが入る想定です。');
    }

    private static void assertExistingIdInputFailureResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        Assert.isNotNull(result, 'Id付きAccountの失敗結果がnullです。');
        Assert.areEqual(expectedInputIndex, result.inputIndex, 'inputIndexが一致しません。');
        Assert.isFalse(result.success, 'Id付きAccountのsuccessはfalseの想定です。');
        Assert.isNull(result.accountId, 'Id付きAccountのaccountIdはnullの想定です。');
        Assert.isNotNull(result.errors, 'Id付きAccountにはerrorsが必要です。');
        Assert.areEqual(1, result.errors.size(), 'Id付きAccountのエラーは1件の想定です。');

        AccountBulkCreateService.AccountCreateError error = result.errors[0];
        Assert.areEqual(
            AccountBulkCreateService.AccountCreateErrorType.INPUT_VALIDATION,
            error.type,
            'エラー種別はINPUT_VALIDATIONの想定です。'
        );
        Assert.areEqual(
            'Account.Id must be null for create operations.',
            error.message,
            'エラーメッセージが一致しません。'
        );
        Assert.isNull(error.statusCode, '事前検証エラーのstatusCodeはnullの想定です。');
        Assert.isNotNull(error.fields, '事前検証エラーにはfieldsが必要です。');
        Assert.areEqual(1, error.fields.size(), 'Id付きAccountのfieldsは1件の想定です。');
        Assert.areEqual('Id', error.fields[0], 'fieldsにIdが入る想定です。');
    }

    private static void assertAccountCreatePermissionFailureResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        AccountBulkCreateService.AccountCreateError error =
            assertSingleDmlFailureResult(result, expectedInputIndex);
        Assert.areEqual(
            System.StatusCode.CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY,
            error.statusCode,
            'API 67.0のAccount作成権限不足はCANNOT_INSERT_UPDATE_ACTIVATE_ENTITYの想定です。'
        );
        assertEmptyFields(error.fields);
        assertAccountCreatePermissionMessage(error.message);
    }

    private static void assertAccountNumberAccessFailureResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        AccountBulkCreateService.AccountCreateError error =
            assertSingleDmlFailureResult(result, expectedInputIndex);
        Assert.areEqual(
            System.StatusCode.CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY,
            error.statusCode,
            'API 67.0のAccountNumber FLS不足はCANNOT_INSERT_UPDATE_ACTIVATE_ENTITYの想定です。'
        );
        Assert.isNotNull(error.fields, 'FLSエラーにはfieldsが必要です。');
        Assert.areEqual(1, error.fields.size(), 'FLSエラーのfieldsは1件の想定です。');
        Assert.areEqual('AccountNumber', error.fields[0], 'fieldsにAccountNumberが入る想定です。');
    }

    private static AccountBulkCreateService.AccountCreateError assertSingleDmlFailureResult(
        AccountBulkCreateService.AccountCreateResult result,
        Integer expectedInputIndex
    ) {
        Assert.isNotNull(result, 'DML失敗結果がnullです。inputIndex=' + expectedInputIndex);
        Assert.areEqual(expectedInputIndex, result.inputIndex, 'inputIndexが一致しません。');
        Assert.isFalse(result.success, 'DML失敗結果のsuccessはfalseの想定です。');
        Assert.isNull(result.accountId, 'DML失敗結果のaccountIdはnullの想定です。');
        Assert.isNotNull(result.errors, 'DML失敗結果にはerrorsが必要です。');
        Assert.areEqual(1, result.errors.size(), '権限不足のDMLエラーは1件の想定です。');

        AccountBulkCreateService.AccountCreateError error = result.errors[0];
        Assert.areEqual(
            AccountBulkCreateService.AccountCreateErrorType.DML,
            error.type,
            'エラー種別はDMLの想定です。'
        );
        Assert.isTrue(String.isNotBlank(error.message), 'Salesforce生成のDMLエラーメッセージが必要です。');
        return error;
    }

    private static void assertEmptyFields(List<String> fields) {
        Assert.isNotNull(fields, 'fieldsはnullではなく空Listの想定です。');
        Assert.areEqual(0, fields.size(), 'fieldsは0件の想定です。');
    }

    private static void assertAccountCreatePermissionMessage(String message) {
        Assert.isTrue(String.isNotBlank(message), '権限不足メッセージが必要です。');
        String normalizedMessage = message.toLowerCase();
        Assert.isTrue(
            normalizedMessage.contains('account'),
            '権限不足メッセージはAccountを示す必要があります。'
        );
        Assert.isTrue(
            normalizedMessage.contains('denied') ||
            normalizedMessage.contains('permission') ||
            normalizedMessage.contains('insufficient'),
            '権限不足メッセージはアクセス拒否を示す必要があります。'
        );
    }

    private static void assertDmlStatementIncrease(
        Integer expectedIncrease,
        Integer beforeValue,
        Integer afterValue
    ) {
        Assert.areEqual(
            expectedIncrease,
            afterValue - beforeValue,
            'DML文の増加数が一致しません。'
        );
    }

    private static void assertDmlRowIncrease(
        Integer expectedIncrease,
        Integer beforeValue,
        Integer afterValue
    ) {
        Assert.areEqual(
            expectedIncrease,
            afterValue - beforeValue,
            'DML行の増加数が一致しません。'
        );
    }
}
