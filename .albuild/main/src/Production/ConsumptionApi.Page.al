page 72222 "DOPSWHS Consumption API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'productionConsumption';
    EntitySetName = 'productionConsumption';
    SourceTable = "Prod. Order Component";
    SourceTableView = where(Status = const(Released));
    DelayedInsert = true;
    ODataKeyFields = Status, "Prod. Order No.", "Prod. Order Line No.", "Line No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(prodOrderNo; Rec."Prod. Order No.") { Caption = 'prodOrderNo'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(prodOrderLineNo; Rec."Prod. Order Line No.") { Caption = 'prodOrderLineNo'; }
                field(componentLineNo; Rec."Line No.") { Caption = 'componentLineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(remainingQuantity; Rec."Remaining Quantity") { Caption = 'remainingQuantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
            }
        }
    }

    [ServiceEnabled]
    procedure consume(prodOrderNo: Code[20]; componentLineNo: Integer; itemNo: Code[20]; qty: Decimal; lpNo: Code[20]; lotNo: Code[50]; serialNo: Code[50]; binCode: Code[20])
    var
        ProdMgmt: Codeunit "DOPSWHS Prod Mgmt";
    begin
        ProdMgmt.ConsumeByProdOrder(prodOrderNo, componentLineNo, itemNo, qty, lpNo, lotNo, serialNo, binCode);
    end;
}
