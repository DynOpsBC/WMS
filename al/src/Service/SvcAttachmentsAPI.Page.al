page 72119 "DOPSWHS Svc Attachments API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceAttachment';
    EntitySetName = 'serviceAttachments';
    SourceTable = "Document Attachment";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    SourceTableView = where("Table ID" = const(5900), "Document Type" = const(Order));
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(no; Rec."No.") { Caption = 'no'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(fileName; Rec."File Name") { Caption = 'fileName'; }
                field(fileExtension; Rec."File Extension") { Caption = 'fileExtension'; }
                field(attachedDate; Rec."Attached Date") { Caption = 'attachedDate'; }
                field(user; Rec."User") { Caption = 'user'; }
            }
        }
    }
}
