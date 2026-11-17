/// <summary>
/// Printable summary of the service done for a sales order (or of one service order): what was
/// reported, who went, what was done, labor and parts, and every note typed along the way.
/// </summary>
page 72126 "DOPSWHS Service Summary"
{
    // A List page opens in place at full width; Card/Worksheet pages open as a narrow task page.
    PageType = List;
    SourceTable = "DOPSWHS Service Cue";
    SourceTableTemporary = true;
    Caption = 'Service Summary';
    ApplicationArea = DOPSWHSService;
    UsageCategory = None;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            usercontrol(Summary; "DOPSWHS Service Summary")
            {
                ApplicationArea = All;

                trigger ControlReady()
                begin
                    IsReady := true;
                    CurrPage.Summary.SetLocale(Format(GlobalLanguage(), 0, 9));
                    SendData();
                end;

                trigger OpenOrder(OrderNo: Text)
                var
                    Header: Record "Service Header";
                begin
                    if not Header.Get(Header."Document Type"::Order, CopyStr(OrderNo, 1, MaxStrLen(Header."No."))) then begin
                        Message(OrderClosedMsg, OrderNo);
                        exit;
                    end;
                    Page.RunModal(Page::"Service Order", Header);
                    SendData();
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
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
            action(ServiceLog)
            {
                ApplicationArea = All;
                Caption = 'Service Log';
                Image = Log;
                ToolTip = 'Open the log entries behind this summary.';

                trigger OnAction()
                var
                    Entry: Record "DOPSWHS Service Log Entry";
                begin
                    if ServiceOrderNo <> '' then
                        Entry.SetRange("Service Order No.", ServiceOrderNo)
                    else
                        Entry.SetRange("Sales Order No.", SalesOrderNo);
                    Page.Run(Page::"DOPSWHS Service Log", Entry);
                end;
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';
                actionref(Refresh_Promoted; Refresh) { }
                actionref(ServiceLog_Promoted; ServiceLog) { }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if Rec.IsEmpty() then begin
            Rec.Init();
            Rec.Insert();
        end;
    end;

    /// <summary>Summary of one service order (its sales order is shown when one is linked).</summary>
    procedure SetServiceOrder(NewServiceOrderNo: Code[20])
    begin
        ServiceOrderNo := NewServiceOrderNo;
        SalesOrderNo := '';
    end;

    /// <summary>Summary of every service order opened for a sales order.</summary>
    procedure SetSalesOrder(NewSalesOrderNo: Code[20])
    begin
        SalesOrderNo := NewSalesOrderNo;
        ServiceOrderNo := '';
    end;

    local procedure SendData()
    var
        SummaryData: Codeunit "DOPSWHS Service Summary Data";
    begin
        if IsReady then
            CurrPage.Summary.SetData(SummaryData.BuildJson(ServiceOrderNo, SalesOrderNo));
    end;

    var
        ServiceOrderNo: Code[20];
        SalesOrderNo: Code[20];
        IsReady: Boolean;
        OrderClosedMsg: Label 'Service order %1 is closed; it can no longer be opened.', Comment = '%1 = service order no.';
}
