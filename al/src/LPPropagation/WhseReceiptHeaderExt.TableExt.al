tableextension 72422 "DOPSWHS Whse Rcpt Hdr Ext" extends "Warehouse Receipt Header"
{
    fields
    {
        field(72422; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        // 72423 is Code[20] on Posted Whse. Receipt Header. Standard
        // TransferFields matches by ID and cannot copy a Boolean into it.
        // Keep the installed column obsolete so upgrades need no ForceSync.
        field(72423; "DOPSWHS Posting Legacy"; Boolean)
        {
            Caption = 'WMS Posting In Progress (Legacy)';
            DataClassification = SystemMetadata;
            ObsoleteState = Removed;
            ObsoleteReason = 'Field 72423 conflicts with the posted receipt LP field. Replaced by 72435.';
            ObsoleteTag = '1.14.1.28';
        }
        field(72435; "DOPSWHS Posting In Progress"; Boolean)
        {
            Caption = 'WMS Posting In Progress';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }

    trigger OnBeforeDelete()
    var
        ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
    begin
        // Standard posting deletes the working receipt too. The flag is set in
        // the same transaction immediately before posting, so only a genuine
        // user/API cancellation cleans the not-yet-posted LP contents.
        if not Rec."DOPSWHS Posting In Progress" then
            ReceiptMgmt.CleanupCanceledReceiptLPs(Rec."No.");
    end;
}
