@IsTest
private class TriggerHandlerTest {

    private static final Integer BEFORE_INSERT_INDEX = 0;
    private static final Integer BEFORE_UPDATE_INDEX = 1;
    private static final Integer BEFORE_DELETE_INDEX = 2;
    private static final Integer AFTER_INSERT_INDEX = 3;
    private static final Integer AFTER_UPDATE_INDEX = 4;
    private static final Integer AFTER_DELETE_INDEX = 5;
    private static final Integer AFTER_UNDELETE_INDEX = 6;

    @IsTest
    static void run_beforeInsert_callsBeforeInsert() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.BEFORE_INSERT);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            BEFORE_INSERT_INDEX,
            1,
            'before insert'
        );
    }

    @IsTest
    static void run_afterInsert_callsAfterInsert() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.AFTER_INSERT);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            AFTER_INSERT_INDEX,
            1,
            'after insert'
        );
    }

    @IsTest
    static void run_beforeUpdate_callsBeforeUpdate() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.BEFORE_UPDATE);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            BEFORE_UPDATE_INDEX,
            1,
            'before update'
        );
    }

    @IsTest
    static void run_afterUpdate_callsAfterUpdate() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.AFTER_UPDATE);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            AFTER_UPDATE_INDEX,
            1,
            'after update'
        );
    }

    @IsTest
    static void run_beforeDelete_callsBeforeDelete() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.BEFORE_DELETE);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            BEFORE_DELETE_INDEX,
            1,
            'before delete'
        );
    }

    @IsTest
    static void run_afterDelete_callsAfterDelete() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.AFTER_DELETE);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            AFTER_DELETE_INDEX,
            1,
            'after delete'
        );
    }

    @IsTest
    static void run_afterUndelete_callsAfterUndelete() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.AFTER_UNDELETE);

        handler.run();

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            AFTER_UNDELETE_INDEX,
            1,
            'after undelete'
        );
    }

    @IsTest
    static void run_outsideTrigger_throwsException() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        Boolean expectedExceptionThrown = false;
        String actualMessage;

        try {
            handler.run();
        } catch (TriggerHandler.TriggerHandlerException exceptionValue) {
            expectedExceptionThrown = true;
            actualMessage = exceptionValue.getMessage();
        } catch (Exception exceptionValue) {
            Assert.fail('Unexpected exception type: ' + exceptionValue.getTypeName());
        }

        Assert.isTrue(
            expectedExceptionThrown,
            'Running outside Trigger execution must throw TriggerHandlerException.'
        );
        Assert.areEqual(
            'Trigger handler called outside of Trigger execution',
            actualMessage,
            'The outside-Trigger exception message does not match the contract.'
        );
        assertNoHooksCalled(handler.getHookCounts(), 'outside Trigger execution');
    }

    @IsTest
    static void run_whenBypassed_skipsExecution() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.BEFORE_UPDATE);
        String handlerName = getHandlerName(handler);

        try {
            TriggerHandler.bypass(handlerName);
            Assert.isTrue(
                TriggerHandler.isBypassed(handlerName),
                'The Handler must be marked as bypassed before run().'
            );

            handler.run();
        } finally {
            TriggerHandler.clearBypass(handlerName);
        }

        Assert.isFalse(
            TriggerHandler.isBypassed(handlerName),
            'The bypass state must be cleared after the test.'
        );
        assertNoHooksCalled(handler.getHookCounts(), 'bypassed execution');
    }

    @IsTest
    static void run_afterClearBypass_executes() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.AFTER_UPDATE);
        String handlerName = getHandlerName(handler);

        try {
            handler.setMaxLoopCount(1);
            TriggerHandler.bypass(handlerName);
            Assert.isTrue(
                TriggerHandler.isBypassed(handlerName),
                'The Handler must be marked as bypassed before clearBypass().'
            );

            handler.run();
            assertNoHooksCalled(handler.getHookCounts(), 'execution before clearBypass()');

            TriggerHandler.clearBypass(handlerName);
            Assert.isFalse(
                TriggerHandler.isBypassed(handlerName),
                'clearBypass() must remove the Handler from the bypass set.'
            );

            handler.run();
        } finally {
            TriggerHandler.clearBypass(handlerName);
            handler.clearMaxLoopCount();
        }

        Assert.isFalse(
            TriggerHandler.isBypassed(handlerName),
            'The Handler must remain outside the bypass set after cleanup.'
        );
        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            AFTER_UPDATE_INDEX,
            1,
            'after update following clearBypass()'
        );
    }

    @IsTest
    static void bypass_isSeparateForEachHandler() {
        RecordingTriggerHandler firstHandler = new RecordingTriggerHandler();
        SecondaryRecordingTriggerHandler secondHandler = new SecondaryRecordingTriggerHandler();
        setTriggerContext(firstHandler, TriggerHandler.TriggerContext.BEFORE_UPDATE);
        setTriggerContext(secondHandler, TriggerHandler.TriggerContext.BEFORE_UPDATE);
        String firstHandlerName = getHandlerName(firstHandler);
        String secondHandlerName = getHandlerName(secondHandler);

        Assert.areNotEqual(
            firstHandlerName,
            secondHandlerName,
            'The two test Handler classes must have different Handler names.'
        );

        try {
            TriggerHandler.bypass(firstHandlerName);
            Assert.isTrue(
                TriggerHandler.isBypassed(firstHandlerName),
                'The first Handler must be bypassed.'
            );
            Assert.isFalse(
                TriggerHandler.isBypassed(secondHandlerName),
                'Bypassing the first Handler must not bypass the second Handler.'
            );

            firstHandler.run();
            secondHandler.run();
        } finally {
            TriggerHandler.clearBypass(firstHandlerName);
        }

        Assert.isFalse(
            TriggerHandler.isBypassed(firstHandlerName),
            'The first Handler bypass state must be cleared after the test.'
        );
        assertNoHooksCalled(firstHandler.getHookCounts(), 'the bypassed first Handler');
        assertOnlyExpectedHookCalled(
            secondHandler.getHookCounts(),
            BEFORE_UPDATE_INDEX,
            1,
            'the non-bypassed second Handler'
        );
    }

    @IsTest
    static void run_withinLoopLimit_executes() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.BEFORE_UPDATE);

        try {
            handler.setMaxLoopCount(2);
            handler.run();
            handler.run();
        } finally {
            handler.clearMaxLoopCount();
        }

        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            BEFORE_UPDATE_INDEX,
            2,
            'two executions within the loop limit'
        );
    }

    @IsTest
    static void run_overLoopLimit_throwsException() {
        RecordingTriggerHandler handler = new RecordingTriggerHandler();
        setTriggerContext(handler, TriggerHandler.TriggerContext.BEFORE_INSERT);
        String handlerName = getHandlerName(handler);
        Boolean expectedExceptionThrown = false;
        String actualMessage;

        try {
            handler.setMaxLoopCount(1);
            handler.run();

            try {
                handler.run();
            } catch (TriggerHandler.TriggerHandlerException exceptionValue) {
                expectedExceptionThrown = true;
                actualMessage = exceptionValue.getMessage();
            } catch (Exception exceptionValue) {
                Assert.fail('Unexpected exception type: ' + exceptionValue.getTypeName());
            }
        } finally {
            handler.clearMaxLoopCount();
        }

        Assert.isTrue(
            expectedExceptionThrown,
            'The second run() must throw when the maximum loop count is one.'
        );
        Assert.areEqual(
            'Maximum loop count of 1 reached in ' + handlerName,
            actualMessage,
            'The loop-limit exception message does not match the contract.'
        );
        assertOnlyExpectedHookCalled(
            handler.getHookCounts(),
            BEFORE_INSERT_INDEX,
            1,
            'execution stopped before the second hook call'
        );
    }

    @IsTest
    static void loopCount_isSeparateForEachHandler() {
        RecordingTriggerHandler firstHandler = new RecordingTriggerHandler();
        SecondaryRecordingTriggerHandler secondHandler = new SecondaryRecordingTriggerHandler();
        setTriggerContext(firstHandler, TriggerHandler.TriggerContext.BEFORE_UPDATE);
        setTriggerContext(secondHandler, TriggerHandler.TriggerContext.BEFORE_UPDATE);
        String firstHandlerName = getHandlerName(firstHandler);
        String secondHandlerName = getHandlerName(secondHandler);
        Boolean firstExceptionThrown = false;
        Boolean secondExceptionThrown = false;
        String firstMessage;
        String secondMessage;

        try {
            firstHandler.setMaxLoopCount(1);
            secondHandler.setMaxLoopCount(1);

            firstHandler.run();
            try {
                firstHandler.run();
            } catch (TriggerHandler.TriggerHandlerException exceptionValue) {
                firstExceptionThrown = true;
                firstMessage = exceptionValue.getMessage();
            } catch (Exception exceptionValue) {
                Assert.fail('Unexpected first Handler exception type: ' + exceptionValue.getTypeName());
            }

            secondHandler.run();
            try {
                secondHandler.run();
            } catch (TriggerHandler.TriggerHandlerException exceptionValue) {
                secondExceptionThrown = true;
                secondMessage = exceptionValue.getMessage();
            } catch (Exception exceptionValue) {
                Assert.fail('Unexpected second Handler exception type: ' + exceptionValue.getTypeName());
            }
        } finally {
            firstHandler.clearMaxLoopCount();
            secondHandler.clearMaxLoopCount();
        }

        Assert.isTrue(firstExceptionThrown, 'The first Handler must enforce its own loop limit.');
        Assert.isTrue(secondExceptionThrown, 'The second Handler must enforce its own loop limit.');
        Assert.areEqual(
            'Maximum loop count of 1 reached in ' + firstHandlerName,
            firstMessage,
            'The first Handler loop-limit message does not match the contract.'
        );
        Assert.areEqual(
            'Maximum loop count of 1 reached in ' + secondHandlerName,
            secondMessage,
            'The second Handler loop-limit message does not match the contract.'
        );
        assertOnlyExpectedHookCalled(
            firstHandler.getHookCounts(),
            BEFORE_UPDATE_INDEX,
            1,
            'the first Handler loop limit'
        );
        assertOnlyExpectedHookCalled(
            secondHandler.getHookCounts(),
            BEFORE_UPDATE_INDEX,
            1,
            'the second Handler loop limit'
        );
    }

    private static String getHandlerName(TriggerHandler handler) {
        return String.valueOf(handler).substringBefore(':');
    }

    private static void setTriggerContext(
        TriggerHandler handler,
        TriggerHandler.TriggerContext context
    ) {
        handler.setTriggerContextForTest(context);
    }

    private static void assertNoHooksCalled(List<Integer> hookCounts, String scenario) {
        assertOnlyExpectedHookCalled(hookCounts, null, 0, scenario);
    }

    private static void assertOnlyExpectedHookCalled(
        List<Integer> hookCounts,
        Integer expectedHookIndex,
        Integer expectedCallCount,
        String scenario
    ) {
        Assert.areEqual(7, hookCounts.size(), 'Seven hook counters are required.');

        for (Integer hookIndex = 0; hookIndex < hookCounts.size(); hookIndex++) {
            Integer expectedCount = hookIndex == expectedHookIndex ? expectedCallCount : 0;
            Assert.areEqual(
                expectedCount,
                hookCounts[hookIndex],
                'Unexpected hook count for ' + scenario + ' at hookIndex=' + hookIndex + '.'
            );
        }
    }

    private class RecordingTriggerHandler extends TriggerHandler {
        private Integer beforeInsertCalls = 0;
        private Integer beforeUpdateCalls = 0;
        private Integer beforeDeleteCalls = 0;
        private Integer afterInsertCalls = 0;
        private Integer afterUpdateCalls = 0;
        private Integer afterDeleteCalls = 0;
        private Integer afterUndeleteCalls = 0;

        protected override void beforeInsert() {
            beforeInsertCalls++;
        }

        protected override void beforeUpdate() {
            beforeUpdateCalls++;
        }

        protected override void beforeDelete() {
            beforeDeleteCalls++;
        }

        protected override void afterInsert() {
            afterInsertCalls++;
        }

        protected override void afterUpdate() {
            afterUpdateCalls++;
        }

        protected override void afterDelete() {
            afterDeleteCalls++;
        }

        protected override void afterUndelete() {
            afterUndeleteCalls++;
        }

        public List<Integer> getHookCounts() {
            return new List<Integer>{
                beforeInsertCalls,
                beforeUpdateCalls,
                beforeDeleteCalls,
                afterInsertCalls,
                afterUpdateCalls,
                afterDeleteCalls,
                afterUndeleteCalls
            };
        }
    }

    private class SecondaryRecordingTriggerHandler extends TriggerHandler {
        private Integer beforeInsertCalls = 0;
        private Integer beforeUpdateCalls = 0;
        private Integer beforeDeleteCalls = 0;
        private Integer afterInsertCalls = 0;
        private Integer afterUpdateCalls = 0;
        private Integer afterDeleteCalls = 0;
        private Integer afterUndeleteCalls = 0;

        protected override void beforeInsert() {
            beforeInsertCalls++;
        }

        protected override void beforeUpdate() {
            beforeUpdateCalls++;
        }

        protected override void beforeDelete() {
            beforeDeleteCalls++;
        }

        protected override void afterInsert() {
            afterInsertCalls++;
        }

        protected override void afterUpdate() {
            afterUpdateCalls++;
        }

        protected override void afterDelete() {
            afterDeleteCalls++;
        }

        protected override void afterUndelete() {
            afterUndeleteCalls++;
        }

        public List<Integer> getHookCounts() {
            return new List<Integer>{
                beforeInsertCalls,
                beforeUpdateCalls,
                beforeDeleteCalls,
                afterInsertCalls,
                afterUpdateCalls,
                afterDeleteCalls,
                afterUndeleteCalls
            };
        }
    }
}
