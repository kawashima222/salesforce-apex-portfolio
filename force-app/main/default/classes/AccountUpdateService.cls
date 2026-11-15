public with sharing class AccountUpdateService {
    private AccountUpdateService() {
    }

    public static AccountUpdateResponse updateAccountsWithUpdatableFields(List<Account> accounts){

        validateUpdateCandidates(accounts);

        if(accounts.isEmpty()){
            return new AccountUpdateResponse(new Set<String>() ,new List<AccountUpdateItemResult>());
        }

        //セキュリティ
        AccountUpdatePreparation preparation = prepareUpdatableAccounts(accounts);

        Database.SaveResult[] saveResults = executePartialUpdate(preparation.sanitizedAccounts);

        List<AccountUpdateItemResult> results = convertSaveResults(saveResults, accounts);

        return new AccountUpdateResponse(preparation.removedFields, results);
    }

    public class AccountUpdateResponse {
        public Set<String> removedFields { get; private set; }
        public List<AccountUpdateItemResult> results { get; private set; }

        public AccountUpdateResponse(
            Set<String> removedFields,
            List<AccountUpdateItemResult> results
        ){
            this.removedFields = removedFields;
            this.results = results;
        }
    }

    public class AccountUpdateItemResult {
        public Integer inputIndex { get; private set; }
        public Id accountId { get; private set; }
        public Boolean success { get; private set; }
        public List<AccountUpdateError> errors { get; private set; }

        public AccountUpdateItemResult(
            Integer inputIndex,
            Id accountId,
            Boolean success,
            List<AccountUpdateError> errors
        ){
            this.inputIndex = inputIndex;
            this.accountId = accountId;
            this.success = success;
            this.errors = errors;
        }
    }

    public class AccountUpdateError {
        public System.StatusCode statusCode { get; private set; }
        public String message { get; private set; }
        public List<String> fields { get; private set; }

        public AccountUpdateError(
            System.StatusCode statusCode,
            String message,
            List<String> fields
        ){
            this.statusCode = statusCode;
            this.message = message;
            this.fields = fields;
        }
    }

    private class AccountUpdatePreparation {
        private List<Account> sanitizedAccounts;
        private Set<String> removedFields;

        private AccountUpdatePreparation (
            List<Account> sanitizedAccounts,
            Set<String> removedFields
        ){
            this.sanitizedAccounts = sanitizedAccounts;
            this.removedFields = removedFields;
        }
    }



    //入力検証
    private static void validateUpdateCandidates(List<Account> accounts){
        if(accounts == null){
            throw new IllegalArgumentException('Account update candidate list must not be null.');
        }

        Map<Id, Integer> firstInputIndexById = new Map<Id, Integer>();

        for(Integer index = 0 ; index < accounts.size() ; index++){
            Account accountRecord = accounts[index];

            if(accountRecord == null){
                throw new IllegalArgumentException('Account update candidate must not be null. inputIndex=' + index);
            }

            if(accountRecord.Id == null){
                throw new IllegalArgumentException('Account.Id must not be null for update operations. inputIndex=' + index);
            }

            if(accountRecord.Id.getSObjectType() != Account.SObjectType){
                throw new IllegalArgumentException('Account.Id must belong to the Account object. inputIndex=' + index);
            }

            if(firstInputIndexById.containsKey(accountRecord.Id)){
                Integer firstInputIndex = firstInputIndexById.get(accountRecord.Id);

                throw new IllegalArgumentException('Duplicate Account.Id is not allowed. firstInputIndex=' + firstInputIndex + ', duplicateInputIndex=' + index);
            }

            firstInputIndexById.put(accountRecord.Id, index);
        }
    }

    //セキュリティ
    private static AccountUpdatePreparation prepareUpdatableAccounts(List<Account> accounts){
        SObjectAccessDecision decision = Security.stripInaccessible(System.AccessType.UPDATABLE, accounts,true);

        List<Account> sanitizedAccounts = (List<Account>)decision.getRecords();
        Map<String,Set<String>> removedFieldsMap = decision.getRemovedFields();
        Set<String> removedFields = new Set<String>();

        if( removedFieldsMap.containsKey('Account')){
            removedFields.addAll(removedFieldsMap.get('Account'));
        }

        return new AccountUpdatePreparation(sanitizedAccounts ,removedFields);
    }

    private static Database.SaveResult[] executePartialUpdate(List<Account> sanitizedAccounts){
        Database.SaveResult[] saveResults = Database.update(sanitizedAccounts ,false ,System.AccessLevel.USER_MODE);
        return saveResults;
    }

    private static List<AccountUpdateItemResult> convertSaveResults(Database.SaveResult[] saveResults ,List<Account> originalAccounts){
        List<AccountUpdateItemResult> results = new List<AccountUpdateItemResult>();
        for(Integer index = 0; index < saveResults.size(); index++){

            Database.SaveResult sr = saveResults[index];
            Integer inputIndex = index;
            Id accountId = originalAccounts[index].Id;
            Boolean success = sr.isSuccess();
            List<AccountUpdateError> errors = new List<AccountUpdateError>();

            if(!sr.isSuccess()){
                for(Database.Error err : sr.getErrors()){
                    errors.add(new AccountUpdateError(
                        err.getStatusCode(),
                        err.getMessage(),
                        err.getFields()
                    ));
                }
            }
            results.add(new AccountUpdateItemResult(inputIndex,accountId,success,errors));
        }
        return results;
    }
}
