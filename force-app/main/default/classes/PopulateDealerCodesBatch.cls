global class PopulateDealerCodesBatch implements Database.Batchable<sObject>, Database.Stateful {
    String query = 'SELECT Premise_Code__c,Primary_Premise_Name__c FROM User WHERE Premise_Code__c != null';
    global Map<String, String> dealers = new Map<String, String>();
    global integer partnerUsers = 0;
    
    public Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<sObject> scope){
    	partnerUsers += scope.size();    
        for (User u: (List<User>) scope) {
            dealers.put(u.Premise_Code__c, u.Primary_Premise_Name__c);
        }
    }
    
    public void finish(Database.BatchableContext BC){
    	List<Dealer__c> ds = new List<Dealer__c>();
        for (String code : dealers.keySet()) {
            Dealer__c d = new Dealer__c();
            d.Code__c = code;
            d.Name = dealers.get(code) + ' (' + code + ')';
            ds.add(d);
        }
        try {
    		upsert ds Code__c;
		} catch (DmlException e) {
    		// Process exception here
		}
        system.debug('Number of partner users are ' + partnerUsers) ; 
        system.debug('Number of unique dealers are ' + ds.size()); 
    }
}