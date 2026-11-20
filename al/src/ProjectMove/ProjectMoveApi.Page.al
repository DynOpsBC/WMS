page 72206 "DOPSWHS Project Move API"
{
    // Terminal: bir projenin / bir maddenin proje taşıma geçmişi. Salt okunur.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'projectMoveEntry';
    EntitySetName = 'projectMoveEntries';
    SourceTable = "DOPSWHS Project Move Entry";
    ODataKeyFields = "Entry No.";
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(entryNo; Rec."Entry No.") { Caption = 'entryNo'; }
                field(movedAt; Rec."Moved At") { Caption = 'movedAt'; }
                field(userId; Rec."User ID") { Caption = 'userId'; }
                field(userName; Rec."User Name") { Caption = 'userName'; }
                field(projectNo; Rec."Project No.") { Caption = 'projectNo'; }
                field(projectDescription; Rec."Project Description") { Caption = 'projectDescription'; }
                field(salesOrderNo; Rec."Sales Order No.") { Caption = 'salesOrderNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(itemDescription; Rec."Item Description") { Caption = 'itemDescription'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(fromBinCode; Rec."From Bin Code") { Caption = 'fromBinCode'; }
                field(toBinCode; Rec."To Bin Code") { Caption = 'toBinCode'; }
                field(lpNo; Rec."LP No.") { Caption = 'lpNo'; }
            }
        }
    }
}
