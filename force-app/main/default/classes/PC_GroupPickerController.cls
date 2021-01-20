public with sharing class PC_GroupPickerController {

    static final String ARCHIVE_LIBRARY_NAME = 'Profiled Content Archive';
    static final String ADMIN_GROUP_NAME = 'Profiled Content Admins Public Group';

    @AuraEnabled (cacheable=false)
    public static Boolean initAdmin(){
        // Share all content profile libraries with content admin public group (where not already)
        // shareProfiledContentLibrariesWithAdmins();
        return true;
    }

    @AuraEnabled (cacheable=true)
    public static List<Group> getGroups(){
        return [SELECT Name FROM Group WHERE Type = 'Regular' AND Name LIKE 'PCG %'];
    }

    @AuraEnabled
    public static List<Group> refreshGroups(){
        return getGroups();
    }

    @AuraEnabled (cacheable=false)
    public static Boolean addGroup(String groupName) {

        Boolean retval = false;
        
        List<String> groupNames = new List<String>();
        List<Group> groups = new List<Group>();
        List<ContentWorkspace> libraries = new List<ContentWorkspace>();
        List<ContentWorkspaceMember> shares = new List<ContentWorkspaceMember> ();

        system.debug('About to add group ' + groupName);
        groupNames.add(groupName);

        groups = createGroups(groupNames);
        if (groups.size() > 0) {
            libraries = createLibraries(groups);
            if (libraries.size() > 0) {
                shares = shareLibraries (libraries, groups);
                if (shares.size() > 0) {
                    retval = true;
                }
            }
        }
        system.debug('Completed add group ' + groupName);

        // ensure content admins have admin access to new library
        // shareProfiledContentLibrariesWithAdmins();

        return retval;
    }

    @AuraEnabled (cacheable=false)
    public static Boolean copyDealers(String sourceGroupName, String targetGroupName) {
        system.debug('About to copy dealers from ' + sourceGroupName + '->' + targetGroupName);
        List<Id> sourceDealerIds = new List<Id>();
        sourceDealerIds = getDealerIds(sourceGroupName);
        system.debug('Got ' + sourceDealerIds.size() + ' dealers from source group ');
        system.debug(sourceDealerIds);
        assignDealers('PCG ' + targetGroupName, sourceDealerIds);
        system.debug('Completed copy dealers from ' + sourceGroupName + '->' + targetGroupName);
        return true;
    }

    @AuraEnabled (cacheable=false)
    public static Boolean cloneGroup(String sourceGroupName, String targetGroupName) {

        Boolean retval = false;
        
        if (addGroup(targetGroupName)) {
            copyDealers(sourceGroupName, targetGroupName);
            retval = true;
        }
        return retval;
    }

    @AuraEnabled (cacheable=false)
    public static Boolean deleteGroup(String groupName) {

        Boolean retval = true;
        
        list<String> groupNames = new list<String>();
        groupNames.add(groupName);

        deleteLibraries(groupNames);
        deletePublicGroups(groupNames);

        return retval;
    }

    private static void deleteLibraries(List<String> groupNames) {
        List<ContentWorkspace> cws = new List<ContentWorkspace>();
        cws = [SELECT Id, Name, DeveloperName FROM ContentWorkspace WHERE Name IN :groupToLibraryNames(groupNames)];
        Integer numLibrariesToDelete = cws.size();
        if (numLibrariesToDelete > 0) {
            system.debug('Start - Deleting ' + numLibrariesToDelete + ' libraries and moving files to archive');
            doArchiveLibraryFiles(cws);
            doDeleteLibraries(cws);
            system.debug('Finish - Deleting ' + numLibrariesToDelete + ' libraries and moving files to archive');
        } else {
            system.debug('No libraries to delete');
        }
    }

    private static Boolean deletePublicGroups(List<String> groupNames) {
        Boolean retval = false;
        List<Group> gs = new List<Group>();
        gs = [SELECT Id FROM Group WHERE Name IN :groupNames];
        ID jobID = System.enqueueJob(new PC_DeleteGroupsQueueable(gs));
        System.debug('Group delete jobID'+jobID);
        retval = true;
        return retval;
    }

    private static List<String> groupToLibraryNames(List<String> groupNames) {
        List<String> libraryNames = new List<String>();
        for (String g : groupNames) {
            libraryNames.add(g.mid(4, 200));
        }
        return libraryNames;
    }
    // Move all files from Source Library to Archive library 
    private static Integer doArchiveLibraryFiles(List<ContentWorkspace> libraries) {
        Integer filesMoved = 0;

        // Find the Archive library (create it if it doesnt exist)
        ContentWorkspace archiveLibrary = getArchiveLibrary();
        if (archiveLibrary == null) {
            system.debug('No archive library found - ' + ARCHIVE_LIBRARY_NAME);
            return filesMoved;
        }
        // Move files from source library to archive library, one library at a time
        for (ContentWorkspace library : libraries) {
            Integer m = moveFiles(library, archiveLibrary);
            system.debug('Moved ' + m + ' files from ' + library.Name + ' to ' + archiveLibrary.Name);
            filesMoved += m;
        }

        system.debug('Moved total of ' + filesMoved + ' files ');
        return filesMoved;
    }

    private static ContentWorkspace getArchiveLibrary() {
        ContentWorkspace archive = null;
        List<ContentWorkspace> cws = [SELECT Id, Name FROM ContentWorkspace WHERE Name = :ARCHIVE_LIBRARY_NAME LIMIT 1];
        if (cws.size() == 1) {
            system.debug('Found archive library ' + ARCHIVE_LIBRARY_NAME);
            archive = cws[0];
        } else {
            
            system.debug('Creating archive library ' + ARCHIVE_LIBRARY_NAME);
            ContentWorkspace cw = new ContentWorkspace();
            cw.Description = 'Profiled content archive created by admin tool';
            cw.Name = ARCHIVE_LIBRARY_NAME;
            cw.DeveloperName = 'PCG_' + cw.Name.replace(' ', '_');
            try {
                insert cw;
                System.debug('*** PC_GroupPickerController.getArchiveLibrary *** created archive library');
            } catch(DmlException e) {
                System.debug('*** PC_GroupPickerController.getArchiveLibrary *** library creation failed: ' + e.getMessage());
            } 
            
            if (cw != null) {
                // Ensure content admin users have access to archive library
                ContentWorkspaceMember m = new ContentWorkspaceMember();
                ContentWorkspacePermission p = [SELECT Id FROM ContentWorkspacePermission WHERE Name = 'Library Administrator' LIMIT 1];
                m.ContentWorkspaceId = cw.Id;
                m.MemberId = createOneGroup (ADMIN_GROUP_NAME);
                m.ContentWorkspacePermissionId = p.Id;
                try {
                    insert m;
                    System.debug('*** PC_GroupPickerController.getArchiveLibrary *** shared archive library with admin public group');
                } catch(DmlException e) {
                    System.debug('*** PC_GroupPickerController.getArchiveLibrary *** library sharing failed: ' + e.getMessage());
                }
            }
            archive = cw;
        }
        return archive;
    }

    // Move files from source library to target
    // (Not as easy as it sounds!)
    private static Integer moveFiles(ContentWorkspace source, ContentWorkspace target) {
        Integer filesMoved = 0;
        
        List<ContentDocumentLink> lstImpactedContentDocumentLinks = new List<ContentDocumentLink>(); // List of ContentDocumentLinks that inform how the moves are made
        List<Id> filesToMoveIds = new List<Id>(); // List of Ids of the files (ContentDocument) in the source library that need to be moved to target
        Set<Id> filesToAddToTargetIds = new Set<Id>(); // List of Ids of the files (ContentDocument) that need to be linked to target
        List<Id> filesToReparentIds = new List<Id>(); // List of Ids of the files (ContentDocument) that need to be reparented to target
        
        List<ContentDocumentLink> filesToDeleteFromLibraries = new List<ContentDocumentLink>();
        List<ContentDocument> filesToReparentToTarget = new List<ContentDocument>();
        List<ContentDocumentLink> filesToAddToTarget = new List<ContentDocumentLink>();

        // Steps

        // 1. Create list of impacted ContentDocumentLinks
        List<ContentDocumentLink> filesInSource = new List<ContentDocumentLink>();
        List<ContentDocumentLink> filesInTargetAlsoInSource = new List<ContentDocumentLink>();
        filesInSource = [SELECT Id, LinkedEntityId, LinkedEntity.Name, ContentDocumentId, ContentDocument.ParentId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :source.id]; // Files in source
        for (ContentDocumentLink fileInSource : filesInSource) {
            filesToMoveIds.add(fileInSource.ContentDocumentId);
        }
        filesInTargetAlsoInSource = [SELECT Id, LinkedEntityId, LinkedEntity.Name, ContentDocumentId, ContentDocument.ParentId, ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :target.id AND ContentDocumentId IN :filesToMoveIds]; 
        lstImpactedContentDocumentLinks.addAll(filesInSource);
        lstImpactedContentDocumentLinks.addAll(filesInTargetAlsoInSource);
        filesToAddToTargetIds.addAll(filesToMoveIds);

        for (ContentDocumentLink cdl : lstImpactedContentDocumentLinks) {
            // 2. Populate 'filesToDeleteFromLibraries' being the list of ContentDocumentLinks to delete
            if ((cdl.LinkedEntityId == target.Id) && (cdl.ContentDocument.ParentId == source.Id)) { // target link that needs to be deleted to enable reparenting of source to target 
                filesToDeleteFromLibraries.add(cdl);
            }
            if ((cdl.LinkedEntityId == source.Id) && (cdl.ContentDocument.ParentId != source.Id)) { // source link that is OK to delete
                filesToDeleteFromLibraries.add(cdl);
            }
            // 3. Populate 'filesToReparentIds' being the ids of the files to (later) reparent to target library by updating 'ParentId' on ContentDocument record
            if ((cdl.LinkedEntityId == source.Id) && (cdl.ContentDocument.ParentId == source.Id)) {
                filesToReparentIds.add(cdl.ContentDocumentId);
                filesToAddToTargetIds.remove(cdl.ContentDocumentId); // wont need to add this one to target, the reparenting will move it automagically
            }
            // 4. Don't move files already in target
            if (cdl.LinkedEntityId == target.id) {
                filesToAddToTargetIds.remove(cdl.ContentDocumentId); // wont need to add this one to target, its already there
            }
        } 
        // 5. Populate 'filesToReparentToTarget' 
        filesToReparentToTarget = [SELECT Id, ParentId, Title FROM ContentDocument WHERE Id IN :filesToReparentIds];
        for (ContentDocument file : filesToReparentToTarget) {
            file.ParentId = target.id;
        }

        // 6. Populate 'filesToAddToTarget'  
        for (Id fileId : filesToAddToTargetIds) {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = fileId;
            cdl.LinkedEntityId = target.id;
            filesToAddToTarget.add(cdl);
        }

        // Debug
        for (ContentDocumentLink cdl : filesToDeleteFromLibraries) {
            system.debug('*** cdls for deletion *** ' + cdl.ContentDocument.Title + ', ' + cdl.LinkedEntity.Name + ', ' + cdl.LinkedEntityId + ', ' + cdl.ContentDocumentId + ', ' + cdl.ContentDocument.ParentId);
        }
        for (ContentDocument file : filesToReparentToTarget) {
            system.debug('*** file for reparenting *** ' + file.Title + '->' + File.ParentId);
        }
        for (ContentDocumentLink file : filesToAddToTarget) {
            for (ContentDocumentLink cdl: lstImpactedContentDocumentLinks) {
                if (file.ContentDocumentId == cdl.ContentDocumentId) {
                    system.debug('*** cdls for adding *** ' + cdl.ContentDocument.Title + '->' + File.LinkedEntityId);
                }
            }
        }

        // Delete files from source library (and any from target that are to be reparented from source)
        try {
            delete filesToDeleteFromLibraries;
            System.debug('*** PC_GroupPickerController.moveFiles *** Deleted ' + filesToDeleteFromLibraries.size() + ' files from libraries: ' + source.Name + ', ' + target.Name);
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.moveFiles *** Delete ContentDocumentLink failed: ' + e.getMessage());
        } 

        // Reparent any files from source library that are owned by source library
        try {
            update filesToReparentToTarget;
            System.debug('*** PC_GroupPickerController.moveFiles *** Reparented ' + filesToReparentToTarget.size() + ' files from source library ' + source.Name);
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.moveFiles *** Update ContentDocument failed: ' + e.getMessage());
        } 

        // Add files from source library to target that are a) not already in target and b) not going to be moved via reparenting
        try {
            insert filesToAddToTarget;
            System.debug('*** PC_GroupPickerController.moveFiles *** Added ' + filesToAddToTarget.size() + ' files to target library ' + target.Name);
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.moveFiles *** Insert ContentDocumentLink failed: ' + e.getMessage());
        } 
       
        filesMoved = filesToMoveIds.size();

        return filesMoved;
    }

    private static List<ContentDocument> getFilesInLibrary(ContentWorkspace library) {
        List<ContentDocument> cds = new List<ContentDocument>();

        List <ContentDocumentLink> cdls = new List<ContentDocumentLink>();
        cdls = [SELECT Id, ContentDocumentId from ContentDocumentLink WHERE LinkedEntityId = :library.Id];
        system.debug('Number of files in ' + library.Name + ' = ' + cdls.size());
        List <Id> fileIds = new List <Id>();
        for (ContentDocumentLink cdl : cdls) {
            fileIds.add(cdl.ContentDocumentId);
        }
        cds = [SELECT Id, ParentId, Title FROM ContentDocument WHERE Id IN :fileIds ];

        return cds;
    }

    private static Boolean doDeleteLibraries(List<ContentWorkspace> libraries) {
        Boolean retval = false;
        try {
            system.debug('Deleting ' + libraries.size() + ' libraries');
            if (libraries.size() > 0) {
                emptyTheRecycleBin(libraries);
                List<Id> libraryIds = new List<Id>();
                for (ContentWorkspace cw : libraries) {
                    libraryIds.add(cw.Id);
                }
                doDeleteLibrariesFuture(libraryIds);
            }
            System.debug('*** PC_GroupPickerController.doDeleteLibraries *** Deleted ' + libraries.size() + ' libraries');
            retval = true;
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.doDeleteLibraries *** Delete from ContentWorkspace failed: ' + e.getMessage());
        }
        return retval;
    }

    // Avoid Mixed DML error
    @future
    private static void doDeleteLibrariesFuture(List<Id> libraryIds) {
        List<ContentWorkspace> libraries = new List<ContentWorkspace> ();
        libraries = [SELECT Id FROM ContentWorkspace WHERE Id IN :libraryIds];
        try {
            delete libraries;
            System.debug('*** PC_GroupPickerController.doDeleteLibrariesFuture *** Deleted ' + libraries.size() + ' libraries');
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.doDeleteLibrariesFuture *** Delete from ContentWorkspace failed: ' + e.getMessage());
        }
    }

    private static void emptyTheRecycleBin(List<ContentWorkspace> libraries){
        
        //fetch ContentDocument objects that are in recycle bin.   
        try{
            List<Id> libraryIds = new List<Id>();
            for (ContentWorkspace cw : libraries) {
                libraryIds.add(cw.Id);
            }
            // Get List of files to permanantly delete
            List<ContentDocumentLink> cdls = new list<ContentDocumentLink>();
            cdls = [SELECT Id, ContentDocumentId from ContentDocumentLink WHERE LinkedEntityId IN :libraryIds AND ContentDocument.isDeleted = TRUE ALL ROWS];
            System.debug('*** PC_GroupPickerController.emptyTheRecycleBin *** Found ' + cdls.size() + ' files to empty from recycle bin');
            List<Id> filesToDeleteFromBin = new List<Id>();
            for (ContentDocumentLink cdl : cdls) {
                filesToDeleteFromBin.add(cdl.ContentDocumentId);
            }
            List<ContentDocument> cds = new List<ContentDocument>();
            cds = [SELECT Id FROM ContentDocument WHERE Id IN :filesToDeleteFromBin ALL ROWS];
            //add all objects to a Sobject type list.
            List<SObject> listToDeleteRecycle=new List<Sobject>();
            listToDeleteRecycle.addAll(cds);
        
            //delete the Sobject list from recycle bin.
            if(listToDeleteRecycle.size() > 0) {
                System.debug('*** PC_GroupPickerController.emptyTheRecycleBin *** Emptying ' + cdls.size() + ' listToDeleteRecycle.size()');
                Database.emptyRecycleBin(listToDeleteRecycle);
            }
        
        }
        catch(Exception e){
            System.debug('*** PC_GroupPickerController.emptyTheRecycleBin *** Delete from Recycle Bin failed: ' + e.getMessage());
        }
    }


    // 
    private static List<Group> createGroups (List<String> groupNames) {
        List<Group> gs = new List<Group>();
        try {
            for (String groupName : groupNames) {
                Group g = new Group();
                g.Name = 'PCG' + ' ' + groupName;
                g.DeveloperName = g.Name.replace(' ', '_');
                g.Type = 'Regular';
                gs.add(g);
            }
            insert gs;
            System.debug('*** PC_GroupPickerController.createGroups *** Created ' + gs.size() + ' new public groups');
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.createGroups *** Group insert failed: ' + e.getMessage());
        }
        return gs;
    }

    // Create a public group if it doesdnt already exist
    private static Id createOneGroup (String groupName) {
        
        // Check if group already exists
        List<Group> gs = new List<Group>();
        gs = [SELECT Id from Group WHERE Name = :groupName LIMIT 1]; 
        if (gs.size() > 0) {
            System.debug('*** PC_GroupPickerController.createOneGroup *** Already exists public group:' + groupName);
            return gs[0].Id;
        }

        // If not make a new one
        Group g = new Group();
        g.Name = groupName;
        g.DeveloperName = g.Name.replace(' ', '_');
        g.Type = 'Regular';
        try {
            insert g;
            System.debug('*** PC_GroupPickerController.createOneGroup *** Created new public group:' + groupName);
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.createOneGroup *** Group insert failed: ' + e.getMessage());
        }
        return g.Id;
    }

    // 
    private static List<ContentWorkspace> createLibraries (List<Group> groups) {
        
        List<ContentWorkspace> cws = new List<ContentWorkspace>();
        try {
            for (Group g : groups) {
                ContentWorkspace w = new ContentWorkspace();
                w.Description = 'Profiled content library created by admin tool';
                w.Name = g.Name.mid(4, 200);
                w.DeveloperName = 'PCG_' + w.Name.replace(' ', '_');
                // w.ShouldAddCreatorMembership = true;
                cws.add(w);
                System.debug('*** PC_GroupPickerController.createLibrary *** Creating library ' + w.Name);
            }
            insert cws;
            System.debug('*** PC_GroupPickerController.createLibrary *** Created ' + cws.size() + ' new libraries');
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.createLibrary *** ContentWorkspace insert failed: ' + e.getMessage());
        }
        return cws;
    }

    // 
    private static List<ContentWorkspaceMember> shareLibraries (List<ContentWorkspace>  libraries, List<Group> groups) {
        
        List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();
        Set<Id> libraryIds = new Set<Id>();
        Id adminsGroupId = createOneGroup (ADMIN_GROUP_NAME); // Id of Profiled Content Admin public group
        try {
            for (ContentWorkspace library : libraries) {
                libraryIds.add(library.Id);
                // General users
                ContentWorkspaceMember m = new ContentWorkspaceMember();
                ContentWorkspacePermission p = [SELECT Id FROM ContentWorkspacePermission WHERE Name = 'Viewer' LIMIT 1];
                m.ContentWorkspaceId = library.Id;
                m.MemberId = getGroupId('PCG ' + library.Name, groups);
                m.ContentWorkspacePermissionId = p.Id;
                cwms.add(m);

                // Content admin users
                ContentWorkspaceMember mAdmin = new ContentWorkspaceMember();
                ContentWorkspacePermission pAdmin = [SELECT Id FROM ContentWorkspacePermission WHERE Name = 'Library Administrator' LIMIT 1];
                mAdmin.ContentWorkspaceId = library.Id;
                mAdmin.MemberId = adminsGroupId;
                mAdmin.ContentWorkspacePermissionId = pAdmin.Id;
                cwms.add(mAdmin);
            }
            insert cwms;
            System.debug('*** PC_GroupPickerController.shareLibraries *** Shared ' + libraries.size() + ' libraries with users and admnins');
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.shareLibrary *** ContentWorkspaceMember insert failed: ' + e.getMessage());
        }

        // Now remove the running user as a direct member, as library should be shared only via public group
        List<ContentWorkspaceMember> membersToDelete = new List<ContentWorkspaceMember>();
        Id myUserId = UserInfo.getUserId();
        membersToDelete = [SELECT id from contentworkspacemember where ContentWorkspaceId IN :libraryIds AND memberid = :myUserId ];
        if (membersToDelete.size() > 0) {
            try {
                delete membersToDelete;
                System.debug('*** PC_GroupPickerController.shareLibrary *** Deleted direct library share for user ' + myUserId);
            } catch(DmlException e) {
                System.debug('*** PC_GroupPickerController.shareLibrary *** ContentWorkspaceMember delete failed: ' + e.getMessage());
            }
        }

        return cwms;
    }

    private static Id getGroupId(String name, List<Group> groups) {
        Id groupId = null;
        for (Group g : groups) {
            if (g.Name == name) {
                return g.Id;
            }
        }
        return groupId;
    }

    @AuraEnabled (cacheable=false)
    public static List<Dealer__c>  getAllDealers(){
        return [SELECT Name, Id FROM Dealer__c ORDER BY Name ASC NULLS FIRST];
    }

    @AuraEnabled (cacheable=false)
    public static List<DealerGroupRelationship__c>  getDealers(String groupName){
        return [SELECT Dealer_Name__c, Dealer__c FROM DealerGroupRelationship__c WHERE Profile_Group__c = :groupName];
    }

    public static List<Id>  getDealerIds(String groupName){
        List<Id> dealerIds = new List<Id>();
        List<DealerGroupRelationship__c> dgrs = new List<DealerGroupRelationship__c>();
        dgrs = getDealers(groupName);
        for (DealerGroupRelationship__c dgr : dgrs) {
            dealerIds.add(dgr.Dealer__c );
        }
        return dealerIds;
    }

    @AuraEnabled (cacheable=false)
    public static Boolean assignDealers(String groupName, List<Id> dealers) {

        Boolean retval = false;
        
        // Update DealerGroupRelationship__c

        // First delete all dealers for this group
        // The add dealers provided in the list
        // This is slightly inefficient, but simple
        deleteDealerGroupRelationship(groupName);
        addDealerGroupRelationship(groupName, dealers);

        // Now assign (and de-assign) members to the group via GroupMember object
        updateGroupMembers(groupName, dealers);

        return retval;
    }

    private static Boolean deleteDealerGroupRelationship (String groupName) {
        
        Boolean retval = false;
        List<DealerGroupRelationship__c> dgrs = new List<DealerGroupRelationship__c>();

        try {
            dgrs = [SELECT Id FROM DealerGroupRelationship__c WHERE Profile_Group__c = :groupName];
            if (dgrs.size() > 0) {
                delete dgrs;
            }
            retval = true;
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.deleteDealerGroupRelationship *** DealerGroupRelationship__c delete failed: ' + e.getMessage());
        }
        return retval;
    }

    private static Boolean addDealerGroupRelationship (String groupName, List<Id> dealers) {
        
        Boolean retval = false;
        List<DealerGroupRelationship__c> dgrs = new List<DealerGroupRelationship__c>();
        try {
            if (dealers != null) {
                for (Id dealer : dealers) {
                    DealerGroupRelationship__c dgr = new DealerGroupRelationship__c();
                    dgr.Profile_Group__c = groupName;
                    dgr.Dealer__c = dealer;
                    dgrs.add(dgr);
                }
                insert dgrs;
            }
            retval = true;
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.addDealerGroupRelationship *** DealerGroupRelationship__c insert failed: ' + e.getMessage());
        }
        return retval;
    }

    @future
    private static void updateGroupMembers(String groupName, List<Id> dealers) {
        
        // Find our group id
        Group g = [SELECT Id from Group WHERE Name = :groupName LIMIT 1]; // Get group Id
        Id groupId = g.Id;
        system.debug('group id ' + groupId);

        // Make List of eligible members
        List <User> members = new List<User>();
        if (dealers != null) {
            for (Id dealer : dealers) {
                Dealer__c d = [SELECT Id, Code__c from Dealer__c WHERE Id = :dealer];
                String code = d.Code__c;
                system.debug('evaluating dealer ' + code);
                List<User> us = [SELECT Id from User WHERE Premise_Code__c = :code AND Profiled_Content_User__c = true];
                members.addAll(us);
            }
        }

        List<Id> memberIds = new List<Id> ();
        for (User u : members) {
            memberIds.add(u.id);
        }

        Integer numMembers = members.size();
        system.debug('number of eligible members for ' + groupName + ' is ' + numMembers);

        // Add new members
        try {
            if (members.size() > 0) {
                List<GroupMember> gms = new List<GroupMember>(); // new members to add
                List<User> newMembers = [SELECT Id, Name from User WHERE Id IN :members AND Id NOT IN (SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :groupId)];
                for (User u : newMembers) {
                    system.debug('adding new member ' + u.Name);
                    GroupMember gm = new GroupMember();
                    gm.GroupId = groupId;
                    gm.UserOrGroupId = u.Id;
                    gms.add(gm);
                }
                insert gms;
            }
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.updateGroupMembers *** GroupMember insert failed: ' + e.getMessage());
        }

        // Remove old members
        try {
                List<GroupMember> membersToDelete = new List<GroupMember>(); // old members to delete
                membersToDelete = [SELECT UserOrGroupId from GroupMember WHERE GroupId = :groupId AND UserOrGroupId NOT IN :memberIds];
                if (membersToDelete.size() > 0) {
                    system.debug('deleting ' + membersToDelete.size() + ' old members');
                    delete membersToDelete;
                } else {
                    system.debug('no members to delete');
                }
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.updateGroupMembers *** GroupMember delete failed: ' + e.getMessage());
        }

    }

    // Ensure all profiled content libraries are shared with profiled content admins
    private static void shareProfiledContentLibrariesWithAdmins() {
        List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();
        Set<Id> libraryIds = new Set<Id>();
        Set<Id> libraryIdsSharedToAdmins = new Set<Id>();

        system.debug('*** PC_GroupPickerController.shareProfiledContentLibrariesWithAdmins *** giving content admins full access to the profiled content libraries'); 
        Id groupId = createOneGroup (ADMIN_GROUP_NAME); // Id of Profiled Content Admin public group
        libraryIds = getContentLibraryIdsAll(); // Ids of all Profiled Content libraries
        system.debug('A. profiled content library ids ' + libraryIds);
        libraryIdsSharedToAdmins = getContentLibraryIdsSharedToGroup(groupId); // Ids of libraries already shared with content admin public group 
        system.debug('B. profiled content library shared to admins ' + libraryIdsSharedToAdmins);
        libraryIds.removeAll(libraryIdsSharedToAdmins); // remove library ids of those already shared to the admin public group
        system.debug('A. - B. ids ' + libraryIds);

        try {
            for (Id libraryId : libraryIds) {
                ContentWorkspaceMember m = new ContentWorkspaceMember();
                ContentWorkspacePermission p = [SELECT Id FROM ContentWorkspacePermission WHERE Name = 'Library Administrator' LIMIT 1];
                m.ContentWorkspaceId = libraryId;
                m.MemberId = groupId;
                m.ContentWorkspacePermissionId = p.Id;
                cwms.add(m);
            }
            insert cwms;
            System.debug('*** PC_GroupPickerController.shareProfiledContentLibrariesWithAdmins *** Shared ' + cwms.size() + ' libraries');
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.shareProfiledContentLibrariesWithAdmins *** ContentWorkspaceMember insert failed: ' + e.getMessage());
        }
    }

    // Share library with profiled content admins
    private static void shareLibraryWithAdmins(Id libraryId) {
        List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();

        system.debug('*** PC_GroupPickerController.shareLibraryWithAdmins *** giving content admins full access to the library'); 
        Id groupId = createOneGroup (ADMIN_GROUP_NAME); // Id of Profiled Content Admin public group
        try {
            ContentWorkspaceMember m = new ContentWorkspaceMember();
            ContentWorkspacePermission p = [SELECT Id FROM ContentWorkspacePermission WHERE Name = 'Library Administrator' LIMIT 1];
            m.ContentWorkspaceId = libraryId;
            m.MemberId = groupId;
            m.ContentWorkspacePermissionId = p.Id;
            cwms.add(m);
            insert cwms;
            System.debug('*** PC_GroupPickerController.shareLibraryWithAdmins *** Shared ' + cwms.size() + ' libraries');
        } catch(DmlException e) {
            System.debug('*** PC_GroupPickerController.shareLibraryWithAdmins *** ContentWorkspaceMember insert failed: ' + e.getMessage());
        }
    }

    // Return all Profile Content Library Ids
    private static Set<Id> getContentLibraryIdsAll() {
        
        Set<Id> cwIds = new Set<Id>();
        List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();

        cwms = [SELECT ContentWorkspaceId FROM ContentWorkspaceMember WHERE Member.Name LIKE 'PCG%'];
        for (ContentWorkspaceMember cwm : cwms) {
            cwIds.add(cwm.ContentWorkspaceId);
        }

        return cwIds;
    }

    // Return all Profile Content Library Ids  shared with the public group
    private static Set<Id> getContentLibraryIdsSharedToGroup(Id groupId) {
    
        Set<Id> cwIds = new Set<Id>();
        List<ContentWorkspaceMember> cwms = new List<ContentWorkspaceMember>();

        // find libraries shared with the groupId
        cwms = [SELECT ContentWorkspaceId FROM ContentWorkspaceMember WHERE MemberId = :groupId];
        for (ContentWorkspaceMember cwm : cwms) {
            cwIds.add(cwm.ContentWorkspaceId);
        }

        return cwIds;
    }
}