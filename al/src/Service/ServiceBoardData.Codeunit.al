/// <summary>
/// Builds the JSON shown by the Service Management board (control add-in "DOPSWHS Service Board").
/// Reads the standard service documents only; nothing is written here.
/// </summary>
codeunit 72102 "DOPSWHS Service Board Data"
{
    Access = Internal;

    var
        ResourceNames: Dictionary of [Code[20], Text];
        RepairStatusTexts: Dictionary of [Code[10], Text];
        MaxOrdersTok: Label '500', Locked = true;

    procedure BuildJson(): Text
    var
        Header: Record "Service Header";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
        Root: JsonObject;
        Orders: JsonArray;
        LocalDate: Date;
        MaxOrders: Integer;
        Counter: Integer;
        Truncated: Boolean;
        Result: Text;
    begin
        Evaluate(MaxOrders, MaxOrdersTok);
        LocalDate := Mgt.LocalToday();
        Root.Add('today', Format(LocalDate, 0, 9));
        Root.Add('canAssign', IsDispatcher());

        // Open work first, so a long tail of finished-but-not-invoiced orders can never push
        // unassigned or overdue jobs off the board; finished orders fill the remaining room.
        Header.SetRange("Document Type", Header."Document Type"::Order);
        Header.SetFilter(Status, '<>%1', Header.Status::Finished);
        AddOrders(Header, Orders, LocalDate, MaxOrders, Counter, Truncated);
        Header.SetRange(Status, Header.Status::Finished);
        AddOrders(Header, Orders, LocalDate, MaxOrders, Counter, Truncated);

        Root.Add('orders', Orders);
        Root.Add('truncated', Truncated);
        Root.Add('technicians', TechniciansJson(LocalDate));
        Root.WriteTo(Result);
        exit(Result);
    end;

    local procedure AddOrders(var Header: Record "Service Header"; var Orders: JsonArray; LocalDate: Date; MaxOrders: Integer; var Counter: Integer; var Truncated: Boolean)
    begin
        Header.SetLoadFields("Document Type", "No.", "Customer No.", Name, City, Description, "Phone No.", Priority, Status,
            "Order Date", "Response Date", "Response Time");
        Header.Ascending(false);
        if not Header.FindSet() then
            exit;
        repeat
            if Counter >= MaxOrders then begin
                Truncated := true;
                exit;
            end;
            Orders.Add(OrderJson(Header, LocalDate));
            Counter += 1;
        until Header.Next() = 0;
    end;

    local procedure IsDispatcher(): Boolean
    var
        Tech: Record "DOPSWHS Service Technician";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        if not Mgt.TryCurrentTechnician(Tech) then
            exit(false);
        exit(Tech.Dispatcher);
    end;

    local procedure OrderJson(var Header: Record "Service Header"; LocalDate: Date): JsonObject
    var
        Allocation: Record "Service Order Allocation";
        Order: JsonObject;
        Names: JsonArray;
        ResourceNos: JsonArray;
        SeenResources: List of [Code[20]];
        HasActive: Boolean;
        Hours: Decimal;
    begin
        Order.Add('no', Header."No.");
        Order.Add('customerNo', Header."Customer No.");
        Order.Add('name', Header.Name);
        Order.Add('city', Header.City);
        Order.Add('description', Header.Description);
        Order.Add('phone', Header."Phone No.");
        Order.Add('priority', PriorityName(Header));
        Order.Add('orderDate', DateText(Header."Order Date"));
        Order.Add('responseDate', DateText(Header."Response Date"));
        Order.Add('responseTime', TimeText(Header."Response Time"));

        // Active allocations decide the stage; finished ones still show who did the job.
        Allocation.SetLoadFields("Resource No.", Status, "Allocated Hours");
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", Header."No.");
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        if Allocation.FindSet() then
            repeat
                if Allocation.Status = Allocation.Status::Active then begin
                    HasActive := true;
                    Hours += Allocation."Allocated Hours";
                end;
                if (Allocation."Resource No." <> '') and not SeenResources.Contains(Allocation."Resource No.") then begin
                    SeenResources.Add(Allocation."Resource No.");
                    ResourceNos.Add(Allocation."Resource No.");
                    Names.Add(ResourceName(Allocation."Resource No."));
                end;
            until Allocation.Next() = 0;
        Order.Add('technicians', Names);
        Order.Add('resourceNos', ResourceNos);
        Order.Add('hours', Hours);
        Order.Add('items', ItemLinesJson(Header));
        Order.Add('stage', StageName(Header, HasActive));
        Order.Add('overdue', (Header."Response Date" <> 0D) and (Header."Response Date" < LocalDate) and (Header.Status <> Header.Status::Finished));
        exit(Order);
    end;

    local procedure ItemLinesJson(var Header: Record "Service Header"): JsonArray
    var
        ItemLine: Record "Service Item Line";
        Items: JsonArray;
        Item: JsonObject;
    begin
        ItemLine.SetLoadFields("Document Type", "Document No.", "Line No.", "Service Item No.", Description, "Repair Status Code");
        ItemLine.SetRange("Document Type", Header."Document Type");
        ItemLine.SetRange("Document No.", Header."No.");
        if ItemLine.FindSet() then
            repeat
                Clear(Item);
                Item.Add('lineNo', ItemLine."Line No.");
                Item.Add('serviceItemNo', ItemLine."Service Item No.");
                Item.Add('description', ItemLine.Description);
                Item.Add('repairStatus', ItemLine."Repair Status Code");
                Item.Add('repairStatusText', RepairStatusText(ItemLine."Repair Status Code"));
                Items.Add(Item);
            until ItemLine.Next() = 0;
        exit(Items);
    end;

    local procedure StageName(var Header: Record "Service Header"; HasActive: Boolean): Text
    begin
        case Header.Status of
            Header.Status::Finished:
                if HasUnshippedLines(Header) then
                    exit('toship')
                else
                    exit('toinvoice');
            Header.Status::"On Hold":
                exit('onhold');
            Header.Status::"In Process":
                exit('inprogress');
        end;
        if HasActive then
            exit('assigned');
        exit('unassigned');
    end;

    /// <summary>
    /// True while something is still to be posted: a typed line with unshipped quantity, or no
    /// typed line at all (the office has to look at such an order before it can be closed).
    /// </summary>
    local procedure HasUnshippedLines(var Header: Record "Service Header"): Boolean
    var
        ServiceLine: Record "Service Line";
    begin
        ServiceLine.SetRange("Document Type", Header."Document Type");
        ServiceLine.SetRange("Document No.", Header."No.");
        ServiceLine.SetFilter(Type, '<>%1', ServiceLine.Type::" ");
        if ServiceLine.IsEmpty() then
            exit(true);
        ServiceLine.SetFilter("Qty. to Ship", '<>0');
        if not ServiceLine.IsEmpty() then
            exit(true);
        ServiceLine.SetRange("Qty. to Ship");
        ServiceLine.SetLoadFields(Quantity, "Quantity Shipped");
        if ServiceLine.FindSet() then
            repeat
                if ServiceLine.Quantity > ServiceLine."Quantity Shipped" then
                    exit(true);
            until ServiceLine.Next() = 0;
        exit(false);
    end;

    local procedure PriorityName(var Header: Record "Service Header"): Text
    begin
        case Header.Priority of
            Header.Priority::High:
                exit('high');
            Header.Priority::Medium:
                exit('medium');
        end;
        exit('low');
    end;

    local procedure TechniciansJson(LocalDate: Date): JsonArray
    var
        Tech: Record "DOPSWHS Service Technician";
        Allocation: Record "Service Order Allocation";
        Techs: JsonArray;
        Entry: JsonObject;
        OpenOrders: List of [Code[20]];
    begin
        Tech.SetRange(Active, true);
        if Tech.FindSet() then
            repeat
                Tech.CalcFields("Resource Name");
                Clear(Entry);
                Entry.Add('user', Tech."User Name");
                Entry.Add('resourceNo', Tech."Resource No.");
                if Tech."Resource Name" <> '' then
                    Entry.Add('name', Tech."Resource Name")
                else
                    Entry.Add('name', Tech."User Name");
                Entry.Add('dispatcher', Tech.Dispatcher);

                // "Open jobs" counts orders, not allocation lines of multi-item orders.
                Clear(OpenOrders);
                Allocation.Reset();
                Allocation.SetLoadFields("Document No.");
                Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
                Allocation.SetRange("Resource No.", Tech."Resource No.");
                Allocation.SetRange(Status, Allocation.Status::Active);
                if Allocation.FindSet() then
                    repeat
                        if not OpenOrders.Contains(Allocation."Document No.") then
                            OpenOrders.Add(Allocation."Document No.");
                    until Allocation.Next() = 0;
                Entry.Add('activeJobs', OpenOrders.Count());
                Allocation.SetRange("Allocation Date", LocalDate);
                Allocation.CalcSums("Allocated Hours");
                Entry.Add('hoursToday', Allocation."Allocated Hours");
                Techs.Add(Entry);
            until Tech.Next() = 0;
        exit(Techs);
    end;

    local procedure ResourceName(ResourceNo: Code[20]): Text
    var
        Res: Record Resource;
        Name: Text;
    begin
        if ResourceNames.Get(ResourceNo, Name) then
            exit(Name);
        Res.SetLoadFields(Name);
        if Res.Get(ResourceNo) and (Res.Name <> '') then
            Name := Res.Name
        else
            Name := ResourceNo;
        ResourceNames.Add(ResourceNo, Name);
        exit(Name);
    end;

    local procedure RepairStatusText(StatusCode: Code[10]): Text
    var
        RepairStatus: Record "Repair Status";
        Description: Text;
    begin
        if StatusCode = '' then
            exit('');
        if RepairStatusTexts.Get(StatusCode, Description) then
            exit(Description);
        RepairStatus.SetLoadFields(Description);
        if RepairStatus.Get(StatusCode) then
            Description := RepairStatus.Description;
        RepairStatusTexts.Add(StatusCode, Description);
        exit(Description);
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
