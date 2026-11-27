page 72466 "DOPSWHS Invt. Mvmt. Line API"
{
    //   GET inventoryMovementLines?$filter=no eq 'IM-0001'
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'inventoryMovementLine';
    EntitySetName = 'inventoryMovementLines';
    SourceTable = "Warehouse Activity Line";
    SourceTableView = where("Activity Type" = const("Invt. Movement"));
    ODataKeyFields = "Activity Type", "No.", "Line No.";
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
                field(no; Rec."No.") { Caption = 'no'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(actionType; Rec."Action Type") { Caption = 'actionType'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(qtyOutstanding; Rec."Qty. Outstanding") { Caption = 'qtyOutstanding'; }
                field(qtyToHandle; Rec."Qty. to Handle") { Caption = 'qtyToHandle'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
            }
        }
    }
}
