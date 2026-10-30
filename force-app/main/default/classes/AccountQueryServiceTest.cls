@IsTest
private class AccountQueryServiceTest {
    @TestSetup
    static void setupUsersAndPermissions(){
        User ownerUser = TestDataFactory.createMinimumAccessUser('accown','AccountOwnerUser',null);
        User readerUser = TestDataFactory.createMinimumAccessUser('accread','AccountReaderUser',null);
        User noCrudUser = TestDataFactory.createMinimumAccessUser('accnocrd','AccountNoCrudUser',null);
        User withoutNumberUser = TestDataFactory.createMinimumAccessUser('accnonum','AccountWithoutNumberUser',null);

        TestDataFactory.assignPermissionSets(readerUser,new Set<String>{ 'Account_Query_Basic' });
        TestDataFactory.assignPermissionSets(withoutNumberUser,new Set<String>{ 'Account_Query_Without_Number' });
    }

    @IsTest
    static void findReadableAccountsByIds_withMultipleAccounts_returnsInDeterministicOrder(){
        List<Account> insertedAccounts = new List<Account>{
            new Account(Name = 'Account A', AccountNumber = 'B-001'),
            new Account(Name = 'Account B', AccountNumber = 'A-001'),
            new Account(Name = 'Account C', AccountNumber = null),
            new Account(Name = 'Account D', AccountNumber = 'A-001'),
            new Account(Name = 'Account E', AccountNumber = 'A-002')
        };

        insert insertedAccounts;

        List<Id> expectedA001Ids = new List<Id>{
            insertedAccounts[1].Id,
            insertedAccounts[3].Id
        };
        expectedA001Ids.sort();

        List<Id> expectedIds = new List<Id>();
        expectedIds.addAll(expectedA001Ids);
        expectedIds.add(insertedAccounts[4].Id);
        expectedIds.add(insertedAccounts[0].Id);
        expectedIds.add(insertedAccounts[2].Id);

        Set<Id> accountIds = new Set<Id>();
        for(Account accountRecord : insertedAccounts){
            accountIds.add(accountRecord.Id);
        }

        Test.startTest();
        List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);
        Test.stopTest();

        Assert.isNotNull(result,'検索結果はnullではなくListとして返される必要があります。');
        Assert.areEqual(expectedIds.size(), result.size(),'SOQLの取得件数が一致しません。取得件数：' + result.size());

        Map<Id,Account> insertedAccountsById = new Map<Id,Account>(insertedAccounts);
        List<Account> expectedAccounts = new List<Account>();
        for(Id expectedId : expectedIds){
            expectedAccounts.add(insertedAccountsById.get(expectedId));
        }

