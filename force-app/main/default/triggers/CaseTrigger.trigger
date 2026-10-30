trigger CaseTrigger on Case (before update, after update) {
    new CaseTriggerhandler().run();
}