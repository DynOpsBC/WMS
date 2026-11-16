page 72120 "DOPSWHS Service Board"
{
    // A List page opens in place at full width; Card/Worksheet pages open as a narrow task page.
    PageType = List;
    SourceTable = "DOPSWHS Service Cue";
    SourceTableTemporary = true;
    Caption = 'Service Management';
    // Searchable only where service is enabled; controls and actions set ApplicationArea = All.
    ApplicationArea = DOPSWHSService;
    UsageCategory = Tasks;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            usercontrol(Board; "DOPSWHS Service Board")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    CurrPage.Board.SetLocale(Format(GlobalLanguage(), 0, 9));
                    SendData();
                end;

                trigger RequestRefresh()
                begin
                    SendData();
                end;

                trigger OpenOrder(OrderNo: Text)
                var
                    Header: Record "Service Header";
                begin
                    if not Header.Get(Header."Document Type"::Order, CopyStr(OrderNo, 1, MaxStrLen(Header."No."))) then begin
                        CurrPage.Board.ShowMessage(StrSubstNo(OrderNotFoundErr, OrderNo), true);
                        SendData();
                        exit;
                    end;
                    Page.RunModal(Page::"Service Order", Header);
                    SendData();
                end;

                trigger AssignTechnician(OrderNo: Text; ItemLineNo: Integer; TechnicianUser: Text; AllocationDate: Text; Hours: Text)
                var
                    Assign: Codeunit "DOPSWHS Svc Board Assign";
                    AssignDate: Date;
                    AssignHours: Decimal;
                begin
                    if not Evaluate(AssignDate, AllocationDate, 9) then begin
                        CurrPage.Board.ShowMessage(InvalidDateErr, true);
                        exit;
                    end;
                    if not Evaluate(AssignHours, Hours, 9) then begin
                        CurrPage.Board.ShowMessage(InvalidHoursErr, true);
                        exit;
                    end;
                    Assign.SetParameters(CopyStr(OrderNo, 1, 20), ItemLineNo, CopyStr(TechnicianUser, 1, 50), AssignDate, AssignHours);
                    Commit();
                    if not Assign.Run() then begin
                        CurrPage.Board.ShowMessage(GetLastErrorText(), true);
                        exit;
                    end;
                    CurrPage.Board.AssignDone();
                    SendData();
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(NewOrder)
            {
                ApplicationArea = All;
                Caption = 'New Service Order';
                Image = New;
                RunObject = page "Service Order";
                RunPageMode = Create;
            }
            action(Refresh)
            {
                ApplicationArea = All;
                Caption = 'Refresh';
                Image = Refresh;
                trigger OnAction()
                begin
                    SendData();
                end;
            }
            action(ListView)
            {
                ApplicationArea = All;
                Caption = 'List View';
                Image = List;
                RunObject = page "DOPSWHS Service Dispatch";
            }
            action(ServiceOrders) { ApplicationArea = All; Caption = 'Service Orders'; Image = Document; RunObject = page "Service Orders"; }
            action(Shipments) { ApplicationArea = All; Caption = 'Posted Service Shipments'; Image = PostedShipment; RunObject = page "Posted Service Shipments"; }
            action(ServiceItems) { ApplicationArea = All; Caption = 'Service Items'; Image = ServiceItem; RunObject = page "Service Item List"; }
            action(Technicians) { ApplicationArea = All; Caption = 'Service Technicians'; Image = Resource; RunObject = page "DOPSWHS Service Technicians"; }
            action(Setup) { ApplicationArea = All; Caption = 'Service Terminal Setup'; Image = Setup; RunObject = page "DOPSWHS Service Setup"; }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';
                actionref(NewOrder_Promoted; NewOrder) { }
                actionref(Refresh_Promoted; Refresh) { }
                actionref(ListView_Promoted; ListView) { }
            }
            group(Category_Related)
            {
                Caption = 'Related';
                actionref(ServiceOrders_Promoted; ServiceOrders) { }
                actionref(Shipments_Promoted; Shipments) { }
                actionref(ServiceItems_Promoted; ServiceItems) { }
                actionref(Technicians_Promoted; Technicians) { }
                actionref(Setup_Promoted; Setup) { }
            }
        }
    }

    trigger OnOpenPage()
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
        AppArea: Codeunit "DOPSWHS Service App Area";
    begin
        Mgt.EnsureSetup();
        AppArea.Sync();
        // The worksheet needs one (temporary) row; the board itself reads its own data.
        if Rec.IsEmpty() then begin
            Rec.Init();
            Rec.Insert();
        end;
    end;

    local procedure SendData()
    var
        BoardData: Codeunit "DOPSWHS Service Board Data";
    begin
        CurrPage.Board.SetData(BoardData.BuildJson());
    end;

    var
        OrderNotFoundErr: Label 'Service order %1 no longer exists.', Comment = '%1 = service order no.';
        InvalidDateErr: Label 'Enter a valid allocation date.';
        InvalidHoursErr: Label 'Enter the planned hours as a number, for example 1.5.';
}
