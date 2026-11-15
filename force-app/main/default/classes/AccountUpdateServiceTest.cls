@IsTest
private class AccountUpdateServiceTest {
    private static final String PHONE_EXCEEDING_MAX_LENGTH =
        '12345678901234567890123456789012345678901';

    @TestSetup
    static void setupUsers(){
    User userWithoutAccountUpdateAccess =
        TestDataFactory.createMinimumAccessUser(
            'noAccUpd',
            'UserWithoutAccountUpdateAccess',
            null
        );

    TestDataFactory.assignPermissionSets(
        userWithoutAccountUpdateAccess,
        new Set<String>{ 'Account_Query_Basic' }
    );

    User userWithoutPhoneEditAccess =
        TestDataFactory.createMinimumAccessUser(
            'noPhEdit',
            'UserWithoutPhoneEditAccess',
            null
        );

    TestDataFactory.assignPermissionSets(
        userWithoutPhoneEditAccess,
        new Set<String>{ 'Account_Update_Without_Phone' }
    );

    User userWithPhoneEditAccess =
        TestDataFactory.createMinimumAccessUser(
            'phEdit',
            'UserWithPhoneEditAccess',
            null
        );

    TestDataFactory.assignPermissionSets(
        userWithPhoneEditAccess,
        new Set<String>{ 'Account_Update_Safe' }
    );
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withValidAccounts_returnsSuccessResults() {

        User userWithPhoneEditAccess = [
            SELECT Id
            FROM User
            WHERE LastName = 'UserWithPhoneEditAccess'
            LIMIT 1
        ];

        Account storedAccount = new Account(
            Name = 'Account A',
            Phone = '03-1111-1111',
            OwnerId = userWithPhoneEditAccess.Id
        );
        insert storedAccount;

        List<Account> updateCandidates = new List<Account>{
            new Account(
                Id = storedAccount.Id,
                Phone = '03-2222-2222'
            )
        };

        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;

        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(userWithPhoneEditAccess){
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }


        Assert.isNotNull(response, '更新結果のResponseが返される必要があります。');
        Assert.isNotNull(
            response.removedFields,
            'removedFieldsは常に非nullである必要があります。'
        );
        Assert.isNotNull(
            response.results,
            'resultsは常に非nullである必要があります。'
        );
        Assert.areEqual(
            0,
            response.removedFields.size(),
            '更新権限のある項目はremovedFieldsへ追加されない想定です。'
        );
        Assert.areEqual(
            1,
            response.results.size(),
            '入力Accountごとに結果が1件返される必要があります。'
        );

        AccountUpdateService.AccountUpdateItemResult itemResult = response.results[0];

        Assert.isNotNull(itemResult, 'inputIndex=0に対応する結果が必要です。');
        Assert.isNotNull(
            itemResult.errors,
            '成功結果でもerrorsは常に非nullである必要があります。'
        );
        Assert.areEqual(0, itemResult.inputIndex, '元入力indexが一致しません。');
        Assert.areEqual(
            updateCandidates[0].Id,
            itemResult.accountId,
            '結果のAccount Idが元入力のAccount Idと一致しません。'
        );
        Assert.isTrue(itemResult.success, '有効なAccountの更新は成功する必要があります。');
        Assert.areEqual(0, itemResult.errors.size(), '成功結果にDMLエラーが含まれています。');
        Assert.areEqual(1, dmlStatementsDifference, 'Account更新のDML文数は1回である必要があります。');
        Assert.areEqual(1, dmlRowsDifference, 'Account更新のDML行数は入力1件分である必要があります。');

        Account actualAccount = [
            SELECT Name, Phone
            FROM Account
            WHERE Id = :storedAccount.Id
        ];

        Assert.areEqual('Account A', actualAccount.Name, '更新対象外のNameが変更されています。');
        Assert.areEqual('03-2222-2222', actualAccount.Phone, 'PhoneがDB上で更新されていません。');
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withMultipleAccounts_preservesResultOrder() {
        User userWithPhoneEditAccess = [
            SELECT Id
            FROM User
            WHERE LastName = 'UserWithPhoneEditAccess'
            LIMIT 1
        ];

        List<Account> storedAccounts = new List<Account>{
            new Account(Name = 'Account C', Phone = '03-1111-1111' ,OwnerId = userWithPhoneEditAccess.Id),
            new Account(Name = 'Account A', Phone = '01-1111-1111' ,OwnerId = userWithPhoneEditAccess.Id),
            new Account(Name = 'Account B', Phone = '02-1111-1111' ,OwnerId = userWithPhoneEditAccess.Id)
        };
        insert storedAccounts;

        List<Account> updateCandidates = new List<Account>{
            new Account(
                Id = storedAccounts[0].Id,
                Phone = '03-2222-2222'
            ),
            new Account(
                Id = storedAccounts[1].Id,
                Phone = '01-2222-2222'
            ),
            new Account(
                Id = storedAccounts[2].Id,
                Phone = '02-2222-2222'
            )
        };

        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;

        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(userWithPhoneEditAccess){
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        Assert.areEqual(3, response.results.size());
        for (Integer index = 0; index < updateCandidates.size(); index++) {
            AccountUpdateService.AccountUpdateItemResult result =
                response.results[index];

            Assert.areEqual(index, result.inputIndex);
            Assert.areEqual(updateCandidates[index].Id, result.accountId);
            Assert.isTrue(result.success);
            Assert.isNotNull(result.errors);
            Assert.areEqual(0, result.errors.size());
        }

        Assert.areEqual(1, dmlStatementsDifference, 'DML文数は1回である必要があります。');
        Assert.areEqual(3, dmlRowsDifference, 'DML行数は入力3件分である必要があります。');

        Map<Id, Account> actualAccountsById = queryAccountsByIds(
            getAccountIds(storedAccounts)
        );
        for (Integer index = 0; index < updateCandidates.size(); index++) {
            Assert.areEqual(
                updateCandidates[index].Phone,
                actualAccountsById.get(updateCandidates[index].Id).Phone,
                '入力順に対応するPhoneが更新されていません。inputIndex=' + index
            );
        }
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withTwoHundredAccounts_updatesAllAccounts() {
        User userWithPhoneEditAccess = [
            SELECT Id
            FROM User
            WHERE LastName = 'UserWithPhoneEditAccess'
            LIMIT 1
        ];

        List<Account> storedAccounts = new List<Account>();

        for(Integer index = 0 ; index < 200 ; index ++){
            String sequenceNumber = String.valueOf(index).leftPad(3, '0');

            storedAccounts.add(new Account(
                Name = 'Account ' + sequenceNumber,
                Phone = '01-1111-' + sequenceNumber,
                OwnerId = userWithPhoneEditAccess.Id
            ));
        }
        insert storedAccounts;

        List<Account> updateCandidates = new List<Account>();
        for( Integer index = 0 ; index < 200 ; index++ ){
            String sequenceNumber = String.valueOf(index).leftPad(3, '0');
            updateCandidates.add(
                new Account (
                    Id = storedAccounts[index].Id,
                    Phone = '01-2222-' + sequenceNumber
                )
            );
        }

        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;

        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(userWithPhoneEditAccess){
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        Assert.areEqual(200, response.results.size());
        for (Integer index = 0; index < updateCandidates.size(); index++) {
            AccountUpdateService.AccountUpdateItemResult result =
                response.results[index];

            Assert.areEqual(index, result.inputIndex);
            Assert.areEqual(updateCandidates[index].Id, result.accountId);
            Assert.isTrue(result.success);
            Assert.isNotNull(result.errors);
            Assert.areEqual(0, result.errors.size());
        }

        Assert.areEqual(1, dmlStatementsDifference, '200件でもDML文数は1回である必要があります。');
        Assert.areEqual(200, dmlRowsDifference, 'DML行数は200件である必要があります。');

        Map<Id, Account> actualAccountsById = queryAccountsByIds(
            getAccountIds(storedAccounts)
        );
        Assert.areEqual(200, actualAccountsById.size(), 'DB上の更新対象件数が一致しません。');
        for (Integer index = 0; index < updateCandidates.size(); index++) {
            Assert.areEqual(
                updateCandidates[index].Phone,
                actualAccountsById.get(updateCandidates[index].Id).Phone,
                'Phoneが更新されていません。inputIndex=' + index
            );
        }

    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withValidAccounts_usesOneDmlStatement() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> storedAccounts = buildStoredAccounts(3, updateUser.Id, 'Limits Account ');
        insert storedAccounts;
        List<Account> updateCandidates = buildPhoneUpdateCandidates(
            storedAccounts,
            '09-2222-'
        );
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        Assert.areEqual(1, dmlStatementsDifference, '複数Accountを1回のDML文で更新する必要があります。');
        Assert.areEqual(3, dmlRowsDifference, 'DML行数は入力Account件数と一致する必要があります。');
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_doesNotModifyInputListOrAccounts() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> storedAccounts = new List<Account>{
            new Account(
                Name = 'Immutable Account A',
                Phone = '03-1111-1111',
                AccountNumber = 'OLD-A',
                OwnerId = updateUser.Id
            ),
            new Account(
                Name = 'Immutable Account B',
                Phone = '06-1111-1111',
                AccountNumber = 'OLD-B',
                OwnerId = updateUser.Id
            )
        };
        insert storedAccounts;
        List<Account> updateCandidates = new List<Account>{
            new Account(
                Id = storedAccounts[0].Id,
                Phone = '03-2222-2222',
                AccountNumber = 'NEW-A'
            ),
            new Account(
                Id = storedAccounts[1].Id,
                Phone = '06-2222-2222',
                AccountNumber = 'NEW-B'
            )
        };
        List<Account> originalOrder = updateCandidates.clone();
        List<Account> accountSnapshots = new List<Account>();
        for (Account candidate : updateCandidates) {
            accountSnapshots.add(candidate.clone(true, false, false, false));
        }
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            Test.stopTest();
        }

        Assert.areEqual(originalOrder.size(), updateCandidates.size(), '入力Listの件数を変更してはいけません。');
        for (Integer index = 0; index < updateCandidates.size(); index++) {
            Assert.isTrue(
                originalOrder[index] === updateCandidates[index],
                '入力Listの要素参照または順序が変更されています。inputIndex=' + index
            );
            Assert.areEqual(accountSnapshots[index].Id, updateCandidates[index].Id, '入力AccountのIdが変更されています。inputIndex=' + index);
            Assert.areEqual(accountSnapshots[index].Phone, updateCandidates[index].Phone, '入力AccountのPhoneが変更されています。inputIndex=' + index);
            Assert.areEqual(accountSnapshots[index].AccountNumber, updateCandidates[index].AccountNumber, '入力AccountのAccountNumberが変更されています。inputIndex=' + index);
        }
        Assert.isTrue(response.removedFields.contains('AccountNumber'), '更新不可のAccountNumberがremovedFieldsに必要です。');

        Map<Id, Account> actualAccountsById = queryAccountsByIds(getAccountIds(storedAccounts));
        for (Integer index = 0; index < storedAccounts.size(); index++) {
            Account actualAccount = actualAccountsById.get(storedAccounts[index].Id);
            Assert.areEqual(updateCandidates[index].Phone, actualAccount.Phone, '更新可能なPhoneがDB上で更新されていません。inputIndex=' + index);
            Assert.areEqual(storedAccounts[index].AccountNumber, actualAccount.AccountNumber, '更新不可のAccountNumberがDB上で変更されています。inputIndex=' + index);
        }
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withNullInput_throwsIllegalArgumentException() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                response = AccountUpdateService.updateAccountsWithUpdatableFields(null);
                Assert.fail('null入力ではIllegalArgumentExceptionが必要です。');
            } catch (IllegalArgumentException exceptionRecord) {
                Assert.areEqual(
                    'Account update candidate list must not be null.',
                    exceptionRecord.getMessage(),
                    'null入力の例外メッセージが一致しません。'
                );
            }
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        Assert.isNull(response, '例外時にResponseを返してはいけません。');
        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withEmptyList_returnsEmptyResponseWithoutDml() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> updateCandidates = new List<Account>();
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertResponseCollections(response, 0, 0);
        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_containingNull_throwsIllegalArgumentException() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        Account storedAccount = new Account(
            Name = 'Null Element Account',
            Phone = '03-1111-1111',
            OwnerId = updateUser.Id
        );
        insert storedAccount;
        List<Account> updateCandidates = new List<Account>{
            new Account(Id = storedAccount.Id, Phone = '03-2222-2222'),
            null
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
                Assert.fail('List内nullではIllegalArgumentExceptionが必要です。');
            } catch (IllegalArgumentException exceptionRecord) {
                Assert.areEqual(
                    'Account update candidate must not be null. inputIndex=1',
                    exceptionRecord.getMessage(),
                    'List内nullの例外メッセージが一致しません。'
                );
            }
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
        Assert.areEqual(
            '03-1111-1111',
            queryAccountsByIds(new Set<Id>{ storedAccount.Id }).get(storedAccount.Id).Phone,
            '構造例外時に有効Accountを更新してはいけません。'
        );
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_containingAccountWithoutId_throwsIllegalArgumentException() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> updateCandidates = new List<Account>{
            new Account(Phone = '03-2222-2222')
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
                Assert.fail('IdなしAccountではIllegalArgumentExceptionが必要です。');
            } catch (IllegalArgumentException exceptionRecord) {
                Assert.areEqual(
                    'Account.Id must not be null for update operations. inputIndex=0',
                    exceptionRecord.getMessage(),
                    'IdなしAccountの例外メッセージが一致しません。'
                );
            }
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
    }

    @IsTest
    static void assigningNonAccountIdToAccount_throwsTypeExceptionBeforeService() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                Account invalidCandidate = new Account(
                    Id = updateUser.Id,
                    Phone = '03-2222-2222'
                );
                Assert.fail('Account.Idへ異種Idを設定した時点でTypeExceptionが必要です。');
            } catch (System.TypeException exceptionRecord) {
                Assert.isTrue(
                    exceptionRecord.getMessage().contains(
                        'Invalid id value for this SObject type'
                    ),
                    '異種Id拒否を示すTypeExceptionメッセージが必要です。'
                );
            }
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_containingDuplicateId_throwsIllegalArgumentException() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> storedAccounts = buildStoredAccounts(2, updateUser.Id, 'Duplicate Account ');
        insert storedAccounts;
        List<Account> updateCandidates = new List<Account>{
            new Account(Id = storedAccounts[0].Id, Phone = '03-2222-0000'),
            new Account(Id = storedAccounts[1].Id, Phone = '03-2222-0001'),
            new Account(Id = storedAccounts[0].Id, Phone = '03-3333-0000')
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
                Assert.fail('重複IdではIllegalArgumentExceptionが必要です。');
            } catch (IllegalArgumentException exceptionRecord) {
                Assert.areEqual(
                    'Duplicate Account.Id is not allowed. firstInputIndex=0, duplicateInputIndex=2',
                    exceptionRecord.getMessage(),
                    '重複Idの例外メッセージが一致しません。'
                );
            }
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
        Map<Id, Account> actualAccountsById = queryAccountsByIds(getAccountIds(storedAccounts));
        for (Integer index = 0; index < storedAccounts.size(); index++) {
            Assert.areEqual(
                storedAccounts[index].Phone,
                actualAccountsById.get(storedAccounts[index].Id).Phone,
                '重複Idの構造例外時にDBを変更してはいけません。inputIndex=' + index
            );
        }
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withInaccessibleField_removesFieldAndUpdatesAccessibleFields() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        Account storedAccount = new Account(
            Name = 'FLS Account',
            Phone = '03-1111-1111',
            AccountNumber = 'OLD-001',
            OwnerId = updateUser.Id
        );
        insert storedAccount;
        List<Account> updateCandidates = new List<Account>{
            new Account(
                Id = storedAccount.Id,
                Phone = '03-2222-2222',
                AccountNumber = 'NEW-001'
            )
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertResponseCollections(response, 1, 1);
        Assert.isTrue(
            response.removedFields.contains('AccountNumber'),
            'FLSで除去されたAccountNumberを返す必要があります。'
        );
        assertSuccessfulResult(response.results[0], 0, storedAccount.Id);
        Assert.areEqual(1, dmlStatementsDifference, 'DML文数が一致しません。');
        Assert.areEqual(1, dmlRowsDifference, 'DML行数が一致しません。');

        Account actualAccount = queryAccountsByIds(
            new Set<Id>{ storedAccount.Id }
        ).get(storedAccount.Id);
        Assert.areEqual('03-2222-2222', actualAccount.Phone, '更新可能なPhoneがDB上で更新されていません。');
        Assert.areEqual('OLD-001', actualAccount.AccountNumber, '更新不可のAccountNumberをDB上で変更してはいけません。');
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withRemovedFields_returnsAggregateRemovedFields() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> storedAccounts = new List<Account>{
            new Account(
                Name = 'Aggregate Account A',
                Phone = '03-1111-1111',
                AccountNumber = 'OLD-A',
                AnnualRevenue = 1000,
                OwnerId = updateUser.Id
            ),
            new Account(
                Name = 'Aggregate Account B',
                Phone = '06-1111-1111',
                AccountNumber = 'OLD-B',
                AnnualRevenue = 2000,
                OwnerId = updateUser.Id
            )
        };
        insert storedAccounts;
        List<Account> updateCandidates = new List<Account>{
            new Account(
                Id = storedAccounts[0].Id,
                Phone = '03-2222-2222',
                AccountNumber = 'NEW-A'
            ),
            new Account(
                Id = storedAccounts[1].Id,
                Phone = '06-2222-2222',
                AnnualRevenue = 9999
            )
        };
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            Test.stopTest();
        }

        assertResponseCollections(response, 2, 2);
        Assert.isTrue(response.removedFields.contains('AccountNumber'), 'removedFieldsにAccountNumberが必要です。');
        Assert.isTrue(response.removedFields.contains('AnnualRevenue'), 'removedFieldsにAnnualRevenueが必要です。');
        Assert.isFalse(response.removedFields.contains('Phone'), '更新可能なPhoneをremovedFieldsへ含めてはいけません。');
        for (Integer index = 0; index < updateCandidates.size(); index++) {
            assertSuccessfulResult(response.results[index], index, updateCandidates[index].Id);
        }

        Map<Id, Account> actualAccountsById = queryAccountsByIds(getAccountIds(storedAccounts));
        Assert.areEqual('03-2222-2222', actualAccountsById.get(storedAccounts[0].Id).Phone, 'Account AのPhoneが更新されていません。');
        Assert.areEqual('OLD-A', actualAccountsById.get(storedAccounts[0].Id).AccountNumber, 'Account AのAccountNumberを変更してはいけません。');
        Assert.areEqual('06-2222-2222', actualAccountsById.get(storedAccounts[1].Id).Phone, 'Account BのPhoneが更新されていません。');
        Assert.areEqual(2000, actualAccountsById.get(storedAccounts[1].Id).AnnualRevenue, 'Account BのAnnualRevenueを変更してはいけません。');
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withoutAccountUpdatePermission_throwsNoAccessException() {
        User updateUser = getUserByLastName('UserWithoutAccountUpdateAccess');
        Account storedAccount = new Account(
            Name = 'CRUD Account',
            Phone = '03-1111-1111',
            OwnerId = updateUser.Id
        );
        insert storedAccount;
        List<Account> updateCandidates = new List<Account>{
            new Account(Id = storedAccount.Id, Phone = '03-2222-2222')
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            try {
                response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
                Assert.fail('Account更新権限不足ではNoAccessExceptionが必要です。');
            } catch (System.NoAccessException exceptionRecord) {
                Assert.isTrue(
                    String.isNotBlank(exceptionRecord.getMessage()),
                    'NoAccessExceptionにメッセージが必要です。'
                );
            }
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        Assert.isNull(response, 'CRUD不足時にResponseを返してはいけません。');
        assertNoDml(dmlStatementsDifference, dmlRowsDifference);
        Assert.areEqual(
            '03-1111-1111',
            queryAccountsByIds(new Set<Id>{ storedAccount.Id }).get(storedAccount.Id).Phone,
            'CRUD不足時にDBを変更してはいけません。'
        );
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_withValidAndInvalidAccounts_returnsPartialResults() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        List<Account> storedAccounts = new List<Account>{
            new Account(
                Name = 'Valid Account',
                Phone = '03-1111-1111',
                OwnerId = updateUser.Id
            ),
            new Account(
                Name = 'Invalid Account',
                Phone = '06-1111-1111',
                OwnerId = updateUser.Id
            )
        };
        insert storedAccounts;
        List<Account> updateCandidates = new List<Account>{
            new Account(Id = storedAccounts[0].Id, Phone = '03-2222-2222'),
            new Account(Id = storedAccounts[1].Id, Phone = PHONE_EXCEEDING_MAX_LENGTH)
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertResponseCollections(response, 0, 2);
        assertSuccessfulResult(response.results[0], 0, storedAccounts[0].Id);
        assertFailedResult(response.results[1], 1, storedAccounts[1].Id);
        Assert.areEqual(1, dmlStatementsDifference, 'DML文数が一致しません。');
        Assert.areEqual(2, dmlRowsDifference, '失敗レコードもDML行数へ含める必要があります。');

        Map<Id, Account> actualAccountsById = queryAccountsByIds(getAccountIds(storedAccounts));
        Assert.areEqual('03-2222-2222', actualAccountsById.get(storedAccounts[0].Id).Phone, '正常AccountのPhoneが更新されていません。');
        Assert.areEqual('06-1111-1111', actualAccountsById.get(storedAccounts[1].Id).Phone, '失敗AccountのPhoneを更新してはいけません。');
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_whenFieldLengthExceedsLimit_returnsDmlErrors() {
        User updateUser = getUserByLastName('UserWithPhoneEditAccess');
        Account storedAccount = new Account(
            Name = 'DML Error Account',
            Phone = '03-1111-1111',
            OwnerId = updateUser.Id
        );
        insert storedAccount;
        List<Account> updateCandidates = new List<Account>{
            new Account(Id = storedAccount.Id, Phone = PHONE_EXCEEDING_MAX_LENGTH)
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(updateUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertResponseCollections(response, 0, 1);
        assertFailedResult(response.results[0], 0, storedAccount.Id);
        Assert.areEqual(1, response.results[0].errors.size(), '文字数超過ではエラー1件を期待します。');
        AccountUpdateService.AccountUpdateError actualError = response.results[0].errors[0];
        Assert.areEqual(System.StatusCode.STRING_TOO_LONG, actualError.statusCode, '文字数超過のStatusCodeが一致しません。');
        Assert.isTrue(actualError.fields.contains('Phone'), '文字数超過エラーのfieldsにPhoneが必要です。');
        Assert.isTrue(String.isNotBlank(actualError.message), 'DMLエラーのmessageが必要です。');
        Assert.areEqual(1, dmlStatementsDifference, 'DML文数が一致しません。');
        Assert.areEqual(1, dmlRowsDifference, 'DML行数が一致しません。');
        Assert.areEqual(
            '03-1111-1111',
            queryAccountsByIds(new Set<Id>{ storedAccount.Id }).get(storedAccount.Id).Phone,
            'DML失敗時にPhoneを変更してはいけません。'
        );
    }

    @IsTest
    static void updateAccountsWithUpdatableFields_whenRecordIsNotUpdatable_returnsFailureResult() {
        User ownerUser = getUserByLastName('UserWithoutPhoneEditAccess');
        User readerUser = getUserByLastName('UserWithPhoneEditAccess');
        Account storedAccount = new Account(
            Name = 'Unshared Account',
            Phone = '03-1111-1111',
            OwnerId = ownerUser.Id
        );
        insert storedAccount;
        List<Account> updateCandidates = new List<Account>{
            new Account(Id = storedAccount.Id, Phone = '03-2222-2222')
        };
        Integer dmlStatementsBefore;
        Integer dmlStatementsDifference;
        Integer dmlRowsBefore;
        Integer dmlRowsDifference;
        AccountUpdateService.AccountUpdateResponse response;

        System.runAs(readerUser) {
            Test.startTest();
            dmlStatementsBefore = Limits.getDmlStatements();
            dmlRowsBefore = Limits.getDmlRows();
            response = AccountUpdateService.updateAccountsWithUpdatableFields(updateCandidates);
            dmlStatementsDifference = Limits.getDmlStatements() - dmlStatementsBefore;
            dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
            Test.stopTest();
        }

        assertResponseCollections(response, 0, 1);
        assertFailedResult(response.results[0], 0, storedAccount.Id);
        Assert.areEqual(
            System.StatusCode.INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY,
            response.results[0].errors[0].statusCode,
            '共有アクセス不足のStatusCodeが一致しません。'
        );
        Assert.areEqual(1, dmlStatementsDifference, 'DML文数が一致しません。');
        Assert.areEqual(1, dmlRowsDifference, 'DML行数が一致しません。');
        Assert.areEqual(
            '03-1111-1111',
            queryAccountsByIds(new Set<Id>{ storedAccount.Id }).get(storedAccount.Id).Phone,
            '共有アクセス不足時にPhoneを変更してはいけません。'
        );
    }

    private static User getUserByLastName(String lastName) {
        return [
            SELECT Id
            FROM User
            WHERE LastName = :lastName
            LIMIT 1
        ];
    }

    private static List<Account> buildStoredAccounts(
        Integer count,
        Id ownerId,
        String namePrefix
    ) {
        List<Account> storedAccounts = new List<Account>();
        for (Integer index = 0; index < count; index++) {
            String sequenceNumber = String.valueOf(index).leftPad(3, '0');
            storedAccounts.add(new Account(
                Name = namePrefix + sequenceNumber,
                Phone = '01-1111-' + sequenceNumber,
                OwnerId = ownerId
            ));
        }
        return storedAccounts;
    }

    private static List<Account> buildPhoneUpdateCandidates(
        List<Account> storedAccounts,
        String phonePrefix
    ) {
        List<Account> updateCandidates = new List<Account>();
        for (Integer index = 0; index < storedAccounts.size(); index++) {
            String sequenceNumber = String.valueOf(index).leftPad(3, '0');
            updateCandidates.add(new Account(
                Id = storedAccounts[index].Id,
                Phone = phonePrefix + sequenceNumber
            ));
        }
        return updateCandidates;
    }

    private static Set<Id> getAccountIds(List<Account> accounts) {
        return new Map<Id, Account>(accounts).keySet();
    }

    private static Map<Id, Account> queryAccountsByIds(Set<Id> accountIds) {
        return new Map<Id, Account>([
            SELECT Id, Name, Phone, AccountNumber, AnnualRevenue
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    private static void assertResponseCollections(
        AccountUpdateService.AccountUpdateResponse response,
        Integer expectedRemovedFieldCount,
        Integer expectedResultCount
    ) {
        Assert.isNotNull(response, '更新結果のResponseが返される必要があります。');
        Assert.isNotNull(response.removedFields, 'removedFieldsは常に非nullである必要があります。');
        Assert.isNotNull(response.results, 'resultsは常に非nullである必要があります。');
        Assert.areEqual(
            expectedRemovedFieldCount,
            response.removedFields.size(),
            'removedFieldsの件数が一致しません。'
        );
        Assert.areEqual(
            expectedResultCount,
            response.results.size(),
            '入力Accountに対応する結果件数が一致しません。'
        );
    }

    private static void assertSuccessfulResult(
        AccountUpdateService.AccountUpdateItemResult result,
        Integer expectedInputIndex,
        Id expectedAccountId
    ) {
        Assert.isNotNull(result, '入力に対応する結果が必要です。');
        Assert.isNotNull(result.errors, '成功結果でもerrorsは常に非nullである必要があります。');
        Assert.areEqual(expectedInputIndex, result.inputIndex, '元入力indexが一致しません。');
        Assert.areEqual(
            expectedAccountId,
            result.accountId,
            '結果のAccount Idが元入力と一致しません。inputIndex=' + expectedInputIndex
        );
        Assert.isTrue(
            result.success,
            '有効なAccountの更新は成功する必要があります。inputIndex=' + expectedInputIndex
        );
        Assert.areEqual(
            0,
            result.errors.size(),
            '成功結果にDMLエラーが含まれています。inputIndex=' + expectedInputIndex
        );
    }

    private static void assertFailedResult(
        AccountUpdateService.AccountUpdateItemResult result,
        Integer expectedInputIndex,
        Id expectedAccountId
    ) {
        Assert.isNotNull(result, '入力に対応する失敗結果が必要です。');
        Assert.isNotNull(result.errors, '失敗結果のerrorsは非nullである必要があります。');
        Assert.areEqual(expectedInputIndex, result.inputIndex, '失敗結果の元入力indexが一致しません。');
        Assert.areEqual(expectedAccountId, result.accountId, '失敗結果のAccount Idが元入力と一致しません。');
        Assert.isFalse(result.success, '失敗結果のsuccessはfalseである必要があります。');
        Assert.isTrue(!result.errors.isEmpty(), '失敗結果には1件以上のDMLエラーが必要です。');
    }

    private static void assertNoDml(
        Integer dmlStatementsDifference,
        Integer dmlRowsDifference
    ) {
        Assert.areEqual(0, dmlStatementsDifference, 'DML文を実行してはいけません。');
        Assert.areEqual(0, dmlRowsDifference, 'DML行を消費してはいけません。');
    }
}
