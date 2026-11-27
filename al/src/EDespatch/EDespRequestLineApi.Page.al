page 72468 "DOPSWHS EDesp Req. Line API"
{
    //   GET eDespatchRequestLines?$filter=requestEntryNo eq 12
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'eDespatchRequestLine';
    EntitySetName = 'eDespatchRequestLines';
    SourceTable = "DOPSWHS EDesp Request Line";
    ODataKeyFields = "Request Entry No.", "Line No.";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(requestEntryNo; Rec."Request Entry No.") { Caption = 'requestEntryNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(fromBinCode; Rec."From Bin Code") { Caption = 'fromBinCode'; }
                field(toBinCode; Rec."To Bin Code") { Caption = 'toBinCode'; }
                field(lpNo; Rec."LP No.") { Caption = 'lpNo'; }
            }
        }
    }
}
