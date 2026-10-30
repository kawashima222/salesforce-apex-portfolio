public with sharing class CaseSelector {

    public static List<Case> getCasesByAccountsAndStatuses(Set<Id> accountIds,Set<String> statuses){

        List<Case> result = new List<Case>();

        if(accountIds == null || accountIds.isEmpty() || statuses == null || statuses.isEmpty()){
            return result;
        }

        Set<Id> validAccountIds = new Set<Id>(accountIds);
        validAccountIds.remove(null);
        if(validAccountIds.isEmpty()) return result;

        Set<String> validStatuses = new Set<String>();
        for(String status : statuses) {
            if(!String.isBlank(status)){
                validStatuses.add(status);
            }
        }
        if(validStatuses.isEmpty()) return result;


        result = [
            SELECT Id, AccountId, Status,CreatedDate, Account.Name 
            FROM Case 
            WHERE AccountId IN :validAccountIds AND Status IN :validStatuses
            WITH USER_MODE
            ORDER BY accountId ASC, CreatedDate ASC, Id ASC
        ];

        return result;
    }
}