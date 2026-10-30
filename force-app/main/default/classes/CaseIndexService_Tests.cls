@IsTest
private class CaseIndexService_Tests {
    private static final Id ACCOUNT_A_ID = '001000000000001AAA';
    private static final Id ACCOUNT_B_ID = '001000000000001BBB';

    // CP5再設計テスト：正常・グループ化・順序・混在
    @IsTest
    static void groupOpenCasesByAccount_withSingleValidCase_returnsGroupedMap(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Case A1', Status = 'New', AccountId = ACCOUNT_A_ID )
        };

        List<Case> expectedAccountACases = new List<Case>{
            testCases[0]
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'有効なCaseが1件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(1, result.size(),'有効なCaseが1件の場合、結果Mapには1つのAccountIdキーが必要です。');
        //共通化処理
        assertCasesForAccount(result,ACCOUNT_A_ID,expectedAccountACases);

    }

    @IsTest
    static void groupOpenCasesByAccount_withCasesForMultipleAccounts_returnsCasesGroupedByAccount(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Case A1', Status = 'New', AccountId = ACCOUNT_A_ID),
            new Case( Subject = 'Case B1', Status = 'Working', AccountId = ACCOUNT_B_ID)
        };

        List<Case> expectedAccountACases = new List<Case>{
            testCases[0]
        };

        List<Case> expectedAccountBCases = new List<Case>{
            testCases[1]
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'有効なCaseが2件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(2, result.size(),'結果Mapには2つのAccountIdキーが必要です。');



        assertCasesForAccount(result,ACCOUNT_A_ID,expectedAccountACases);
        assertCasesForAccount(result,ACCOUNT_B_ID,expectedAccountBCases);
    }

    @IsTest
    static void groupOpenCasesByAccount_withMultipleCasesForSameAccount_returnsCasesInInputOrder(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Case A2', Status = 'New', AccountId = ACCOUNT_A_ID),
            new Case( Subject = 'Case A1', Status = 'New', AccountId = ACCOUNT_A_ID),
            new Case( Subject = 'Case A3', Status = 'New', AccountId = ACCOUNT_A_ID)
        };

        List<Case> expectedAccountACases = new List<Case>{
            testCases[0],
            testCases[1],
            testCases[2]
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'有効なCaseが3件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(1, result.size(),'結果Mapには1つのAccountIdキーが必要です。');

        assertCasesForAccount(result,ACCOUNT_A_ID,expectedAccountACases);
    }


    @IsTest
    static void groupOpenCasesByAccount_withValidAndExcludedCases_returnsOnlyValidCases(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Case A Before Exclusions' ,Status =  'New' ,AccountId = ACCOUNT_A_ID ),
            null,
            new Case( Subject = 'Case Without Account' ,Status = 'New' ,AccountId = null),
            new Case( Subject = 'Case Without Status' ,Status = null ,AccountId = ACCOUNT_A_ID),
            new Case( Subject = 'Closed Case' ,Status = 'Closed' ,AccountId = ACCOUNT_B_ID),
            new Case( Subject = 'Case A After Exclusions' ,Status = 'New' ,AccountId = ACCOUNT_A_ID),
            new Case( Subject = 'Case B After Exclusions' ,Status = 'New' ,AccountId = ACCOUNT_B_ID)
        };

        List<Case> expectedAccountACases = new List<Case>{
            testCases[0],
            testCases[5]
        };

        List<Case> expectedAccountBCases = new List<Case>{
            testCases[6]
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'有効なCaseが3件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(2, result.size(),'結果Mapには2つのAccountIdキーが必要です。');

        assertCasesForAccount(result,ACCOUNT_A_ID,expectedAccountACases);
        assertCasesForAccount(result,ACCOUNT_B_ID,expectedAccountBCases);
    }

