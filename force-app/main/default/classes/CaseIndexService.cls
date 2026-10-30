public with sharing class CaseIndexService {
    public static Map<Id,List<Case>> groupOpenCasesByAccount(List<Case> caseList){
        //戻り値
        Map<Id,List<Case>> resultMap = new Map<Id,List<Case>>();
        if(caseList == null || caseList.isEmpty()) {
            return resultMap;
        }

        for(case currentCase  : caseList) {
            if(currentCase  == null || currentCase.AccountId == null || String.isBlank(currentCase.Status) || currentCase.Status == 'Closed' ){
                continue;
            }

            Id accountId = currentCase.AccountId;

            if(!resultMap.containsKey(accountId)){
                resultMap.put(accountId, new List<Case>());
            }

            resultMap.get(accountId).add(currentCase);

        }
        return resultMap;
    }
}