trigger PCG_ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    if(trigger.isAfter && trigger.isInsert) {
        PCG_NotifyMembersOfNewContent.newProfiledContent(trigger.new);
    }
}