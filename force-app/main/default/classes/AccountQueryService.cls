public with sharing class AccountQueryService {
    private AccountQueryService() {
    }

    public static List<Account> findReadableAccountsByIds(Set<Id> accountIds){
        validateAccountIds(accountIds);

        if(accountIds.isEmpty()){
            return new List<Account>();
        }

        List<Account> readableAccounts = [
            SELECT Id, Name, AccountNumber
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
            ORDER BY AccountNumber ASC NULLS LAST, Id ASC
        ];

        return readableAccounts;
    }

    //入力検証
    private static void validateAccountIds(Set<Id> accountIds){
        if(accountIds == null){
            throw new IllegalArgumentException('Account ID set must not be null.');
        }
        if(accountIds.contains(null)){
            throw new IllegalArgumentException('Account ID set must not contain null.');
        }
        for(Id recordId : accountIds){
            if(recordId.getSObjectType() != Account.SObjectType){
                throw new IllegalArgumentException('Account ID set must contain only Account IDs.');
            }
        }
    }

}