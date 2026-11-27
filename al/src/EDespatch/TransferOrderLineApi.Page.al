page 72463 "DOPSWHS Transfer Line API"
{
    // Lines of released transfer orders for the handheld.  GET transferOrderLines?$filter=documentNo eq 'TO-0001'
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'transferOrderLine';
    EntitySetName = 'transferOrderLines';
    SourceTable = "Transfer Line";
    SourceTableView = where("Derived From Line No." = const(0));
    ODataKeyFields = "Document No.", "Line No.";
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
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(quantityShipped; Rec."Quantity Shipped") { Caption = 'quantityShipped'; }
                field(outstandingQuantity; Rec."Outstanding Quantity") { Caption = 'outstandingQuantity'; }
                field(qtyToShip; Rec."Qty. to Ship") { Caption = 'qtyToShip'; }
                field(transferFromBinCode; Rec."Transfer-from Bin Code") { Caption = 'transferFromBinCode'; }
                field(transferToBinCode; Rec."Transfer-To Bin Code") { Caption = 'transferToBinCode'; }
                field(gtin; ItemGtin) { Caption = 'gtin'; }
                field(lotRequired; LotRequired) { Caption = 'lotRequired'; }
                field(serialRequired; SerialRequired) { Caption = 'serialRequired'; }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
    begin
        ItemGtin := '';
        LotRequired := false;
        SerialRequired := false;
        if not Item.Get(Rec."Item No.") then
            exit;
        ItemGtin := Item.GTIN;
        if Item."Item Tracking Code" = '' then
            exit;
        if ItemTrackingCode.Get(Item."Item Tracking Code") then begin
            LotRequired := ItemTrackingCode."Lot Specific Tracking";
            SerialRequired := ItemTrackingCode."SN Specific Tracking";
        end;
    end;

    var
        ItemGtin: Code[14];
        LotRequired: Boolean;
        SerialRequired: Boolean;
}
