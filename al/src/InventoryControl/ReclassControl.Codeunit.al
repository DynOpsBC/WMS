codeunit 72006 "DOPSWHS Reclass Control"
{
    // KIT-015 (Kitoko, Kas 2026): item reclassification journal ("stok virmanı")
    // controls, both off by default (Advanced WMS Setup):
    //  - "Reclass Reason Code Mandatory": every reclassification line needs a
    //    reason code, so each transfer between bins/locations/lots is explained.
    //  - "Reclass Posting Restricted": only users on the inventory approver list
    //    with "Approve Reclassification" may post reclassification journals.
    // Checked per line while the journal batch is posted (journal page, Post
    // and Print, batch posting). Batches the WMS fills itself for terminal bin
    // moves are flagged "WMS System Batch" and are exempt, so terminal moves
    // keep working without reason codes or approver accounts.
    Access = Public;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Item Jnl.-Post Batch", 'OnAfterCheckJnlLine', '', false, false)]
    local procedure CheckReclassJournalLine(var ItemJournalLine: Record "Item Journal Line"; CommitIsSuppressed: Boolean)
    var
        ReasonMandatory: Boolean;
        PostingRestricted: Boolean;
    begin
        if ItemJournalLine.IsTemporary() then
            exit;
        if (ItemJournalLine."Entry Type" <> ItemJournalLine."Entry Type"::Transfer) or (ItemJournalLine."Journal Template Name" = '') then
            exit;
        GetReclassSetup(ReasonMandatory, PostingRestricted);
        if not (ReasonMandatory or PostingRestricted) then
            exit;
        if not IsReclassJournal(ItemJournalLine."Journal Template Name") then
            exit;
        if IsSystemBatch(ItemJournalLine."Journal Template Name", ItemJournalLine."Journal Batch Name") then
            exit;
        if PostingRestricted and not IsReclassApprover(UserId()) then
            Error(NotAuthorizedErr, UserId(), ItemJournalLine."Journal Batch Name");
        if ReasonMandatory and (ItemJournalLine."Reason Code" = '') then
            Error(ReasonCodeRequiredErr, ItemJournalLine."Line No.", ItemJournalLine."Item No.", ItemJournalLine."Journal Batch Name");
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Setup", 'R')]
    procedure GetReclassSetup(var ReasonMandatory: Boolean; var PostingRestricted: Boolean)
    var
        Setup: Record "DOPSWHS Setup";
    begin
        ReasonMandatory := false;
        PostingRestricted := false;
        Setup.SetLoadFields("Reclass Reason Mandatory", "Reclass Approval Required");
        if not Setup.Get('') then
            exit;
        ReasonMandatory := Setup."Reclass Reason Mandatory";
        PostingRestricted := Setup."Reclass Approval Required";
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Inventory Approver", 'R')]
    procedure IsReclassApprover(UserName: Text): Boolean
    var
        InventoryApprover: Record "DOPSWHS Inventory Approver";
    begin
        if UserName = '' then
            exit(false);
        InventoryApprover.SetRange("User ID", CopyStr(UserName, 1, MaxStrLen(InventoryApprover."User ID")));
        InventoryApprover.SetRange("Approve Reclassification", true);
        exit(not InventoryApprover.IsEmpty());
    end;

    /// <summary>Marks a journal batch that the WMS fills and posts itself (terminal bin moves).</summary>
    procedure MarkSystemBatch(var ItemJournalBatch: Record "Item Journal Batch")
    begin
        if ItemJournalBatch."DOPSWHS System Batch" then
            exit;
        ItemJournalBatch."DOPSWHS System Batch" := true;
        ItemJournalBatch.Modify(true);
    end;

    local procedure IsReclassJournal(TemplateName: Code[10]): Boolean
    var
        ItemJournalTemplate: Record "Item Journal Template";
    begin
        ItemJournalTemplate.SetLoadFields(Type);
        if not ItemJournalTemplate.Get(TemplateName) then
            exit(false);
        exit(ItemJournalTemplate.Type = ItemJournalTemplate.Type::Transfer);
    end;

    local procedure IsSystemBatch(TemplateName: Code[10]; BatchName: Code[10]): Boolean
    var
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        ItemJournalBatch.SetLoadFields("DOPSWHS System Batch");
        if not ItemJournalBatch.Get(TemplateName, BatchName) then
            exit(false);
        exit(ItemJournalBatch."DOPSWHS System Batch");
    end;

    var
        NotAuthorizedErr: Label 'You (%1) are not allowed to post item reclassification journals (batch %2). Ask an administrator to add you to the Inventory Control Approvers with Approve Reclassification.', Comment = '%1 = user id, %2 = journal batch';
        ReasonCodeRequiredErr: Label 'Reason Code must be filled in on reclassification journal line %1 (item %2, batch %3).', Comment = '%1 = line no., %2 = item no., %3 = journal batch';
}
