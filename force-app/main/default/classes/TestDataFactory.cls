@IsTest
public class TestDataFactory {


    //最小権限のユーザーを作成するメソッド
    public static User createMinimumAccessUser() {
        return createMinimumAccessUser(
            'tuser',
            'TestUser',
            null
        );
    }

    public static User createMinimumAccessUser(
        String alias,
        String lastName,
        Id userRoleId
    ){
        Profile minimumProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];

        User testUser = new User(
            Alias = alias,
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'ja',
            LocaleSidKey = 'ja_JP',
            ProfileId = minimumProfile.Id,
            TimeZoneSidKey = 'Asia/Tokyo',
            Username = generateUniqueUsername(),
            UserRoleId = userRoleId
        );

        insert testUser;

        return testUser;
    }

    private static String generateUniqueUsername() {
        return 'testuser.' +
            UserInfo.getOrganizationId() + '.' +
            System.currentTimeMillis() + '.' +
            String.valueOf(Math.random()) +
            '@example.com';
    }

    //ユーザーに複数権限セットを割り当てるメソッド
    public static void assignPermissionSets(User user, Set<String> permissionSetNames){
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();

        List<PermissionSet> permissionSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :permissionSetNames
        ];

        for(PermissionSet ps : permissionSets) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = user.Id,
                PermissionSetId = ps.Id
            ));
        }

        Assert.areEqual(permissionSetNames.size(),permissionSets.size(),'指定したPermission Setがすべて存在すること');

        insert assignments;
    }

    //テスト取引先を1件作成するメソッド
    public static Account createTestAccount(String accountName, Id ownerId){
        Account acc = new Account(
            Name = accountName
        );

        if(ownerId != null){
            acc.OwnerId = ownerId;
        }

        insert acc;
        return acc;

    }

    //テスト取引先を複数件作成するメソッド
    public static List<Account> createTestAccounts(Integer numAccts, Id ownerId){
        List<Account> accts = new List<Account>();

        if(numAccts == null || numAccts <= 0){
            return accts;
        }

        for(Integer i = 0 ; i < numAccts ; i++){
            Account acc = new Account(
                Name = 'テスト取引先' + i
            );

            if(ownerId != null){
                acc.OwnerId = ownerId;
            }

            accts.add(acc);
        }

        insert accts;
        return accts;
    }

    //テストケースを1件返すメソッド
    public static Case buildTestCase(Id accountId, String status ,Id ownerId){
        Case c = new Case(
            AccountId = accountId,
            Status = status
        );

        if(ownerId != null){
            c.OwnerId = ownerId;
        }

        return c;
    }


}