        for(Integer index = 0; index < result.size(); index++){
            Account expectedAccount = expectedAccounts[index];
            Account actualAccount = result[index];

            Assert.areEqual(
                expectedAccount.Id,
                actualAccount.Id,
                'AccountのIdと取得順が期待値と一致しません。resultIndex=' + index
            );
            Assert.areEqual(
                expectedAccount.Name,
                actualAccount.Name,
                'AccountのNameが期待値と一致しません。resultIndex=' + index
            );
            Assert.areEqual(
                expectedAccount.AccountNumber,
                actualAccount.AccountNumber,
                'AccountNumberが期待値と一致しません。resultIndex=' + index
            );
        }

    }

    @IsTest
    static void findReadableAccountsByIds_withNullInput_throwsIllegalArgumentException(){

        Boolean exceptionThrown = false;

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        try {
            List<Account> result = AccountQueryService.findReadableAccountsByIds(null);
            Assert.fail('IllegalArgumentExceptionが送出される必要があります。');
        } catch (IllegalArgumentException exceptionRecord){
            exceptionThrown = true;

            Assert.areEqual('Account ID set must not be null.', exceptionRecord.getMessage(), '例外メッセージが一致しません。');
        }
        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.isTrue(exceptionThrown,'IllegalArgumentExceptionが送出される必要があります。');
        Assert.areEqual(0, queryDifference,'入力検証エラーの場合、SOQLを実行してはいけません。');
    }

    @IsTest
    static void findReadableAccountsByIds_withEmptySet_returnsEmptyListWithoutQuery(){
        Set<Id> accountIds = new Set<Id>();
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();

        List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);

        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.isNotNull(result,'空Setの場合も、nullではなく空Listを返す必要があります。');
        Assert.areEqual(0, result.size(),'空Setの場合、検索結果は0件である必要があります。');
        Assert.areEqual(0, queryDifference,'空Setの場合、SOQLを実行してはいけません。');
    }

    @IsTest
    static void findReadableAccountsByIds_containingNull_throwsIllegalArgumentException(){
        Account insertedAccount = new Account(Name = 'Account A', AccountNumber = 'A-001');
        insert insertedAccount;

        Set<Id> accountIds = new Set<Id>{
            insertedAccount.Id,
            null
        };
        Boolean exceptionThrown = false;

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        try {
            List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);
            Assert.fail('IllegalArgumentExceptionが送出される必要があります。');
        } catch (IllegalArgumentException exceptionRecord){
            exceptionThrown = true;

            Assert.areEqual('Account ID set must not contain null.', exceptionRecord.getMessage(), '例外メッセージが一致しません。');
        }
        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.isTrue(exceptionThrown,'IllegalArgumentExceptionが送出される必要があります。');
        Assert.areEqual(0, queryDifference,'入力検証エラーの場合、SOQLを実行してはいけません。');
    }

    @IsTest
    static void findReadableAccountsByIds_containingNonAccountId_throwsIllegalArgumentException(){
        Contact insertedContact = new Contact(LastName = 'Test Contact');
        insert insertedContact;

        Set<Id> accountIds = new Set<Id>{
            insertedContact.Id
        };

        Boolean exceptionThrown = false;

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        try {
            List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);
            Assert.fail('IllegalArgumentExceptionが送出される必要があります。');
        } catch (IllegalArgumentException exceptionRecord){
            exceptionThrown = true;

            Assert.areEqual('Account ID set must contain only Account IDs.', exceptionRecord.getMessage(), '例外メッセージが一致しません。');
        }
        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.isTrue(exceptionThrown,'IllegalArgumentExceptionが送出される必要があります。');
        Assert.areEqual(0, queryDifference,'入力検証エラーの場合、SOQLを実行してはいけません。');
    }

    @IsTest
    static void findReadableAccountsByIds_withOnlyNonexistentId_returnsEmptyList(){
        Id nonexistentAccountId = '001000000000001';
        Set<Id> accountIds = new Set<Id>{ nonexistentAccountId };

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();

        List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);

        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Integer queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
        Test.stopTest();

        Assert.isNotNull(result,'存在しないAccount Idだけの場合も、nullではなく空Listを返す必要があります。');
        Assert.areEqual(0, result.size(),'存在しないAccount Idだけの場合、検索結果は0件である必要があります。');
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(0,queryRowsDifference,'SOQLの取得行数が一致しません。取得行数：' + queryRowsDifference);
    }

    @IsTest
    static void findReadableAccountsByIds_withExistingAndNonexistentIds_returnsOnlyExistingAccount(){
        Account insertedAccount = new Account(Name = 'Account A', AccountNumber = 'A-001');

        insert insertedAccount;

        Id nonexistentAccountId = '001000000000001';
        Set<Id> accountIds = new Set<Id>{ nonexistentAccountId, insertedAccount.Id };

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();

        List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);

        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Integer queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
        Test.stopTest();

        Assert.isNotNull(result,'検索結果はnullではなくListとして返される必要があります。');
        Assert.areEqual(1, result.size(),'SOQLの取得件数が一致しません。取得件数：' + result.size());
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(1,queryRowsDifference,'SOQLの取得行数が一致しません。取得行数：' + queryRowsDifference);
        Assert.areEqual(insertedAccount.Id, result[0].Id,'実在するAccountのIdが検索結果と一致しません。');

    }

    @IsTest
    static void findReadableAccountsByIds_withUnsharedAccount_omitsInvisibleAccount(){
        User ownerUser = [
            SELECT Id
            FROM User
            WHERE LastName = 'AccountOwnerUser'
            LIMIT 1
        ];

        User readerUser = [
            SELECT Id
            FROM User
            WHERE LastName = 'AccountReaderUser'
            LIMIT 1
        ];


        Account visibleAccount = new Account(Name = 'Visible Account', AccountNumber = 'A-001', OwnerId = readerUser.Id);
        Account hiddenAccount = new Account(Name = 'Hidden Account', AccountNumber = 'B-001', OwnerId = ownerUser.Id);

        insert new List<Account>{ visibleAccount,hiddenAccount };

        Set<Id> accountIds = new Set<Id>{
            visibleAccount.Id,
            hiddenAccount.Id
        };

        List<Account> result;
        Integer queryDifference;
        Integer queryRowsDifference;

        System.runAs(readerUser){
            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer queryRowsBefore = Limits.getQueryRows();

            result = AccountQueryService.findReadableAccountsByIds(accountIds);

            queryDifference = Limits.getQueries() - queriesBefore;
            queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
            Test.stopTest();
        }


        Assert.isNotNull(result,'検索結果はnullではなくListとして返される必要があります。');
        Assert.areEqual(1, result.size(),'SOQLの取得件数が一致しません。取得件数：' + result.size());
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(1,queryRowsDifference,'SOQL取得行数が1行である必要があります。');

        Assert.areEqual(visibleAccount.Id, result[0].Id,'検索結果のAccountが一致しません。');

    }

    @IsTest
    static void findReadableAccountsByIds_withoutAccountReadPermission_throwsQueryException(){
        User noCrudUser = [
            SELECT Id
            FROM User
            WHERE LastName = 'AccountNoCrudUser'
            LIMIT 1
        ];

        Account insertedAccount = new Account(Name = 'Account A', AccountNumber = 'A-001', OwnerId = noCrudUser.Id);

        insert insertedAccount;

        Set<Id> accountIds = new Set<Id>{
            insertedAccount.Id
        };

        List<Account> result;
        Integer queryDifference;
        Integer queryRowsDifference;
        Boolean exceptionThrown = false;

        System.runAs(noCrudUser){
            Assert.isFalse(Schema.SObjectType.Account.isAccessible(),'テストユーザーにはAccountの参照権限がない必要があります。');

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer queryRowsBefore = Limits.getQueryRows();

            try{
                result = AccountQueryService.findReadableAccountsByIds(accountIds);
                Assert.fail('QueryExceptionが送出される必要があります。');
            } catch(QueryException exceptionRecord){
                exceptionThrown = true;
            }

            queryDifference = Limits.getQueries() - queriesBefore;
            queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
            Test.stopTest();
        }

        Assert.isNull(result,'権限不足時は検索結果を返さない必要があります。');
        Assert.isTrue(exceptionThrown,'QueryExceptionが送出される必要があります。');
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(0,queryRowsDifference,'SOQL取得行数が一致しません。取得行数：' + queryRowsDifference);

    }

    @IsTest
    static void findReadableAccountsByIds_withoutAccountNumberReadAccess_throwsQueryException(){
        User withoutNumberUser = [
            SELECT Id
            FROM User
            WHERE LastName = 'AccountWithoutNumberUser'
            LIMIT 1
        ];

        Account insertedAccount = new Account(Name = 'Account A', AccountNumber = 'A-001', OwnerId = withoutNumberUser.Id);

        insert insertedAccount;

        Set<Id> accountIds = new Set<Id>{
            insertedAccount.Id
        };

        List<Account> result;
        Integer queryDifference;
        Integer queryRowsDifference;
        Boolean exceptionThrown = false;

        System.runAs(withoutNumberUser){
            Assert.isTrue(Schema.SObjectType.Account.isAccessible(),'テストユーザーにはAccountの参照権限が必要です。');
            Assert.isFalse(Schema.SObjectType.Account.fields.AccountNumber.isAccessible(),'テストユーザーにはAccountNumberの参照権限がない必要があります。');

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer queryRowsBefore = Limits.getQueryRows();

            try{
                result = AccountQueryService.findReadableAccountsByIds(accountIds);
                Assert.fail('QueryExceptionが送出される必要があります。');
            } catch(QueryException exceptionRecord){
                exceptionThrown = true;
            }

            queryDifference = Limits.getQueries() - queriesBefore;
            queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
            Test.stopTest();
        }

        Assert.isNull(result,'権限不足時は検索結果を返さない必要があります。');
        Assert.isTrue(exceptionThrown,'QueryExceptionが送出される必要があります。');
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(0,queryRowsDifference,'SOQL取得行数が一致しません。取得行数：' + queryRowsDifference);
    }

    @IsTest
    static void findReadableAccountsByIds_withTwoHundredAccounts_returnsAllAccounts(){
        List<Account> insertAccounts = new List<Account>();

        for(Integer index = 0; index < 200 ; index++){
            String sequence = String.valueOf(index + 1).leftPad(3, '0');

            insertAccounts.add(
                new Account(Name = 'AccountA-' + sequence, AccountNumber = 'A-' + sequence)
            );
        }

        insert insertAccounts;

        Set<Id> accountIds = new Map<Id,Account>(insertAccounts).keySet();

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();

        List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);

        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Integer queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
        Test.stopTest();



        Assert.isNotNull(result,'検索結果はnullではなくListとして返される必要があります。');

        Set<Id> actualIds = new Map<Id,Account>(result).keySet();
        Assert.areEqual(insertAccounts.size(), result.size(),'SOQLの取得件数が一致しません。取得件数：' + result.size());
        Assert.areEqual(accountIds, actualIds,'検索結果に欠落または想定外のAccountがあります。');
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(200,queryRowsDifference,'SOQL取得行数が一致しません。取得行数：' + queryRowsDifference);

        for(Integer index = 0; index < result.size(); index++){
            Account expectedAccount = insertAccounts[index];
            Account actualAccount = result[index];

            Assert.areEqual(
                expectedAccount.Id,
                actualAccount.Id,
                'AccountのIdと取得順が一致しません。resultIndex=' + index
            );
            Assert.areEqual(
                expectedAccount.Name,
                actualAccount.Name,
                'AccountのNameが一致しません。resultIndex=' + index
            );
            Assert.areEqual(
                expectedAccount.AccountNumber,
                actualAccount.AccountNumber,
                'AccountNumberが一致しません。resultIndex=' + index
            );
        }
    }

    @IsTest
    static void findReadableAccountsByIds_withValidIds_usesOneQueryAndDoesNotModifyInput(){
        List<Account> insertAccounts = new List<Account>();
        for(Integer index = 0; index < 3 ; index++){
            String sequence = String.valueOf(index + 1).leftPad(3, '0');

            insertAccounts.add(
                new Account(Name = 'AccountA-' + sequence, AccountNumber = 'A-' + sequence)
            );
        }

        insert insertAccounts;

        Set<Id> accountIds = new Map<Id,Account>(insertAccounts).keySet();
        Set<Id> expectedAccountIds = new Set<Id>();
        expectedAccountIds.addAll(accountIds);

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();
        Integer dmlStatementsBefore = Limits.getDmlStatements();
        Integer dmlRowsBefore = Limits.getDmlRows();

        List<Account> result = AccountQueryService.findReadableAccountsByIds(accountIds);

        Integer queryDifference = Limits.getQueries() - queriesBefore;
        Integer queryRowsDifference = Limits.getQueryRows() - queryRowsBefore;
        Integer dmlStatementDifference = Limits.getDmlStatements() - dmlStatementsBefore;
        Integer dmlRowsDifference = Limits.getDmlRows() - dmlRowsBefore;
        Test.stopTest();

        Assert.isNotNull(result,'検索結果はnullではなくListとして返される必要があります。');

        Set<Id> actualIds = new Map<Id,Account>(result).keySet();
        Assert.areEqual(3, result.size(),'検索対象のAccountがすべて返される必要があります。取得件数：' + result.size());
        Assert.areEqual(expectedAccountIds, actualIds,'検索結果のAccount Id集合が入力と一致しません。');
        Assert.areEqual(expectedAccountIds, accountIds,'入力されたAccount Id集合を変更してはいけません。');
        Assert.areEqual(expectedAccountIds.size(), accountIds.size(),'入力されたAccount Id集合の件数を変更してはいけません。');
        Assert.areEqual(1, queryDifference,'SOQLの実行回数が一致しません。実行回数：' + queryDifference);
        Assert.areEqual(3,queryRowsDifference,'SOQL取得行数が一致しません。取得行数：' + queryRowsDifference);
        Assert.areEqual(0, dmlStatementDifference,'検索処理ではDML文を実行してはいけません。');
        Assert.areEqual(0, dmlRowsDifference,'検索処理ではDML行を消費してはいけません。');
    }
}
