public class PCG_NotifyMembersOfNewContent {
    
    @InvocableMethod
    public static List<List<User>> membersToNotify(List<String> documentIds) {
        List<User> usersList = new List<User>();
        List<List<User>> usersListofLists = new List<List<User>>();
        List<Id> userIds = new List<Id>();
        Set<Id> userIdsSet = new Set<Id>();
        for (String documentId : documentIds) {
            List<ContentDocumentLink> cdls = new List<ContentDocumentLink>();
            List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();
            List<User> membersToNotify = new List<User>();
            List<Id> inList = new List<Id>();
            
            // A. Get list of Ids of all libraries containing this document and which are also shared to a PCG group
            cdls = [SELECT LinkedEntityId, LinkedEntity.Name FROM ContentDocumentLink WHERE ContentDocumentId = :documentId AND LinkedEntityId IN (SELECT ContentWorkspaceId FROM ContentWorkspaceMember WHERE Member.Name LIKE 'PCG%')];
            for (ContentDocumentLink cdl : cdls) {
                inList.add(cdl.LinkedEntityId);
            }
            system.debug(inList);
            
            // B. Get list of Group Ids of Groups associated with A
            if (inList.size() > 0) {
                cwms = [SELECT MemberId FROM ContentWorkspaceMember WHERE MemberType = 'G' AND Member.Name LIKE 'PCG%' AND ContentWorkspaceId IN :inList];
                inList.clear();
                for (ContentWorkspaceMember cwm : cwms) {
                    inList.add(cwm.MemberId);
                }
                system.debug(inList);
            }
            
            // C. Get list of Users who are members of B
            If (inList.size() > 0) {
                membersToNotify = [SELECT Id, Name, Email from User WHERE Id IN (SELECT UserOrGroupId FROM GroupMember WHERE GroupId IN :inList)]; 
            }
            
            // D. Add User Ids to Set (set to ensure uniqueness)
            for (User u : membersToNotify) {
                userIdsSet.add(u.Id);
                system.debug(u.Name);
            }
    	}
        userIds.addAll(userIdsSet);
        
        usersList = [SELECT Id, Name, Email FROM User WHERE Id IN :userIds];
        usersListofLists.add(usersList);
        return usersListofLists;
    }
    
    public static void newProfiledContent(List<ContentDocumentLink> cdls) {
		List<ContentDocumentLink> inScopeCdls = new List<ContentDocumentLink>();
        for (ContentDocumentLink cdl : cdls) {
            Id linkedEntityId = cdl.LinkedEntityId;
            Schema.SObjectType sobjectType = linkedEntityId.getSObjectType();
            if (sobjectType.getDescribe().getName() == 'ContentWorkspace') { // is the document in a library 
            	inScopeCdls.add(cdl);
            }
        }
        doInsertHistoryEntry(inScopeCdls);
    }
    
    public static void newProfiledContent(List<ContentVersion> cvs) {
    	List<id> documentIds = new List<id>();
        for (ContentVersion cv : cvs) {
            documentIds.add(cv.ContentDocumentId);
        }
        // doInsertHistoryEntry(documentIds);
    }
    
    public static void doInsertHistoryEntry(List<ContentDocumentLink> cdls) {
        List<PCG_Profiled_Content_History__c> pchs = new List<PCG_Profiled_Content_History__c>();
        Set<Id> setProfiledContentLibraryIds = getProfiledContentLibaryIds();
        Set<Id> inScopeCdlIds = new Set<Id>();
        List<ContentDocumentLink> inScopeCdls = new List<ContentDocumentLink>();
        for (ContentDocumentLink cdl : cdls) {
            system.debug('evaluating library id ' + cdl.LinkedEntityId);
            if (setProfiledContentLibraryIds.contains(cdl.LinkedEntityId)) {
                // The document has been added to a PCG library, so we'll create a history record from this CDL
                system.debug('library is PCG');
                inScopeCdlIds.add(cdl.id);
            } else {
                system.debug('library NOT PCG');
            }
        }
        if (inScopeCdlIds.size() > 0) {
            inScopeCdls = [SELECT Id, ContentDocument.Title, ContentDocumentId, ContentDocument.LatestPublishedVersion.VersionNumber, LinkedEntityId, LinkedEntity.Name FROM ContentDocumentLink WHERE Id IN :inScopeCdlIds];
            for (ContentDocumentLink cdl : inScopeCdls) {      
                PCG_Profiled_Content_History__c pch = new PCG_Profiled_Content_History__c();
                pch.Document_Id__c = cdl.ContentDocumentId;
                pch.Title__c = cdl.ContentDocument.Title;
                pch.Version__c = cdl.ContentDocument.LatestPublishedVersion.VersionNumber;    
                pch.Action__c = 'U';
                pch.Library_Id__c = cdl.LinkedEntityId;
                pch.Library_Name__c = cdl.LinkedEntity.Name;
                system.debug('history record is:');
                system.debug(pch);
                insert pch;
            }
        }
    }
    
    // Return set of Library Ids, where the library is associated with a PCG Group
    public static Set<id> getProfiledContentLibaryIds() {
    	Set<id> libraryIds = new Set<id>();
        List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();
        cwms = [SELECT ContentWorkspaceId FROM ContentWorkspaceMember WHERE Member.Name LIKE 'PCG%'];
        if (cwms.size() > 0) {
            for (ContentWorkspaceMember cwm : cwms) {
                libraryIds.add(cwm.ContentWorkspaceId);
            }
        }
        return libraryIds;
    }
    
    public static void notifyNewProfiledContent(List<PCG_Profiled_Content_History__c> pchs) {
        List<id> documentIds = new List<id>();
        for (PCG_Profiled_Content_History__c pch : pchs) {
            documentIds.add(pch.Document_Id__c);
        }
		doNotifyNewProfiledContent(documentIds);
    }
    
    public static void doNotifyNewProfiledContent(List<Id> documentIds) {          
        if (documentIds.size() > 0) {
            for (Id docId : documentIds) {
                List<List<User>> membersToNotifyListofList = new List<List<User>>();
                List<Id> docIds = new List<Id>();
                docIds.add(docId);
                membersToNotifyListofList = membersToNotify(docIds);
                List<User> theMembersToNotify = membersToNotifyListofList[0];
                ContentDocument cd = [SELECT Title, LatestPublishedVersionId FROM ContentDocument WHERE Id = :docId]; 
                for (User u : theMembersToNotify) {
                	createNotificationTask(u.Id, docId, cd.Title);
                }
            }
        }
    }
    
    public static void createNotificationTask(Id userId, Id documentId, String documentTitle) {          
        Task t = new Task();
        t.OwnerId = userId;	
        t.Status = 'Open';
        t.Priority = 'Low';
        t.Subject = 'New commercial content uploaded' + documentTitle;
        t.Description = 'New commercial content uploaded - ' + documentTitle;
        t.TaskCategory__c = 'Agent Activity';
        t.TaskSubCategory__c = 'To Do';
        t.ActivityDate = date.today();
        // t.WhatId = documentId;
        
        system.debug(t);
        // insert t;
        Database.DMLOptions dmlOptions = new Database.DMLOptions(); 
        dmlOptions.EmailHeader.TriggerUserEmail = TRUE; 
        
        Database.Insert(
            t, 
            dmlOptions
        );
 
    }

}