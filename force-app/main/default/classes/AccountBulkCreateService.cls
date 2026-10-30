/**
 * 複数の新規Account候補をUSER_MODEで一括登録します。
 * 正常に結果を返す場合、入力と同じ件数・順序の結果を返します。
 */
public with sharing class AccountBulkCreateService {

    public enum ProcessingMode {
        ALL_OR_NONE,
        PARTIAL_SUCCESS
    }

    public enum AccountCreateErrorType {
        INPUT_VALIDATION,
        DML
    }

    public class AccountCreateError {
        public AccountCreateErrorType type { get; set; }
        public String message { get; set; }
        public System.StatusCode statusCode { get; set; }
        public List<String> fields { get; set; }
    }

    public class AccountCreateResult {
        public Integer inputIndex { get; set; }
        public Boolean success { get; set; }
        public Id accountId { get; set; }
        public List<AccountCreateError> errors { get; set; }
    }

    public class InvalidAccountCreateRequestException  extends Exception {
    }

    /**
     * 指定された処理モードでAccountを登録します。
     *
     * @param accounts 新規作成するAccount候補
     * @param mode 全件成功または部分成功の処理方針
     * @return 元入力と同じ位置に対応する作成結果
     * @throws InvalidAccountCreateRequestException 入力契約に違反した場合
     */
    public static List<AccountCreateResult> createAccounts( List<Account> accounts, ProcessingMode mode ){
        validateRequest(accounts, mode);

        if ( accounts.isEmpty() ){
            return new List<AccountCreateResult>();
        }

        //enumをDatabase.insert用のBooleanへ変換
        Boolean allOrNothing =
            mode == ProcessingMode.ALL_OR_NONE;

        AccountCreatePreparation preparation = prepareAccounts( accounts, allOrNothing );

        if( preparation.dmlAccounts.isEmpty() ){
            return preparation.results;
        }

        //Accountのinsert
        List<Database.SaveResult> saveResults = insertAccountsInUserMode( preparation.dmlAccounts, allOrNothing );

        applySaveResults( preparation, saveResults );

        return preparation.results;
    }

    //共通化処理


    private static void validateRequest( List<Account> accounts, ProcessingMode mode){
        //accountsのnull検証
        if( accounts == null ){
            throw new InvalidAccountCreateRequestException (
                'Input Account list must not be null.'
            );
        }

        //modeのnull検証
        if( mode == null ){
            throw new InvalidAccountCreateRequestException (
                'ProcessingMode must not be null.'
            );
        }
    }

    //準備結果クラス
    private class AccountCreatePreparation {
        List<AccountCreateResult> results = new List<AccountCreateResult>();
        List<Account> dmlAccounts = new List<Account>();
        // dmlInputIndexes[dmlIndex]に、元入力Listのindexを保持する
        List<Integer> dmlInputIndexes = new List<Integer>();
    }

    private static AccountCreatePreparation prepareAccounts( List<Account> accounts, Boolean allOrNothing ){
        AccountCreatePreparation preparation = new AccountCreatePreparation();
        //元入力と同じ件数の枠を用意
        for( Integer i = 0; i < accounts.size(); i++ ){
            preparation.results.add(null);
        }

        for( Integer inputIndex = 0; inputIndex < accounts.size(); inputIndex++ ){
            Account acc = accounts[inputIndex];

            //List内のnull
            if( acc == null ){
                if( allOrNothing ){
                    throw new InvalidAccountCreateRequestException (
                        'Input Account must not be null. inputIndex=' + String.valueOf(inputIndex)
                    );
                } else {

                    preparation.results[inputIndex] = createInputValidationFailureResult(inputIndex, 'Input Account must not be null.', new List<String>() );

                    continue;
                }
            }

            //Id付のAccount
            if( acc.Id != null ){
                if( allOrNothing ){
                    throw new InvalidAccountCreateRequestException (
                        'Account.Id must be null for create operations. inputIndex=' + String.valueOf(inputIndex)
                    );
                } else {

                    preparation.results[inputIndex] = createInputValidationFailureResult(inputIndex, 'Account.Id must be null for create operations.', new List<String>{ 'Id' } );

                    continue;
                }
            }

            // DML成功時に呼出元のAccountへIdを設定しないため、cloneを登録する
            preparation.dmlAccounts.add(acc.clone(false,false,false,false));
            //同時にinputIndexをdmlInputIndexesへ追加
            preparation.dmlInputIndexes.add(inputIndex);
        }
        return preparation;
    }

    //失敗結果
    private static AccountCreateResult createInputValidationFailureResult( Integer inputIndex, String message, List<String> fields ){
        AccountCreateResult result = new AccountCreateResult();
        result.inputIndex = inputIndex;
        result.success = false;
        result.accountId = null;
        result.errors = new List<AccountCreateError>();

        AccountCreateError error = new AccountCreateError();
        error.type = AccountCreateErrorType.INPUT_VALIDATION;
        error.message = message;
        error.statusCode = null;
        error.fields = fields;

        result.errors.add(error);
        return result;
    }

    //DML実行
    private static List<Database.SaveResult> insertAccountsInUserMode( List<Account> dmlAccounts, Boolean allOrNothing ){

        List<Database.SaveResult> saveResults = Database.insert( dmlAccounts, allOrNothing, System.AccessLevel.USER_MODE );
        return saveResults;
    }

    private static void applySaveResults( AccountCreatePreparation preparation, List<Database.SaveResult> saveResults ){

        for( Integer dmlIndex = 0; dmlIndex < saveResults.size(); dmlIndex++ ){
            Database.SaveResult saveResult = saveResults[dmlIndex];
            Integer inputIndex = preparation.dmlInputIndexes[dmlIndex];

            if( saveResult.isSuccess() ){
                AccountCreateResult result = new AccountCreateResult();
                result.inputIndex = inputIndex;
                result.success = true;
                result.accountId = saveResult.getId();
                result.errors = new List<AccountCreateError>();

                preparation.results[inputIndex] = result;
            } else {
                AccountCreateResult result = new AccountCreateResult();
                result.inputIndex = inputIndex;
                result.success = false;
                result.accountId = null;
                result.errors = new List<AccountCreateError>();

                for ( Database.Error databaseError : saveResult.getErrors() ) {
                    AccountCreateError error = new AccountCreateError();
                    error.type = AccountCreateErrorType.DML;
                    error.message = databaseError.getMessage();
                    error.statusCode = databaseError.getStatusCode();
                    error.fields = databaseError.getFields();

                    result.errors.add(error);
                }

                preparation.results[inputIndex] = result;
            }
        }
    }
}