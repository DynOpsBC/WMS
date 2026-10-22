page 72001 "DOPSWHS First Count Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'firstCountLine';
    EntitySetName = 'firstCountLines';
    SourceTable = "DOPSWHS First Count Line";
    ODataKeyFields = "Count No.", "Line No.";
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
                field(countNo; Rec."Count No.") { Caption = 'countNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(quantityBase; Rec."Quantity (Base)") { Caption = 'quantityBase'; }
                field(userId; Rec."User ID") { Caption = 'userId'; }
                field(createdDateTime; Rec."Created DateTime") { Caption = 'createdDateTime'; }
            }
        }
    }
}
