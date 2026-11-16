page 72104 "DOPSWHS Service Dispatch Cue"
{
    PageType = CardPart;
    SourceTable = "DOPSWHS Service Cue";
    SourceTableTemporary = true;
    Caption = 'Service Overview';
    Editable = false;
    layout
    {
        area(Content)
        {
            cuegroup(ServiceOrders)
            {
                Caption = 'Service Orders';
                field(Pending; Rec."Pending")
                {
                    ApplicationArea = All;
                    Caption = 'Pending';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(0);
                    end;
                }
                field(InProcess; Rec."In Process")
                {
                    ApplicationArea = All;
                    Caption = 'In Process';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(1);
                    end;
                }
                field(OnHold; Rec."On Hold")
                {
                    ApplicationArea = All;
                    Caption = 'On Hold';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(2);
                    end;
                }
                field(Finished; Rec."Finished")
                {
                    ApplicationArea = All;
                    Caption = 'Finished';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(3);
                    end;
                }
                field(Unassigned; Rec."Unassigned")
                {
                    ApplicationArea = All;
                    Caption = 'Unassigned';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(4);
                    end;
                }
                field(Overdue; Rec."Overdue")
                {
                    ApplicationArea = All;
                    Caption = 'Overdue';
                    trigger OnDrillDown()
                    begin
                        OpenOrders(5);
                    end;
                }
            }
        }
    }
    trigger OnOpenPage()
    begin
        Rec.Init();
        Rec.Insert();
        // Blank response dates are not overdue.
        Rec.SetRange("Date Filter", DMY2Date(1, 1, 2000), Today() - 1);
    end;
    trigger OnAfterGetRecord()
    var
        Header: Record "Service Header";
    begin
        Rec.Unassigned := 0;
        Header.SetRange("Document Type", Header."Document Type"::Order);
        Header.SetFilter(Status, '<>%1', Header.Status::Finished);
        if Header.FindSet() then
            repeat
                if not HasAllocation(Header."No.") then
                    Rec.Unassigned += 1;
            until Header.Next() = 0;
    end;
    local procedure HasAllocation(OrderNo: Code[20]): Boolean
    var
        Allocation: Record "Service Order Allocation";
    begin
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", OrderNo);
        Allocation.SetRange(Posted, false);
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        exit(not Allocation.IsEmpty());
    end;
    local procedure UnassignedFilter(): Text
    var
        Header: Record "Service Header";
        Filter: TextBuilder;
    begin
        Header.SetRange("Document Type", Header."Document Type"::Order);
        Header.SetFilter(Status, '<>%1', Header.Status::Finished);
        if Header.FindSet() then
            repeat
                if not HasAllocation(Header."No.") then begin
                    if Filter.Length() > 0 then
                        Filter.Append('|');
                    Filter.Append('''' + Header."No." + '''');
                end;
            until Header.Next() = 0;
        if Filter.Length() = 0 then
            exit('''''');
        exit(Filter.ToText());
    end;

    local procedure OpenOrders(Kind: Integer)
    var
        Header: Record "Service Header";
        Dispatch: Page "DOPSWHS Service Dispatch";
    begin
        Header.SetRange("Document Type", Header."Document Type"::Order);
        case Kind of
            0: Header.SetRange(Status, Header.Status::Pending);
            1: Header.SetRange(Status, Header.Status::"In Process");
            2: Header.SetRange(Status, Header.Status::"On Hold");
            3: Header.SetRange(Status, Header.Status::Finished);
            4:
                begin
                    Header.SetFilter(Status, '<>%1', Header.Status::Finished);
                    Header.SetFilter("No.", UnassignedFilter());
                end;
            5:
                begin
                    Header.SetFilter(Status, '<>%1', Header.Status::Finished);
                    Header.SetRange("Response Date", DMY2Date(1, 1, 2000), Today() - 1);
                end;
        end;
        Dispatch.SetTableView(Header);
        Dispatch.Run();
    end;
}