    // CP5再設計テスト：null・空・除外境界
    @IsTest
    static void groupOpenCasesByAccount_withNullInput_returnsEmptyMap(){
        List<Case> testCases = null;

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'入力Listがnullでも、結果Mapはnullではなく空Mapである必要があります。');
        Assert.areEqual(0, result.size(),'入力Listがnullの場合、結果Mapは空である必要があります。' );
    }

    @IsTest
    static void groupOpenCasesByAccount_withEmptyInput_returnsEmptyMap(){
        List<Case> testCases = new List<Case>();

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'入力Listが空の場合、結果Mapは空Mapである必要があります。');
        Assert.areEqual(0, result.size(),'入力Listが空の場合、結果Mapは空である必要があります。' );
    }

    @IsTest
    static void groupOpenCasesByAccount_withNullElement_skipsNullAndProcessesFollowingCase(){
        List<Case> testCases = new List<Case>{
            null,
            new Case( Subject = 'Valid After Null' ,Status = 'New' ,AccountId = ACCOUNT_A_ID)
        };

        List<Case> expectedAccountACases = new List<Case>{
            testCases[1]
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'有効なCaseが1件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(1, result.size(),'有効なCaseが1件の場合、結果Mapには1つのAccountIdキーが必要です。');

        assertCasesForAccount(result ,ACCOUNT_A_ID ,expectedAccountACases);
    }

    @IsTest
    static void groupOpenCasesByAccount_withCaseWithoutAccountId_excludesCase(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'nullAccountIdCase' ,Status = 'New' , AccountId = null)
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.IsNotNull(result,'有効なCaseが存在しない場合、結果Mapはnullであってはいけません');
        Assert.areEqual(0, result.size() ,'有効なCaseが存在しない場合、結果Mapは空である必要があります。');
    }

    @IsTest
    static void groupOpenCasesByAccount_withNullStatus_excludesCase(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Status Null Case' ,Status = null , AccountId = ACCOUNT_A_ID )
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'Statusがnullでも、結果Mapはnullではなく空Mapである必要があります。');
        Assert.areEqual(0, result.size(),'StatusがnullのCaseは除外され、結果Mapは空である必要があります。');
    }

    @IsTest
    static void groupOpenCasesByAccount_withEmptyStatus_excludesCase(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Status Empty Case' ,Status = '' , AccountId = ACCOUNT_A_ID )
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'Statusが空文字でも、結果Mapはnullではなく空Mapである必要があります。');
        Assert.areEqual(0, result.size(),'Statusが空文字のCaseは除外され、結果Mapは空である必要があります。');
    }

    @IsTest
    static void groupOpenCasesByAccount_withWhitespaceStatus_excludesCase(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Status Whitespace Case' ,Status = '   ' , AccountId = ACCOUNT_A_ID )
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result,'Statusが空白文字だけでも、結果Mapはnullではなく空Mapである必要があります。');
        Assert.areEqual(0, result.size(),'Statusが空白文字だけのCaseは除外され、結果Mapは空である必要があります。');
    }

    @IsTest
    static void groupOpenCasesByAccount_withClosedCase_excludesCase(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Closed Case' ,Status = 'Closed' , AccountId = ACCOUNT_A_ID)
        };

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.IsNotNull(result,'有効なCaseが存在しない場合、結果Mapはnullであってはいけません');
        Assert.areEqual(0, result.size() ,'有効なCaseが存在しない場合、結果Mapは空である必要があります。');
    }

    @IsTest
    static void groupOpenCasesByAccount_withTwoHundredValidCases_groupsAllCasesByAccount(){
        List<Case> testCases = new List<Case>();
        List<Case> expectedAccountACases = new List<Case>();
        List<Case> expectedAccountBCases = new List<Case>();

        for(Integer index = 0; index < 100; index++){
            String sequenceNumber = String.valueOf(index).leftPad(3,'0');
            String caseASubject = 'Case A-' + sequenceNumber;
            String caseBSubject = 'Case B-' + sequenceNumber;

            Case caseA = new Case(
                Subject = caseASubject, Status = 'New', AccountId = ACCOUNT_A_ID
            );

            Case caseB = new Case(
                Subject = caseBSubject, Status = 'New', AccountId = ACCOUNT_B_ID
            );

            testCases.add(caseA);
            testCases.add(caseB);

            expectedAccountACases.add(caseA);
            expectedAccountBCases.add(caseB);
        }

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.IsNotNull(result,'有効なCaseが200件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(2, result.size() ,'有効なCaseが200件の場合、結果Mapには2つのAccountIdキーが必要です。');

        assertCasesForAccount(result,ACCOUNT_A_ID,expectedAccountACases);
        assertCasesForAccount(result,ACCOUNT_B_ID,expectedAccountBCases);
    }

    @IsTest
    static void groupOpenCasesByAccount_doesNotModifyInputListOrCases(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Case A' ,Status = 'New' , AccountId = ACCOUNT_A_ID),
            null,
            new Case( Subject = 'Case B Closed' ,Status = 'Closed' , AccountId = ACCOUNT_B_ID),
            new Case( Subject = 'Case B' ,Status = 'New' , AccountId = ACCOUNT_B_ID)
        };

        Integer originalListSize = testCases.size();
        Case originalCaseA = testCases[0];
        Case originalCaseB1 = testCases[2];
        Case originalCaseB2 = testCases[3];

        String originalCaseASubject = originalCaseA.Subject;
        String originalCaseAStatus = originalCaseA.Status;
        Id originalCaseAAccountId = originalCaseA.AccountId;
        String originalCaseB1Subject = originalCaseB1.Subject;
        String originalCaseB1Status = originalCaseB1.Status;
        Id originalCaseB1AccountId = originalCaseB1.AccountId;
        String originalCaseB2Subject = originalCaseB2.Subject;
        String originalCaseB2Status = originalCaseB2.Status;
        Id originalCaseB2AccountId = originalCaseB2.AccountId;

        Test.startTest();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Test.stopTest();

        Assert.isNotNull(result, '結果Mapはnullであってはいけません。');
        Assert.areEqual(2, result.size(), '結果Mapには2つのAccountIdキーが必要です。');

        Assert.areEqual(originalListSize, testCases.size(), '入力Listの件数を変更してはいけません。');
        Assert.isTrue(testCases[0] === originalCaseA, 'inputIndex=0のCase参照を変更してはいけません。');
        Assert.isNull(testCases[1], 'inputIndex=1のnull位置を変更してはいけません。');
        Assert.isTrue(testCases[2] === originalCaseB1, 'inputIndex=2のCase参照を変更してはいけません。');
        Assert.isTrue(testCases[3] === originalCaseB2, 'inputIndex=3のCase参照を変更してはいけません。');

        Assert.areEqual(originalCaseASubject, testCases[0].Subject, 'inputIndex=0のSubjectを変更してはいけません。');
        Assert.areEqual(originalCaseAStatus, testCases[0].Status, 'inputIndex=0のStatusを変更してはいけません。');
        Assert.areEqual(originalCaseAAccountId, testCases[0].AccountId, 'inputIndex=0のAccountIdを変更してはいけません。');

        Assert.areEqual(originalCaseB1Subject, testCases[2].Subject, 'inputIndex=2のSubjectを変更してはいけません。');
        Assert.areEqual(originalCaseB1Status, testCases[2].Status, 'inputIndex=2のStatusを変更してはいけません。');
        Assert.areEqual(originalCaseB1AccountId, testCases[2].AccountId, 'inputIndex=2のAccountIdを変更してはいけません。');

        Assert.areEqual(originalCaseB2Subject, testCases[3].Subject, 'inputIndex=3のSubjectを変更してはいけません。');
        Assert.areEqual(originalCaseB2Status, testCases[3].Status, 'inputIndex=3のStatusを変更してはいけません。');
        Assert.areEqual(originalCaseB2AccountId, testCases[3].AccountId, 'inputIndex=3のAccountIdを変更してはいけません。');

    }

    @IsTest
    static void groupOpenCasesByAccount_withValidCases_executesWithoutSoqlOrDml(){
        List<Case> testCases = new List<Case>{
            new Case( Subject = 'Case A', Status = 'New', AccountId = ACCOUNT_A_ID )
        };

        List<Case> expectedAccountACases = new List<Case>{
            testCases[0]
        };

        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        Integer beforeDmlStatements = Limits.getDMLStatements();
        Integer beforeDmlRows = Limits.getDMLRows();
        Map<Id,List<Case>> result = CaseIndexService.groupOpenCasesByAccount(testCases);
        Integer afterQueries = Limits.getQueries();
        Integer afterDmlStatements = Limits.getDMLStatements();
        Integer afterDmlRows = Limits.getDMLRows();
        Test.stopTest();

        Assert.isNotNull(result,'有効なCaseが1件の場合、結果Mapはnullであってはいけません。');
        Assert.areEqual(1, result.size(),'有効なCaseが1件の場合、結果Mapには1つのAccountIdキーが必要です。');

        assertCasesForAccount(result,ACCOUNT_A_ID,expectedAccountACases);

        Assert.areEqual(
            0,
            afterQueries - beforeQueries,
            'groupOpenCasesByAccountはSOQLを実行してはいけません。'
        );
        Assert.areEqual(
            0,
            afterDmlStatements - beforeDmlStatements,
            'groupOpenCasesByAccountはDML文を実行してはいけません。'
        );
        Assert.areEqual(
            0,
            afterDmlRows - beforeDmlRows,
            'groupOpenCasesByAccount must not consume any DML rows.'
        );
    }

    //共通化処理
    private static void assertCasesForAccount(
        Map<Id, List<Case>> result,
        Id expectedAccountId,
        List<Case> expectedCases
    ){
        Assert.isTrue(
            result.containsKey(expectedAccountId),
            '結果MapにAccountId=' + expectedAccountId + 'のキーが必要です。'
        );
        List<Case> actualCases = result.get(expectedAccountId);
        Assert.isNotNull(
            actualCases,
            'AccountId=' + expectedAccountId + 'に対応するCase Listはnullであってはいけません。'
        );
        Assert.areEqual(
            expectedCases.size(),
            actualCases.size(),
            'AccountId=' + expectedAccountId
                + 'に対応するCase Listの件数が一致しません。期待値='
                + expectedCases.size() + '、実測値=' + actualCases.size() + '。'
        );

        for(Integer index = 0 ; index < actualCases.size() ; index++){
            Case expectedCase = expectedCases[index];
            Case actualCase = actualCases[index];

            Assert.areEqual(
                expectedCase.AccountId,
                actualCase.AccountId,
                'AccountId=' + expectedAccountId + '、List index=' + index
                    + '、項目=AccountIdが一致しません。期待値='
                    + expectedCase.AccountId + '、実測値=' + actualCase.AccountId + '。'
            );
            Assert.areEqual(
                expectedCase.Subject,
                actualCase.Subject,
                'AccountId=' + expectedAccountId + '、List index=' + index
                    + '、項目=Subjectが一致しません。期待値='
                    + expectedCase.Subject + '、実測値=' + actualCase.Subject + '。'
            );
            Assert.areEqual(
                expectedCase.Status,
                actualCase.Status,
                'AccountId=' + expectedAccountId + '、List index=' + index
                    + '、項目=Statusが一致しません。期待値='
                    + expectedCase.Status + '、実測値=' + actualCase.Status + '。'
            );
        }
    }
}
