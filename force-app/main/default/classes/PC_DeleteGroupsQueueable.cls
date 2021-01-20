public class PC_DeleteGroupsQueueable implements Queueable {
    public List<Group> groups ;
    public PC_DeleteGroupsQueueable(List<Group> lstGroups) {
        this.groups = lstGroups;
    }
    public void execute(QueueableContext context) {
        try {
            system.debug('Deleting ' + groups.size() + ' groups');
            if (groups.size() > 0) {
                delete groups;
            }
        } catch(DmlException e) {
            System.debug('*** PC_DeleteGroupsQueueable.PC_DeleteGroupsQueueable *** Group deletes failed: ' + e.getMessage());
        }
    }
}