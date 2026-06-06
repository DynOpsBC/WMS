page 72295 "DOPSWHS Sales Source Line API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'salesSourceLine';
    EntitySetName = 'salesSourceLines';
    SourceTable = "Sales Line";
    SourceTableView = where("Document Type" = const(Order));
    DelayedInsert = true;
    ODataKeyFields = "Document Type", "Document No.", "Line No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(documentType; Rec."Document Type") { Caption = 'documentType'; Editable = false; }
                field(no; Rec."Document No.") { Caption = 'no'; Editable = false; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; Editable = false; }
                field(type; Rec.Type) { Caption = 'type'; Editable = false; }
                field(itemNo; Rec."No.") { Caption = 'itemNo'; Editable = false; }
                field(description; Rec.Description) { Caption = 'description'; Editable = false; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; Editable = false; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; Editable = false; }
                field(outstandingQuantity; Rec."Outstanding Quantity") { Caption = 'outstandingQuantity'; Editable = false; }
                field(qtyShipped; Rec."Quantity Shipped") { Caption = 'qtyShipped'; Editable = false; }
                field(qtyToShip; Rec."Qty. to Ship") { Caption = 'qtyToShip'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; Editable = false; }
                field(unitPrice; Rec."Unit Price") { Caption = 'unitPrice'; Editable = false; }
            }
        }
    }
}
