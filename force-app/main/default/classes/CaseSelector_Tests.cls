@IsTest
private with sharing class CaseSelector_Tests {

    @IsTest
    static void testReturnsMatchingCases() {

        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account acc;
        Case c;
        String status = 'New';
        Datetime expectedCreatedDate = Datetime.newInstance(2026, 1, 1, 10, 0, 0);
        Integer queriesBefore;
        Integer queriesAfter;

        System.runAs(currentUser){
            //取引先作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);

            //ケース
            c = TestDataFactory.buildTestCase(acc.Id,status ,testUser.Id);
            insert c;
        }

        //作成日を設定
        Test.setCreatedDate(c.Id,expectedCreatedDate);

        Set<Id> accountIds = new Set<Id>{ acc.Id };
        Set<String> statuses = new Set<String>{ status };
        List<Case> result;

        Test.StartTest();
        queriesBefore = Limits.getQueries();   
        System.runAs(testUser){    
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
        }
        queriesAfter = Limits.getQueries();
        Test.StopTest();

        //Assert
        Assert.areEqual(1,result.size(),'サイズが一致しません。想定：1 結果：'+result.size());
        Assert.areEqual(c.Id,result[0].Id,'ケースIdが一致しません。想定：'+ c.Id + '結果：' + result[0].Id);
        Assert.areEqual(acc.Id,result[0].AccountId,'取引先Idが一致しません。想定：'+ acc.Id + '結果：' + result[0].AccountId);
        Assert.areEqual(status,result[0].Status,'ステータスが一致しません。想定：'+ status + '結果：' + result[0].Status);
        Assert.areEqual(expectedCreatedDate,result[0].CreatedDate,'作成日が一致しません。想定：'+ expectedCreatedDate + '結果：' + result[0].CreatedDate);
        Assert.areEqual(acc.Name,result[0].Account.Name,'取引先名が一致しません。想定：'+ acc.Name + '結果：' + result[0].Account.Name);
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
    }

    @IsTest
    static void testReturnsCasesForMultipleConditions(){

        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);
 
        //変数宣言
        List<Account> accList;
        Case caseA;
        Case caseB;
        Case caseC;
        Case caseD;
        List<Id> expectedAccountIds;
        Datetime dateA = datetime.newInstance(2026,1,1,10,0,0);
        Datetime dateB = datetime.newInstance(2026,1,2,10,0,0);
        Datetime dateC = datetime.newInstance(2026,1,3,10,0,0);
        Datetime dateD = datetime.newInstance(2026,1,4,10,0,0);
        Integer queriesBefore;
        Integer queriesAfter;   

        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        //Mixed DMLエラー対策
        System.runAs(currentUser){
            //取引先2件作成
            Integer numAccts = 2;
            accList = TestDataFactory.createTestAccounts(numAccts ,testUser.Id);

            //取引先のsort
            expectedAccountIds = new List<Id>{
                accList[0].Id,
                accList[1].Id
            };
            expectedAccountIds.sort();

            //ケース
            caseA = TestDataFactory.buildTestCase(expectedAccountIds[0], 'New', testUser.Id);
            caseB = TestDataFactory.buildTestCase(expectedAccountIds[1], 'Closed', testUser.Id);
            caseC = TestDataFactory.buildTestCase(expectedAccountIds[1], 'Escalated', testUser.Id);
            caseD = TestDataFactory.buildTestCase(expectedAccountIds[1], 'Working', testUser.Id);
            insert new List<Case>{
                caseA,
                caseB,
                caseC,
                caseD
            };

            //作成日を設定
            Test.setCreatedDate(caseA.Id,dateA);
            Test.setCreatedDate(caseB.Id,dateB);
            Test.setCreatedDate(caseC.Id,dateC);
            Test.setCreatedDate(caseD.Id,dateD);

        }

        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>( expectedAccountIds );
        Set<String> statuses = new Set<String>{ 'New','Closed','Escalated','Working' };
        List<Case> result;

        Test.startTest();
        queriesBefore = Limits.getQueries(); 
        System.runAs(testUser){
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
        }
        queriesAfter = Limits.getQueries(); 
        Test.stopTest();

        
        //Assertで使用する変数設定
        List<Case> expectedCases = new List<Case>{
            caseA,
            caseB,
            caseC,
            caseD
        };

        List<Datetime> expectedCreatedDates = new List<Datetime>{
            dateA,
            dateB,
            dateC,
            dateD
        };

        Map<Id, String> accountNameById = new Map<Id, String>();
        for(Account acc : accList) {
            accountNameById.put(acc.Id, acc.Name);
        }

        //Assert処理
        Assert.areEqual(expectedCases.size(),result.size(),'サイズが一致しません。想定：' + expectedCases.size() + '結果：'+ result.size());
        for(Integer i = 0 ; i < expectedCases.size() ; i++ ){
            Assert.areEqual(expectedCases[i].Id,result[i].Id,'Case Idが一致しません。index：' + i + '想定：' + expectedCases[i].Id + '結果：' + result[i].Id);
            Assert.areEqual(expectedCases[i].AccountId,result[i].AccountId,'AccountIdが一致しません。index：' + i + '想定：' + expectedCases[i].AccountId + '結果：' + result[i].AccountId);
            Assert.areEqual(expectedCases[i].Status,result[i].Status,'Statusが一致しません。index：' + i + '想定：' + expectedCases[i].Status + '結果：' + result[i].Status);
            Assert.areEqual(expectedCreatedDates[i],result[i].CreatedDate,'CreatedDateが一致しません。index：' + i + ' 想定：' + expectedCreatedDates[i] + '結果：' + result[i].CreatedDate);
            Assert.areEqual(accountNameById.get(expectedCases[i].AccountId),result[i].Account.Name,'Account.Nameが一致しません。index：' + i +' 想定：' + accountNameById.get(expectedCases[i].AccountId) +' 結果：' + result[i].Account.Name);
        }
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
    }
    
    @IsTest
    static void testExcludesNonMatchingCases(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];
        
        //変数宣言
        List<Account> accList;
        List<Id> expectedAccountIds;
        Case caseA;
        Case caseB;
        Case caseC;

        //Mixed対策
        System.runAs(currentUser){
            //取引先2件作成
            Integer numAccts = 2;
            accList = TestDataFactory.createTestAccounts(numAccts, testUser.Id);
            expectedAccountIds = new List<Id> {
                accList[0].Id,
                accList[1].Id
            };
            expectedAccountIds.sort();

            //ケース3つ作成
            caseA = TestDataFactory.buildTestCase(expectedAccountIds[0], 'New', testUser.Id);
            caseB = TestDataFactory.buildTestCase(expectedAccountIds[1], 'New', testUser.Id);
            caseC = TestDataFactory.buildTestCase(expectedAccountIds[0], 'Closed', testUser.Id);
            insert new List<Case> {
                caseA,
                caseB,
                caseC
            };
        }

        //メソッド入力値・戻り値宣言
        List<Case> result;
        Set<Id> accountIds = new Set<Id>{ expectedAccountIds[0] };
        Set<String> statuses = new Set<String> { 'New' };
        Integer queriesBefore;
        Integer queriesAfter;

        System.runAs(testUser){
            Test.StartTest();
            queriesBefore = Limits.getQueries();
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
            queriesAfter = Limits.getQueries();
            Test.StopTest();
        }

        //Assert
        Assert.areEqual(1,result.size(),'サイズが一致しません。想定：1 結果：'+ result.size());
        Assert.areEqual(caseA.Id,result[0].Id,'Case Idが一致しません。想定：' + caseA.Id + '結果：' + result[0].Id);
        Assert.areEqual(caseA.Status,result[0].Status,'Statusが一致しません。想定：' + caseA.Status + '結果：' + result[0].Status);
        Assert.areEqual(expectedAccountIds[0],result[0].AccountId,'Account Idが一致しません。想定：' + expectedAccountIds[0] + '結果：' + result[0].AccountId);
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
    }

    @IsTest
    static void testReturnsEmptyWhenNoCasesMatch(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account acc;
        String accountName = '取引先A';

        //Mixed対策
        System.runAs(currentUser){
            //取引先1件作成
            acc = TestDataFactory.createTestAccount(accountName, testUser.Id);
        }

        //メソッド入力値・戻り値宣言
        List<Case> result;
        Set<Id> accountIds = new Set<Id>{ acc.Id };
        Set<String> statuses = new Set<String>{ 'New' };
        Integer queriesBefore;
        Integer queriesAfter;
        

        System.runAs(testUser){
            Test.StartTest();
            queriesBefore = Limits.getQueries();
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
            queriesAfter = Limits.getQueries();
            Test.StopTest();
        }

        //Assert
        Assert.isNotNull(result);
        Assert.isTrue(result.isEmpty());
        Assert.areEqual(0,result.size(),'サイズが一致しません。想定：0 結果：'+ result.size());
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
    }

    @IsTest
    static void testReturnsCasesInExpectedOrder(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];
        
        //変数宣言
        List<Account> accList;
        List<Id> expectedAccountIds;
        List<Id> expectedCaseIds;
        Case caseA;
        Case caseB;
        Case caseC;
        Case caseD;
        Datetime dateSame = datetime.newInstance(2026,1,1,10,0,0);
        Datetime dateA = datetime.newInstance(2026,1,2,10,0,0);
        Datetime dateD = datetime.newInstance(2025,12,31,10,0,0);
        Integer queriesBefore;
        Integer queriesAfter; 

        //Mixed対策
        System.runAs(currentUser){
            //取引先2件作成
            Integer numAccts = 2;
            accList = TestDataFactory.createTestAccounts(numAccts, testUser.Id);
            expectedAccountIds = new List<Id> {
                accList[0].Id,
                accList[1].Id
            };
            expectedAccountIds.sort();

            //ケース4つ作成
            caseA = TestDataFactory.buildTestCase(expectedAccountIds[0], 'New', testUser.Id);
            caseB = TestDataFactory.buildTestCase(expectedAccountIds[0], 'New', testUser.Id);
            caseC = TestDataFactory.buildTestCase(expectedAccountIds[0], 'New', testUser.Id);
            caseD = TestDataFactory.buildTestCase(expectedAccountIds[1], 'New', testUser.Id);
            insert new List<Case> {
                caseA,
                caseB,
                caseC,
                caseD
            };

            /*
            ケースIdソート
            並び順
            1.CaseBまたはCaseCのIdが小さいCase
            2.CaseBまたはCaseCのIdが大きいCase
            3.CaseA
            4.CaseD
            **/
            List<Id> sameDateCaseIds = new List<Id>{
                caseB.Id,
                caseC.Id
            };
            sameDateCaseIds.sort();

            expectedCaseIds = new List<Id>{
                sameDateCaseIds[0],
                sameDateCaseIds[1],
                caseA.Id,
                caseD.Id
            };

            //作成日を設定
            Test.setCreatedDate(caseA.Id,dateA);
            Test.setCreatedDate(caseB.Id,dateSame);
            Test.setCreatedDate(caseC.Id,dateSame);
            Test.setCreatedDate(caseD.Id,dateD);
        }

        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>( expectedAccountIds );
        Set<String> statuses = new Set<String>{ 'New' };
        List<Case> result;

        
        Test.startTest();
        queriesBefore = Limits.getQueries(); 
        System.runAs(testUser){
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
        }
        queriesAfter = Limits.getQueries(); 
        Test.stopTest();

        //Assertで使用する変数設定
        //ケースのId期待値順にList並び替え
        Map<Id,Case> caseById = new Map<Id,Case>{
            caseA.Id => caseA,
            caseB.Id => caseB,
            caseC.Id => caseC,
            caseD.Id => caseD
        };
        List<Case> expectedCases = new List<Case>();
        for(Id caseId : expectedCaseIds){
            expectedCases.add(caseById.get(caseId));
        }

        //作成日をIdでマッピング、のちに順序確認で使用
        Map<Id,Datetime> createdDateByCaseId = new Map<Id,Datetime>{
            CaseA.Id => dateA,
            CaseB.Id => dateSame,
            CaseC.Id => dateSame,
            CaseD.Id => dateD
        };

        Map<Id, String> accountNameById = new Map<Id, String>();
        for(Account acc : accList) {
            accountNameById.put(acc.Id, acc.Name);
        }

        //Assert確認
        Assert.areEqual(expectedCases.size(),result.size(),'サイズが一致しません。想定：' + expectedCases.size() + '結果：'+ result.size());
        for(Integer i = 0 ; i < expectedCases.size() ; i++ ){
            Assert.areEqual(expectedCases[i].Id,result[i].Id,'Case Idが一致しません。index：' + i + '想定：' + expectedCases[i].Id + '結果：' + result[i].Id);
            Assert.areEqual(expectedCases[i].AccountId,result[i].AccountId,'AccountIdが一致しません。index：' + i + '想定：' + expectedCases[i].AccountId + '結果：' + result[i].AccountId);
            Assert.areEqual(expectedCases[i].Status,result[i].Status,'Statusが一致しません。index：' + i + '想定：' + expectedCases[i].Status + '結果：' + result[i].Status);
            Assert.areEqual(createdDateByCaseId.get(expectedCases[i].Id),result[i].CreatedDate,'CreatedDateが一致しません。index：' + i + ' 想定：' + createdDateByCaseId.get(expectedCases[i].Id) + '結果：' + result[i].CreatedDate);
            Assert.areEqual(accountNameById.get(expectedCases[i].AccountId),result[i].Account.Name,'Account.Nameが一致しません。index：' + i +' 想定：' + accountNameById.get(expectedCases[i].AccountId) +' 結果：' + result[i].Account.Name);
        }
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
    }

    @IsTest
    static void testReturnsEmptyForNullOrEmptyInput(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account acc;
        Integer queriesBefore;
        Integer queriesAfter;

        //テストデータ作成
        System.runAs(currentUser){
            //取引先作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);
        }

        //メソッド入力・戻り値変数宣言
        Set<Id> validAccountIds = new Set<Id> { acc.Id };
        Set<String> validStatuses = new Set<String> { 'New' };
        List<Case> resultNullAccountIds;
        List<Case> resultEmptyAccountIds;
        List<Case> resultNullStatuses;
        List<Case> resultEmptyStatuses;

        Test.StartTest();
        queriesBefore = Limits.getQueries();   
        System.runAs(testUser){    
            resultNullAccountIds = CaseSelector.getCasesByAccountsAndStatuses(null, validStatuses);
            resultEmptyAccountIds = CaseSelector.getCasesByAccountsAndStatuses(new Set<Id>(), validStatuses);
            resultNullStatuses = CaseSelector.getCasesByAccountsAndStatuses(validAccountIds, null);
            resultEmptyStatuses = CaseSelector.getCasesByAccountsAndStatuses(validAccountIds, new Set<String>());
        }
        queriesAfter = Limits.getQueries();
        Test.StopTest();

        //Assert
        Assert.areEqual(0, resultNullAccountIds.size(),'サイズが一致しません。想定：0 結果：'+ resultNullAccountIds.size());
        Assert.areEqual(0, resultEmptyAccountIds.size(),'サイズが一致しません。想定：0 結果：'+ resultEmptyAccountIds.size());
        Assert.areEqual(0, resultNullStatuses.size(),'サイズが一致しません。想定：0 結果：'+ resultNullStatuses.size());
        Assert.areEqual(0, resultEmptyStatuses.size(),'サイズが一致しません。想定：0 結果：'+ resultEmptyStatuses.size());
        Assert.areEqual(0,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：0 結果：' + (queriesAfter - queriesBefore));  
    }

    @IsTest
    static void testHandlesNullInsideSet(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];
        
        //変数宣言
        Account acc;
        Case c;
        String status = 'New';
        Integer queriesBefore;
        Integer queriesAfter; 

        //Mixed対策
        System.runAs(currentUser){
            //取引先1件作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);

            //ケース1つ作成
            c = TestDataFactory.buildTestCase(acc.Id, status, testUser.Id);
            insert c;
        }

        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>{ acc.Id, null };
        Set<String> statuses = new Set<String>{ status, null, ' ' };
        List<Case> result;

        Test.StartTest();
        queriesBefore = Limits.getQueries();   
        System.runAs(testUser){    
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
        }
        queriesAfter = Limits.getQueries();
        Test.StopTest();
        
        //Assert
        Assert.areEqual(1,result.size(),'サイズが一致しません。想定：1 結果：'+ result.size());
        Assert.areEqual(c.Id,result[0].Id,'ケースIdが一致しません。想定：'+ c.Id + '結果：' + result[0].Id);
        Assert.areEqual(acc.Id,result[0].AccountId,'取引先Idが一致しません。想定：'+ acc.Id + '結果：' + result[0].AccountId);
        Assert.areEqual(status,result[0].Status,'ステータスが一致しません。想定：'+ status + '結果：' + result[0].Status);
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
        Assert.areEqual(2,accountIds.size(),'サイズが一致しません。想定：2 結果：' + accountIds.size());
        Assert.isTrue(accountIds.contains(acc.Id),'元のAccountIdが入力Setから削除されています。');
        Assert.isTrue(accountIds.contains(null),'nullが入力Setから削除されています。');
        Assert.areEqual(3,statuses.size(),'サイズが一致しません。想定：3 結果：' + statuses.size());
        Assert.isTrue(statuses.contains(status),status + 'が入力Setから削除されています。');
        Assert.isTrue(statuses.contains(null),'nullが入力Setから削除されています。');
        Assert.isTrue(statuses.contains(' '),'空白文字が入力Setから削除されています。');
    }

    @IsTest
    static void testReturnsEmptyAfterCleaningInputs(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account acc;
        String status = 'New';
        Integer queriesBefore;
        Integer queriesAfter;

        //テストデータ作成
        System.runAs(currentUser){
            //取引先作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);
        }

        //メソッド入力・戻り値変数宣言
        Set<Id> validAccountIds = new Set<Id> { acc.Id };
        Set<Id> invalidAccountIds = new Set<Id> { null };

        Set<String> validStatuses = new Set<String> { status };
        Set<String> invalidStatuses = new Set<String> { null,' ' };
        List<Case> resultInvalidAccountIds;
        List<Case> resultInvalidStatuses;

        Test.StartTest();
        queriesBefore = Limits.getQueries();   
        System.runAs(testUser){    
            resultInvalidAccountIds = CaseSelector.getCasesByAccountsAndStatuses(invalidAccountIds, validStatuses);
            resultInvalidStatuses = CaseSelector.getCasesByAccountsAndStatuses(validAccountIds, invalidStatuses);
        }
        queriesAfter = Limits.getQueries();
        Test.StopTest();

        //Assert
        Assert.areEqual(0, resultInvalidAccountIds.size(), 'サイズが一致しません。想定：0 結果：' + resultInvalidAccountIds.size());
        Assert.areEqual(1, validAccountIds.size(), 'サイズが一致しません。想定：1 結果：' + validAccountIds.size());
        Assert.isTrue(validAccountIds.contains( acc.Id ),'元のAccount Idが入力Setから削除されています。');
        Assert.areEqual(1, invalidAccountIds.size(), 'サイズが一致しません。想定：1 結果：' + invalidAccountIds.size());
        Assert.isTrue(invalidAccountIds.contains(null),'nullが入力Setから削除されています。');

        Assert.areEqual(0, resultInvalidStatuses.size(), 'サイズが一致しません。想定：0 結果：' + resultInvalidStatuses.size());
        Assert.areEqual(1, validStatuses.size(), 'サイズが一致しません。想定：1 結果：' + validStatuses.size());
        Assert.isTrue(validStatuses.contains( status ),'ステータスが入力Setから削除されています。');
        Assert.areEqual(2, invalidStatuses.size(), 'サイズが一致しません。想定：2 結果：' + invalidStatuses.size());
        Assert.isTrue(invalidStatuses.contains(null),'nullが入力Setから削除されています。');
        Assert.isTrue(invalidStatuses.contains(' '),'空文字が入力Setから削除されています。');
        Assert.areEqual(0,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：0 結果：' + (queriesAfter - queriesBefore));
    }

    @IsTest
    static void testThrowsQueryExceptionWithoutCaseRead(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];
        
        //変数宣言
        Account acc;
        Case c;
        String status = 'New';

        //Mixed対策
        System.runAs(currentUser){
            //取引先1件作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);

            //ケース1つ作成
            c = TestDataFactory.buildTestCase(acc.Id, status, testUser.Id);
            insert c;
        }

        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>{ acc.Id };
        Set<String> statuses = new Set<String>{ status };
        Boolean queryExceptionThrown = false;

        Test.StartTest();
        try {
            System.runAs(testUser){    
                CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
            }
        } catch (QueryException e){
            queryExceptionThrown = true;
        } catch (Exception e){
            Assert.fail('想定外の例外が発生しました。型：' + e.getTypeName());
        }
        Test.StopTest();

        //Assert
        Assert.isTrue(queryExceptionThrown,'Case Read権限がないためQueryExceptionが発生する想定です。');
    }

    @IsTest
    static void testCaseAccountIdAccessDenied(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account acc;
        Case c;
        String status = 'New';

        //Mixed対策
        System.runAs(currentUser){
            //取引先1件作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);

            //ケース1つ作成
            c = TestDataFactory.buildTestCase(acc.Id, status, testUser.Id);
            insert c;
        }
        
        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>{ acc.Id };
        Set<String> statuses = new Set<String>{ status };
        Boolean queryExceptionThrown = false;

        Test.StartTest();
        try {
            System.runAs(testUser){    
                CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
            }
        } catch (QueryException e){
            queryExceptionThrown = true;
        } catch (Exception e){
            Assert.fail('想定外の例外が発生しました。型：' + e.getTypeName());
        }
        Test.StopTest();

        //Assert
        Assert.isTrue(queryExceptionThrown,'Case.AccountIdへの項目権限がないためQueryExceptionが発生する想定です。');
    }

    @IsTest
    static void testAccountReadAccessDenied(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM USER
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account acc;
        Case c;
        String status = 'New';

        //Mixed対策
        System.runAs(currentUser){
            //取引先1件作成
            acc = TestDataFactory.createTestAccount('テスト取引先', testUser.Id);

            //ケース1つ作成
            c = TestDataFactory.buildTestCase(acc.Id, status, testUser.Id);
            insert c;
        }
        
        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>{ acc.Id };
        Set<String> statuses = new Set<String>{ status };
        Boolean queryExceptionThrown = false;

        Test.StartTest();
        try {
            System.runAs(testUser){    
                CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
            }
        } catch (QueryException e){
            queryExceptionThrown = true;
        } catch (Exception e){
            Assert.fail('想定外の例外が発生しました。型：' + e.getTypeName());
        }
        Test.StopTest();

        //Assert
        Assert.isTrue(queryExceptionThrown,'Account参照権限がないためQueryExceptionが発生する想定です。');
    }

    @IsTest
    static void testExcludesCasesWithoutRecordAccess(){
        USER otherUser = TestDataFactory.createMinimumAccessUser();
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        //変数宣言
        Account visibleAccount;
        Case visibleCase;

        Account hiddenAccount;
        Case hiddenCase;

        String status = 'New';
        Integer queriesBefore;
        Integer queriesAfter;

        System.runAs(currentUser){
            //取引先作成
            visibleAccount = TestDataFactory.createTestAccount('参照可能取引先', testUser.Id);
            hiddenAccount = TestDataFactory.createTestAccount('参照不可取引先', otherUser.Id);

            //ケース
            visibleCase = TestDataFactory.buildTestCase(visibleAccount.Id,status ,testUser.Id);
            hiddenCase = TestDataFactory.buildTestCase(hiddenAccount.Id,status ,otherUser.Id);
            insert new List<Case>{
                visibleCase,
                hiddenCase
            };
        }

        
        //メソッド入力・戻り値変数宣言
        Set<Id> validAccountIds = new Set<Id> { 
            visibleAccount.Id,
            hiddenAccount.Id
        };

        Set<String> Statuses = new Set<String> { status };
        List<Case> result;

        Test.StartTest();
        queriesBefore = Limits.getQueries();   
        System.runAs(testUser){    
            result = CaseSelector.getCasesByAccountsAndStatuses(validAccountIds, Statuses);
        }
        queriesAfter = Limits.getQueries();
        Test.StopTest();

        Set<Id> resultCaseIds = new set<Id>();

        for(Case c : result){
            resultCaseIds.add(c.Id);
        }

        //Assert
        Assert.areEqual(1,result.size(),'サイズが一致しません。想定：1 結果：'+ result.size());
        Assert.areEqual(visibleCase.Id, result[0].Id,'Case Idが一致しません。想定：' + visibleCase.Id + '結果：' + result[0].Id);
        Assert.isFalse(resultCaseIds.contains(hiddenCase.Id),'参照権限のないCaseが取得されています。');
        Assert.areEqual(visibleAccount.Id,result[0].AccountId,'取引先Idが一致しません。想定：'+ visibleAccount.Id + '結果：' + result[0].AccountId);
        Assert.areEqual(status,result[0].Status,'ステータスが一致しません。想定：'+ status + '結果：' + result[0].Status);
        Assert.areEqual(visibleAccount.Name,result[0].Account.Name,'取引先名が一致しません。想定：'+ visibleAccount.Name + '結果：' + result[0].Account.Name);
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));
    }

    @IsTest
    static void testMeasuresResourceUsage(){
        User testUser = TestDataFactory.createMinimumAccessUser();
        Set<String> permissionSetNames = new Set<String> {
            'CaseSel_AccountRead',
            'CaseSel_CaseRead',
            'CaseSel_CaseAccountIdRead'
        };
        TestDataFactory.assignPermissionSets(testUser, permissionSetNames);

        //変数宣言
        List<Account> accList;
        List<Case> caseList = new List<Case>();

        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        //Mixed DMLエラー対策
        System.runAs(currentUser){
            //取引先200件作成
            Integer numAccts = 200;
            accList = TestDataFactory.createTestAccounts(numAccts ,testUser.Id);

            //ケース
            for( Account acc : accList ){

                for( Integer i = 0 ; i < 10; i++){
                    caseList.add(
                        TestDataFactory.buildTestCase(acc.Id,'New',testUser.Id)
                    );
                }
            }
            insert caseList;
        }

        //メソッド入力・戻り値変数宣言
        Set<Id> accountIds = new Set<Id>();
        for(Account acc : accList){
            accountIds.add(acc.Id);
        }
        Set<String> statuses = new Set<String>{ 'New' };
        List<Case> result;

        Integer queriesBefore;
        Integer queriesAfter;

        Integer queryRowsBefore;
        Integer queryRowsAfter;

        Integer cpuBefore;
        Integer cpuAfter;

        Integer heapBefore;
        Integer heapAfter;

        Integer cpuLimit;
        Integer heapLimit;
        Integer queryRowsLimit;

        Test.startTest();
        System.runAs(testUser){
            queriesBefore = Limits.getQueries(); 
            cpuBefore = Limits.getCpuTime();
            queryRowsBefore = Limits.getQueryRows();
            heapBefore = Limits.getHeapSize();
            
            result = CaseSelector.getCasesByAccountsAndStatuses(accountIds, statuses);
            
            queriesAfter = Limits.getQueries(); 
            cpuAfter= Limits.getCpuTime();
            queryRowsAfter = Limits.getQueryRows();
            heapAfter = Limits.getHeapSize();

            cpuLimit = Limits.getLimitCpuTime();
            heapLimit = Limits.getLimitHeapSize();
            queryRowsLimit = Limits.getLimitQueryRows();
        }
        Test.stopTest();

        //１．戻り値が2000件
        Assert.areEqual(2000,result.size(),'サイズが一致しません。想定：2000 結果：'+ result.size());

        //２．SOQL増加回数が1回
        Assert.areEqual(1,queriesAfter - queriesBefore,'SOQL実行回数が一致しません。想定：1 結果：' + (queriesAfter - queriesBefore));

        //３．取得行数の増加が2000件
        Assert.areEqual(2000,queryRowsAfter - queryRowsBefore,'取得行数が一致しません。想定：2000 結果：' + (queryRowsAfter - queryRowsBefore));

        //４．CPU使用量がCPU上限未満
        Integer cpuUsed = cpuAfter - cpuBefore;
        Assert.isTrue(cpuUsed < cpuLimit,'CPU使用量が上限以上です。使用量：' + cpuUsed + 'ms 上限：' + cpuLimit + 'ms');

        //５．ヒープ使用量がヒープ上限未満
        Integer heapUsed = heapAfter - heapBefore;
        Assert.isTrue(heapUsed < heapLimit,'ヒープ使用増加量が上限以上です。使用量：' + heapUsed +'bytes 上限：' + heapLimit +'bytes');
        Assert.isTrue(heapAfter < heapLimit,'現在のヒープ使用量が上限以上です。使用量：' + heapAfter +'bytes 上限：' + heapLimit +'bytes');

        //６．取得行数が取得行数上限未満
        Assert.isTrue(queryRowsAfter < queryRowsLimit,'SOQL取得行数が上限以上です。取得行数：' + queryRowsAfter +' 上限：' + queryRowsLimit);

        //成功時の測定値
        Integer soqlUsed = queriesAfter - queriesBefore;
        Integer queryRowsUsed = queryRowsAfter - queryRowsBefore;

        System.debug('=== CaseSelector Resource Usage ===');
        System.debug('取得Case件数: ' + result.size());
        System.debug('Account入力件数: ' + accountIds.size());
        System.debug('SOQL使用回数: ' + soqlUsed);
        System.debug('SOQL取得行数: ' + queryRowsUsed);
        System.debug('CPU使用量: ' + cpuUsed + 'ms / 上限: ' + cpuLimit + 'ms');
        System.debug('Heap実行前: ' + heapBefore + 'bytes');
        System.debug('Heap増加量: ' + heapUsed + 'bytes / 上限: ' + heapLimit + 'bytes');
        System.debug('Heap現在値: ' + heapAfter + 'bytes');
        System.debug('QueryRows現在値: ' + queryRowsAfter + ' / 上限: ' + queryRowsLimit);
        System.debug('===================================');
    }
}