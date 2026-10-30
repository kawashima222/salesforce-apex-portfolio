/**
 * Provides common trigger-context dispatch, bypass, and loop-count management.
 */
public virtual with sharing class TriggerHandler {

    // ============================================================
    // Types and state
    // ============================================================
    @TestVisible
    private enum TriggerContext{
        BEFORE_INSERT,
        BEFORE_UPDATE,
        BEFORE_DELETE,
        AFTER_INSERT,
        AFTER_UPDATE,
        AFTER_DELETE,
        AFTER_UNDELETE
    }

    private static Set<String> bypassedHandlers = new Set<String>();
    //setMaxLoopCountにてLoopCountを設定
    private static Map<String,LoopCount> loopCountMap = new Map<String,LoopCount>();

    //Salesforceの`Trigger.operationType`を、`run()`がdispatchする内部contextへ対応付ける。
    private TriggerContext context;
    private Boolean isTriggerExecuting;

    // ============================================================
    // Initialization
    // ============================================================
    /**
     * Initializes the handler from the current Salesforce trigger context.
     */
    public TriggerHandler() {
        this.setTriggerContext();
    }

    private void setTriggerContext(){
        if( !Trigger.isExecuting ){
            isTriggerExecuting = false;
            context = null;
            return;
        }else{
            isTriggerExecuting = true;
        }

        if( isTriggerExecuting ){
            switch on Trigger.operationType {
                when BEFORE_INSERT {
                    context = TriggerContext.BEFORE_INSERT;
                }
                when BEFORE_UPDATE {
                    context = TriggerContext.BEFORE_UPDATE;
                }
                when BEFORE_DELETE {
                    context = TriggerContext.BEFORE_DELETE;
                }
                when AFTER_INSERT {
                    context = TriggerContext.AFTER_INSERT;
                }
                when AFTER_UPDATE {
                    context = TriggerContext.AFTER_UPDATE;
                }
                when AFTER_DELETE {
                    context = TriggerContext.AFTER_DELETE;
                }
                when AFTER_UNDELETE {
                    context = TriggerContext.AFTER_UNDELETE;
                }
                when else{
                    throw new TriggerHandler.TriggerHandlerException('Unsupported Trigger context: '+ Trigger.operationType);
                }
            }
        }
    }

    // ============================================================
    // Handler execution
    // ============================================================
    /**
     * Validates the execution and dispatches it to the matching context hook.
     */
    public void run(){
        //トリガー外からの実行なら例外、bypass中なら終了
        if(!validateRun()){
            return;
        }

        addLoopCount();

        switch on context {
            when BEFORE_INSERT {
                this.beforeInsert();
            }
            when BEFORE_UPDATE {
                this.beforeUpdate();
            }
            when AFTER_INSERT {
                this.afterInsert();
            }
            when AFTER_UPDATE {
                this.afterUpdate();
            }
            when BEFORE_DELETE {
                this.beforeDelete();
            }
            when AFTER_DELETE {
                this.afterDelete();
            }
            when AFTER_UNDELETE {
                this.afterUndelete();
            }
        }
    }

    //Trigger外なら例外、bypass中ならfalse、それ以外はtrue
    private Boolean validateRun(){
        if(!this.isTriggerExecuting){
            throw new TriggerHandlerException('Trigger handler called outside of Trigger execution');
        }
        //
        if(isBypassed(getHandlerName())){
            return false;
        }
        return true;
    }

    //設定済みHandlerのcountを増やし、上限超過なら例外
    private void addLoopCount(){
        string handlerName = getHandlerName();
        //setMaxLoopCount()が呼ばれているか確認
        if(TriggerHandler.loopCountMap.containsKey(handlerName)){
            //trueなら上限超過
            Boolean exceede = loopCountMap.get(handlerName).increment();
            if(exceede){
                Integer max = TriggerHandler.loopCountMap.get(handlerName).getMax();
                throw new TriggerHandlerException('Maximum loop count of ' + max + ' reached in ' + handlerName);
            }
        }
    }

    //実行中インスタンスから具体的Handler名を取得
    private string getHandlerName(){
        return String.valueOf(this)
            .substringBefore(':');
    }

    // ============================================================
    // Loop count management
    // ============================================================
    /**
     * Sets the maximum number of executions for the current handler instance.
     * The existing execution count is preserved.
     *
     * @param max Maximum executions, or -1 for no limit.
     */
    public void setMaxLoopCount(Integer max){
        validateMaxLoopCount(max);

        String handlerName = getHandlerName();
        if(!TriggerHandler.loopCountMap.containsKey(handlerName)){
            TriggerHandler.loopCountMap.put(handlerName,new LoopCount(max));
        }else{
            TriggerHandler.loopCountMap.get(handlerName).setMax(max);
        }
    }

    /**
     * Removes the execution limit for the current handler while preserving its count.
     */
    public void clearMaxLoopCount(){
        TriggerHandler.loopCountMap.get(getHandlerName())?.setMax(-1);
    }

    //bypass API共通のHandler名検証
    private static Void validateHandlerName(String handlerName){
        if(String.isBlank(handlerName)){
            throw new IllegalArgumentException('Handler name must not be blank.');
        }
    }

    // ============================================================
    // Bypass management
    // ============================================================
    /**
     * Adds a handler to the transaction-scoped bypass set.
     *
     * @param handlerName Name of the handler to bypass.
     */
    public static void bypass(String handlerName){
        validateHandlerName(handlerName);
        TriggerHandler.bypassedHandlers.add(handlerName);
    }

    /**
     * Determines whether a handler is currently bypassed.
     *
     * @param handlerName Name of the handler to inspect.
     * @return true when the handler is bypassed; otherwise false.
     */
    public static Boolean isBypassed(String handlerName){
        validateHandlerName(handlerName);
        return TriggerHandler.bypassedHandlers.contains(handlerName);
    }

    /**
     * Removes a handler from the transaction-scoped bypass set.
     *
     * @param handlerName Name of the handler whose bypass is cleared.
     */
    public static void clearBypass(String handlerName){
        validateHandlerName(handlerName);
        TriggerHandler.bypassedHandlers.remove(handlerName);
    }

    //maxのnull・範囲検証
    private static void validateMaxLoopCount(Integer max){
        if(max == null){
            throw new IllegalArgumentException('Maximum loop count must not be null.');
        }
        if(max == 0 || max < -1){
            throw new IllegalArgumentException('Maximum loop count must be -1 or a positive integer.');
        }
    }

    // ============================================================
    // Trigger context hooks
    // ============================================================
    protected virtual void beforeInsert(){
    }

    protected virtual void beforeUpdate(){
    }

    protected virtual void beforeDelete(){
    }

    protected virtual void afterInsert(){
    }

    protected virtual void afterUpdate(){
    }

    protected virtual void afterDelete(){
    }

    protected virtual void afterUndelete(){
    }

    // ============================================================
    // Test support
    // ============================================================
    @TestVisible
    private void setTriggerContextForTest(TriggerContext context){
        if(context == null){
            throw new IllegalArgumentException('Trigger context must not be null.');
        }
        this.context = context;
        this.isTriggerExecuting = true;
    }

    // ============================================================
    // Supporting types
    // ============================================================
    @TestVisible
    private class LoopCount {
        private Integer max;
        private Integer count;

        /**
         * Initializes a loop counter with zero executions.
         *
         * @param max Maximum executions, or -1 for no limit.
         */
        public LoopCount(Integer max){
            this.max = max;
            this.count = 0;
        }

        /**
         * Increments the execution count and checks the configured limit.
         *
         * @return true when the updated count exceeds the maximum.
         */
        public Boolean increment(){
            this.count++;
            return this.exceeded();
        }

        /**
         * Determines whether the current count exceeds the maximum.
         *
         * @return true when the maximum has been exceeded.
         */
        public Boolean exceeded(){
            return max >= 0 && count > max;
        }

        /**
         * Returns the configured maximum execution count.
         *
         * @return Configured maximum execution count.
         */
        public Integer getMax(){
            return this.max;
        }

        /**
         * Returns the current execution count.
         *
         * @return Current execution count.
         */
        public Integer getCount(){
            return this.count;
        }

        /**
         * Replaces the maximum execution count without resetting the current count.
         *
         * @param max New maximum execution count.
         */
        public void setMax(Integer max){
            this.max = max;
        }
    }

    /**
     * Indicates invalid trigger-handler execution or a loop-limit violation.
     */
    public class TriggerHandlerException extends Exception {
    }
}
