/// <summary>
/// Builds the JSON of the Service Summary page: one service order, or every service order opened
/// for a sales order. Reads the live service order while it exists and falls back to the posted
/// shipment and the service log afterwards. Nothing is written here.
/// </summary>
codeunit 72106 "DOPSWHS Service Summary Data"
{
    Access = Internal;

    procedure BuildJson(ServiceOrderNo: Code[20]; SalesOrderNo: Code[20]): Text
    var
        Root: JsonObject;
        Orders: JsonArray;
        OrderNos: List of [Code[20]];
        OrderNo: Code[20];
        Result: Text;
    begin
        if ServiceOrderNo <> '' then begin
            OrderNos.Add(ServiceOrderNo);
            SalesOrderNo := SalesOrderOf(ServiceOrderNo);
        end else
            CollectOrders(SalesOrderNo, OrderNos);

        foreach OrderNo in OrderNos do
            Orders.Add(OrderJson(OrderNo));

        Root.Add('company', CompanyProperty.DisplayName());
        Root.Add('generatedAt', Format(CurrentDateTime(), 0, 9));
        Root.Add('serviceOrderNo', ServiceOrderNo);
        Root.Add('salesOrderNo', SalesOrderNo);
        if SalesOrderNo <> '' then
            Root.Add('salesOrder', SalesOrderJson(SalesOrderNo));
        Root.Add('orders', Orders);
        Root.WriteTo(Result);
        exit(Result);
    end;

    local procedure SalesOrderOf(ServiceOrderNo: Code[20]): Code[20]
    var
        Header: Record "Service Header";
        Shipment: Record "Service Shipment Header";
        Entry: Record "DOPSWHS Service Log Entry";
    begin
        if Header.Get(Header."Document Type"::Order, ServiceOrderNo) then
            exit(Header."DOPSWHS Sales Order No.");
        Shipment.SetRange("Order No.", ServiceOrderNo);
        if Shipment.FindLast() then
            exit(Shipment."DOPSWHS Sales Order No.");
        Entry.SetCurrentKey("Service Order No.", "Entry No.");
        Entry.SetRange("Service Order No.", ServiceOrderNo);
        if Entry.FindLast() then
            exit(Entry."Sales Order No.");
        exit('');
    end;

    local procedure CollectOrders(SalesOrderNo: Code[20]; var OrderNos: List of [Code[20]])
    var
        Header: Record "Service Header";
        Shipment: Record "Service Shipment Header";
        Entry: Record "DOPSWHS Service Log Entry";
    begin
        if SalesOrderNo = '' then
            exit;
        Header.SetRange("Document Type", Header."Document Type"::Order);
        Header.SetRange("DOPSWHS Sales Order No.", SalesOrderNo);
        if Header.FindSet() then
            repeat
                AddOnce(OrderNos, Header."No.");
            until Header.Next() = 0;
        Shipment.SetRange("DOPSWHS Sales Order No.", SalesOrderNo);
        if Shipment.FindSet() then
            repeat
                AddOnce(OrderNos, Shipment."Order No.");
            until Shipment.Next() = 0;
        Entry.SetCurrentKey("Sales Order No.", "Service Order No.", "Entry No.");
        Entry.SetRange("Sales Order No.", SalesOrderNo);
        if Entry.FindSet() then
            repeat
                AddOnce(OrderNos, Entry."Service Order No.");
            until Entry.Next() = 0;
    end;

    local procedure AddOnce(var OrderNos: List of [Code[20]]; OrderNo: Code[20])
    begin
        if (OrderNo <> '') and not OrderNos.Contains(OrderNo) then
            OrderNos.Add(OrderNo);
    end;

    local procedure OrderJson(OrderNo: Code[20]): JsonObject
    var
        Header: Record "Service Header";
        Shipment: Record "Service Shipment Header";
        Entry: Record "DOPSWHS Service Log Entry";
        Order: JsonObject;
        Shipments: JsonArray;
        ShipmentJson: JsonObject;
        IsLive: Boolean;
        LastShipmentNo: Code[20];
    begin
        Order.Add('no', OrderNo);
        IsLive := Header.Get(Header."Document Type"::Order, OrderNo);

        Shipment.SetRange("Order No.", OrderNo);
        if Shipment.FindSet() then
            repeat
                Clear(ShipmentJson);
                ShipmentJson.Add('no', Shipment."No.");
                ShipmentJson.Add('date', DateText(Shipment."Posting Date"));
                Shipments.Add(ShipmentJson);
                LastShipmentNo := Shipment."No.";
            until Shipment.Next() = 0;
        Order.Add('shipments', Shipments);

        if IsLive then begin
            Order.Add('customerNo', Header."Customer No.");
            Order.Add('customerName', Header.Name);
            Order.Add('city', Header.City);
            Order.Add('contact', Header."Contact Name");
            Order.Add('phone', Header."Phone No.");
            Order.Add('description', Header.Description);
            Order.Add('orderDate', DateText(Header."Order Date"));
            Order.Add('finishingDate', DateText(Header."Finishing Date"));
            Order.Add('priority', PriorityName(Header.Priority.AsInteger()));
            Order.Add('status', StatusName(Header, LastShipmentNo <> ''));
            Order.Add('salesOrderNo', Header."DOPSWHS Sales Order No.");
            Order.Add('items', LiveItemsJson(Header));
            Order.Add('lines', LiveLinesJson(Header));
        end else
            if LastShipmentNo <> '' then begin
                Shipment.Get(LastShipmentNo);
                Order.Add('customerNo', Shipment."Customer No.");
                Order.Add('customerName', Shipment.Name);
                Order.Add('city', Shipment.City);
                Order.Add('contact', Shipment."Contact Name");
                Order.Add('phone', Shipment."Phone No.");
                Order.Add('description', Shipment.Description);
                Order.Add('orderDate', DateText(Shipment."Order Date"));
                Order.Add('finishingDate', DateText(Shipment."Finishing Date"));
                Order.Add('priority', PriorityName(Shipment.Priority));
                Order.Add('status', 'closed');
                Order.Add('salesOrderNo', Shipment."DOPSWHS Sales Order No.");
                Order.Add('items', PostedItemsJson(LastShipmentNo));
                Order.Add('lines', PostedLinesJson(OrderNo));
            end else begin
                // Only the log is left (order deleted without a shipment).
                Entry.SetCurrentKey("Service Order No.", "Entry No.");
                Entry.SetRange("Service Order No.", OrderNo);
                if Entry.FindLast() then begin
                    Order.Add('customerNo', Entry."Customer No.");
                    Order.Add('customerName', Entry."Customer Name");
                    Order.Add('salesOrderNo', Entry."Sales Order No.");
                end;
                Order.Add('status', 'closed');
            end;

        Order.Add('technicians', TechniciansJson(OrderNo));
        Order.Add('log', LogJson(OrderNo));
        exit(Order);
    end;

    local procedure StatusName(Header: Record "Service Header"; HasShipment: Boolean): Text
    begin
        case Header.Status of
            Header.Status::Finished:
                if HasShipment then
                    exit('posted')
                else
                    exit('finished');
            Header.Status::"On Hold":
                exit('onhold');
            Header.Status::"In Process":
                exit('inprocess');
        end;
        exit('pending');
    end;

    local procedure PriorityName(Priority: Integer): Text
    begin
        // Service Header (enum) and Service Shipment Header (option) share Low, Medium, High, Urgent.
        case Priority of
            1:
                exit('medium');
            2, 3:
                exit('high');
        end;
        exit('low');
    end;

    local procedure LiveItemsJson(Header: Record "Service Header"): JsonArray
    var
        ItemLine: Record "Service Item Line";
        Items: JsonArray;
    begin
        ItemLine.SetRange("Document Type", Header."Document Type");
        ItemLine.SetRange("Document No.", Header."No.");
        if ItemLine.FindSet() then
            repeat
                Items.Add(ItemJson(ItemLine."Line No.", ItemLine."Service Item No.", ItemLine.Description, ItemLine."Serial No.",
                    ItemLine."Fault Area Code", ItemLine."Symptom Code", ItemLine."Resolution Code",
                    ItemLine."Starting Date", ItemLine."Starting Time", ItemLine."Finishing Date", ItemLine."Finishing Time"));
            until ItemLine.Next() = 0;
        exit(Items);
    end;

    local procedure PostedItemsJson(ShipmentNo: Code[20]): JsonArray
    var
        ItemLine: Record "Service Shipment Item Line";
        Items: JsonArray;
    begin
        ItemLine.SetRange("No.", ShipmentNo);
        if ItemLine.FindSet() then
            repeat
                Items.Add(ItemJson(ItemLine."Line No.", ItemLine."Service Item No.", ItemLine.Description, ItemLine."Serial No.",
                    ItemLine."Fault Area Code", ItemLine."Symptom Code", ItemLine."Resolution Code",
                    ItemLine."Starting Date", ItemLine."Starting Time", ItemLine."Finishing Date", ItemLine."Finishing Time"));
            until ItemLine.Next() = 0;
        exit(Items);
    end;

    local procedure ItemJson(LineNo: Integer; ServiceItemNo: Code[20]; Description: Text; SerialNo: Text; FaultAreaCode: Code[10]; SymptomCode: Code[10]; ResolutionCode: Code[10]; StartDate: Date; StartTime: Time; FinishDate: Date; FinishTime: Time): JsonObject
    var
        FaultArea: Record "Fault Area";
        Symptom: Record "Symptom Code";
        Resolution: Record "Resolution Code";
        Item: JsonObject;
    begin
        Item.Add('lineNo', LineNo);
        Item.Add('serviceItemNo', ServiceItemNo);
        Item.Add('description', Description);
        Item.Add('serialNo', SerialNo);
        if FaultArea.Get(FaultAreaCode) then
            Item.Add('faultArea', TextOr(FaultArea.Description, FaultAreaCode))
        else
            Item.Add('faultArea', FaultAreaCode);
        if Symptom.Get(SymptomCode) then
            Item.Add('symptom', TextOr(Symptom.Description, SymptomCode))
        else
            Item.Add('symptom', SymptomCode);
        if Resolution.Get(ResolutionCode) then
            Item.Add('resolution', TextOr(Resolution.Description, ResolutionCode))
        else
            Item.Add('resolution', ResolutionCode);
        Item.Add('startDate', DateText(StartDate));
        Item.Add('startTime', TimeText(StartTime));
        Item.Add('finishDate', DateText(FinishDate));
        Item.Add('finishTime', TimeText(FinishTime));
        exit(Item);
    end;

    local procedure LiveLinesJson(Header: Record "Service Header"): JsonArray
    var
        Line: Record "Service Line";
        Lines: JsonArray;
    begin
        Line.SetRange("Document Type", Header."Document Type");
        Line.SetRange("Document No.", Header."No.");
        Line.SetFilter(Type, '<>%1', Line.Type::" ");
        if Line.FindSet() then
            repeat
                Lines.Add(LineJson(Line.Type = Line.Type::Resource, Line.Type = Line.Type::Item, Line."No.", Line.Description,
                    Line.Quantity, Line."Unit of Measure Code", Line."Service Item Line No."));
            until Line.Next() = 0;
        exit(Lines);
    end;

    local procedure PostedLinesJson(OrderNo: Code[20]): JsonArray
    var
        Line: Record "Service Shipment Line";
        Lines: JsonArray;
    begin
        Line.SetRange("Order No.", OrderNo);
        // An undone shipment leaves a +/- pair of correction lines; neither is work that was done.
        Line.SetRange(Correction, false);
        Line.SetFilter(Type, '<>%1', Line.Type::" ");
        if Line.FindSet() then
            repeat
                Lines.Add(LineJson(Line.Type = Line.Type::Resource, Line.Type = Line.Type::Item, Line."No.", Line.Description,
                    Line.Quantity, Line."Unit of Measure Code", Line."Service Item Line No."));
            until Line.Next() = 0;
        exit(Lines);
    end;

    local procedure LineJson(IsLabor: Boolean; IsPart: Boolean; No: Code[20]; Description: Text; Quantity: Decimal; UnitOfMeasure: Code[10]; ItemLineNo: Integer): JsonObject
    var
        Line: JsonObject;
    begin
        if IsLabor then
            Line.Add('kind', 'labor')
        else
            if IsPart then
                Line.Add('kind', 'part')
            else
                Line.Add('kind', 'other');
        Line.Add('no', No);
        Line.Add('description', Description);
        Line.Add('quantity', Quantity);
        Line.Add('unit', UnitOfMeasure);
        Line.Add('itemLineNo', ItemLineNo);
        exit(Line);
    end;

    local procedure TechniciansJson(OrderNo: Code[20]): JsonArray
    var
        Allocation: Record "Service Order Allocation";
        Entry: Record "DOPSWHS Service Log Entry";
        Res: Record Resource;
        Names: JsonArray;
        Seen: List of [Text];
        Name: Text;
    begin
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", OrderNo);
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        Allocation.SetFilter("Resource No.", '<>%1', '');
        if Allocation.FindSet() then
            repeat
                if Res.Get(Allocation."Resource No.") and (Res.Name <> '') then
                    Name := Res.Name
                else
                    Name := Allocation."Resource No.";
                if not Seen.Contains(Name) then begin
                    Seen.Add(Name);
                    Names.Add(Name);
                end;
            until Allocation.Next() = 0;
        if Seen.Count() > 0 then
            exit(Names);
        // Allocations are gone with the order: the log still knows who worked on it.
        Entry.SetCurrentKey("Service Order No.", "Entry No.");
        Entry.SetRange("Service Order No.", OrderNo);
        Entry.SetFilter("Entry Type", '%1|%2|%3|%4', Entry."Entry Type"::Started, Entry."Entry Type"::Labor,
            Entry."Entry Type"::Part, Entry."Entry Type"::Finished);
        Entry.SetFilter("Technician Name", '<>%1', '');
        if Entry.FindSet() then
            repeat
                if not Seen.Contains(Entry."Technician Name") then begin
                    Seen.Add(Entry."Technician Name");
                    Names.Add(Entry."Technician Name");
                end;
            until Entry.Next() = 0;
        exit(Names);
    end;

    local procedure LogJson(OrderNo: Code[20]): JsonArray
    var
        Entry: Record "DOPSWHS Service Log Entry";
        Entries: JsonArray;
        Item: JsonObject;
    begin
        Entry.SetCurrentKey("Service Order No.", "Entry No.");
        Entry.SetRange("Service Order No.", OrderNo);
        if Entry.FindSet() then
            repeat
                Clear(Item);
                Item.Add('at', Format(Entry."Logged At", 0, 9));
                Item.Add('type', Entry."Entry Type".Names.Get(Entry."Entry Type".Ordinals.IndexOf(Entry."Entry Type".AsInteger())));
                Item.Add('typeText', Format(Entry."Entry Type"));
                Item.Add('text', Entry."Entry Text");
                if Entry."Technician Name" <> '' then
                    Item.Add('who', Entry."Technician Name")
                else
                    Item.Add('who', Entry."User ID");
                Item.Add('terminal', Entry."From Terminal");
                Item.Add('itemLineNo', Entry."Service Item Line No.");
                Entries.Add(Item);
            until Entry.Next() = 0;
        exit(Entries);
    end;

    local procedure SalesOrderJson(SalesOrderNo: Code[20]): JsonObject
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        InvoiceHeader: Record "Sales Invoice Header";
        InvoiceLine: Record "Sales Invoice Line";
        Result: JsonObject;
        Lines: JsonArray;
    begin
        Result.Add('no', SalesOrderNo);
        if SalesHeader.Get(SalesHeader."Document Type"::Order, SalesOrderNo) then begin
            Result.Add('state', 'open');
            Result.Add('customerNo', SalesHeader."Sell-to Customer No.");
            Result.Add('customerName', SalesHeader."Sell-to Customer Name");
            Result.Add('orderDate', DateText(SalesHeader."Order Date"));
            Result.Add('externalDocumentNo', SalesHeader."External Document No.");
            Result.Add('yourReference', SalesHeader."Your Reference");
            SalesLine.SetRange("Document Type", SalesHeader."Document Type");
            SalesLine.SetRange("Document No.", SalesHeader."No.");
            SalesLine.SetFilter(Type, '<>%1', SalesLine.Type::" ");
            if SalesLine.FindSet() then
                repeat
                    Lines.Add(SalesLineJson(SalesLine."No.", SalesLine.Description, SalesLine.Quantity, SalesLine."Unit of Measure Code"));
                until SalesLine.Next() = 0;
        end else begin
            InvoiceHeader.SetRange("Order No.", SalesOrderNo);
            if InvoiceHeader.FindLast() then begin
                Result.Add('state', 'invoiced');
                Result.Add('invoiceNo', InvoiceHeader."No.");
                Result.Add('customerNo', InvoiceHeader."Sell-to Customer No.");
                Result.Add('customerName', InvoiceHeader."Sell-to Customer Name");
                Result.Add('orderDate', DateText(InvoiceHeader."Order Date"));
                Result.Add('externalDocumentNo', InvoiceHeader."External Document No.");
                Result.Add('yourReference', InvoiceHeader."Your Reference");
                InvoiceLine.SetRange("Document No.", InvoiceHeader."No.");
                InvoiceLine.SetFilter(Type, '<>%1', InvoiceLine.Type::" ");
                if InvoiceLine.FindSet() then
                    repeat
                        Lines.Add(SalesLineJson(InvoiceLine."No.", InvoiceLine.Description, InvoiceLine.Quantity, InvoiceLine."Unit of Measure Code"));
                    until InvoiceLine.Next() = 0;
            end else
                Result.Add('state', 'unknown');
        end;
        Result.Add('lines', Lines);
        exit(Result);
    end;

    local procedure SalesLineJson(No: Code[20]; Description: Text; Quantity: Decimal; UnitOfMeasure: Code[10]): JsonObject
    var
        Line: JsonObject;
    begin
        Line.Add('no', No);
        Line.Add('description', Description);
        Line.Add('quantity', Quantity);
        Line.Add('unit', UnitOfMeasure);
        exit(Line);
    end;

    local procedure TextOr(Value: Text; Fallback: Text): Text
    begin
        if Value <> '' then
            exit(Value);
        exit(Fallback);
    end;

    local procedure DateText(Value: Date): Text
    begin
        if Value = 0D then
            exit('');
        exit(Format(Value, 0, 9));
    end;

    local procedure TimeText(Value: Time): Text
    begin
        if Value = 0T then
            exit('');
        exit(CopyStr(Format(Value, 0, 9), 1, 5));
    end;
}
