page 72294 "DOPSWHS Sales Source API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'salesSource';
    EntitySetName = 'salesSources';
    SourceTable = "Sales Header";
    SourceTableView = where("Document Type" = const(Order));
    DelayedInsert = true;
    Editable = false;
    ODataKeyFields = "No.";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(customerNo; Rec."Sell-to Customer No.") { Caption = 'customerNo'; }
                field(customerName; Rec."Sell-to Customer Name") { Caption = 'customerName'; }
                field(shipToName; Rec."Ship-to Name") { Caption = 'shipToName'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(orderDate; Rec."Order Date") { Caption = 'orderDate'; }
                field(shipmentDate; Rec."Shipment Date") { Caption = 'shipmentDate'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(shippingAgentCode; Rec."Shipping Agent Code") { Caption = 'shippingAgentCode'; }
                field(lineCount; LineCount) { Caption = 'lineCount'; }
                field(outstandingQty; OutstandingQty) { Caption = 'outstandingQty'; }
                field(percentComplete; PercentComplete) { Caption = 'percentComplete'; }
                field(requiresWhseShipment; RequiresWhseShipment) { Caption = 'requiresWhseShipment'; }
                field(directShipAllowed; DirectShipAllowed) { Caption = 'directShipAllowed'; }
                part(lines; "DOPSWHS Sales Source Line API")
                {
                    Caption = 'lines';
                    EntityName = 'salesSourceLine';
                    EntitySetName = 'salesSourceLines';
                    SubPageLink = "Document Type" = const(Order), "Document No." = field("No.");
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        FillCalculatedFields();
    end;

    [ServiceEnabled]
    procedure ship(invoice: Boolean): Text
    var
        Mgmt: Codeunit "DOPSWHS Sales Source Mgmt";
    begin
        exit(Mgmt.ShipOrder(Rec."No.", invoice));
    end;

    /// <summary>
    /// Creates the warehouse shipment and its pick for one sales order. This
    /// is the warehouse-required counterpart of direct ship and uses the same
    /// grouped-pick engine as the picking-order screen.
    /// </summary>
    [ServiceEnabled]
    procedure createWarehousePick(userId: Code[50]): Text
    var
        MultiOrderPick: Codeunit "DOPSWHS Multi Order Pick";
        ShipmentNo: Code[20];
        PickNo: Code[20];
        Result: JsonObject;
        ResultText: Text;
    begin
        if userId = '' then
            Error('WMS kullanıcı kimliği boş olamaz.');
        PickNo := MultiOrderPick.CreateGroupedPick(Rec."No.", userId, ShipmentNo, 'multi');
        Result.Add('shipmentNo', ShipmentNo);
        Result.Add('pickNo', PickNo);
        Result.WriteTo(ResultText);
        exit(ResultText);
    end;

    [ServiceEnabled]
    procedure listShippingAgents(): Text
    var
        ShippingAgent: Record "Shipping Agent";
        Agents: JsonArray;
        Agent: JsonObject;
        ResultText: Text;
    begin
        if ShippingAgent.FindSet() then
            repeat
                Clear(Agent);
                Agent.Add('code', ShippingAgent.Code);
                Agent.Add('name', ShippingAgent.Name);
                Agents.Add(Agent);
            until ShippingAgent.Next() = 0;
        Agents.WriteTo(ResultText);
        exit(ResultText);
    end;

    [ServiceEnabled]
    procedure setShippingAgent(shippingAgentCode: Code[10])
    var
        SalesHeader: Record "Sales Header";
        ReleaseSalesDocument: Codeunit "Release Sales Document";
        WasReleased: Boolean;
    begin
        SalesHeader.Get(SalesHeader."Document Type"::Order, Rec."No.");
        SalesHeader.TestField("Shipping Agent Code", '');
        if shippingAgentCode = '' then
            Error('Sevkiyat acente kodu boş olamaz.');
        WasReleased := SalesHeader.Status = SalesHeader.Status::Released;
        if WasReleased then
            ReleaseSalesDocument.Reopen(SalesHeader);
        SalesHeader.Validate("Shipping Agent Code", shippingAgentCode);
        SalesHeader.Modify(true);
        if WasReleased then
            ReleaseSalesDocument.PerformManualRelease(SalesHeader);
        Rec := SalesHeader;
    end;

    var
        LineCount: Integer;
        OutstandingQty: Decimal;
        PercentComplete: Decimal;
        RequiresWhseShipment: Boolean;
        DirectShipAllowed: Boolean;

    local procedure FillCalculatedFields()
    var
        SL: Record "Sales Line";
        Loc: Record Location;
        TotalQty: Decimal;
        ShippedQty: Decimal;
    begin
        Clear(LineCount); Clear(OutstandingQty); Clear(PercentComplete);
        Clear(RequiresWhseShipment); Clear(DirectShipAllowed);
        SL.SetRange("Document Type", SL."Document Type"::Order);
        SL.SetRange("Document No.", Rec."No.");
        SL.SetFilter(Type, '<>%1', SL.Type::" ");
        if SL.FindSet() then
            repeat
                LineCount += 1;
                OutstandingQty += SL."Outstanding Quantity";
                TotalQty += SL.Quantity;
                ShippedQty += SL."Quantity Shipped";
            until SL.Next() = 0;
        if TotalQty <> 0 then
            PercentComplete := Round(ShippedQty / TotalQty * 100, 1);

        if Rec."Location Code" = '' then begin
            RequiresWhseShipment := false;
            DirectShipAllowed := true;
        end else if Loc.Get(Rec."Location Code") then begin
            RequiresWhseShipment := Loc."Require Shipment";
            DirectShipAllowed := not Loc."Require Shipment";
        end else begin
            RequiresWhseShipment := false;
            DirectShipAllowed := true;
        end;
    end;
}
