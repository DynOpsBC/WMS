// Shows on the standard service and sales documents what the terminal knows: who works on the job,
// which sales order the service is for, and the log and summary behind it. Everything here uses
// the DOPSWHSService application area, so warehouse-only customers see no change.
pageextension 72122 "DOPSWHS Svc Order Card" extends "Service Order"
{
    layout
    {
        // Right under the description: who is on the job is the first thing the office looks for.
        addafter(Description)
        {
            field(DOPSWHSTechnicians; TechnicianNames)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Technician';
                Editable = false;
                Importance = Promoted;
                ToolTip = 'The technicians who work or worked on this service order.';

                trigger OnDrillDown()
                begin
                    ShowAllocations(Rec."No.");
                end;
            }
            field("DOPSWHS Sales Order No."; Rec."DOPSWHS Sales Order No.")
            {
                ApplicationArea = DOPSWHSService;
                Importance = Promoted;
                ToolTip = 'The sales order this service is for. The service summary is prepared with reference to it.';
            }
        }
    }
    actions
    {
        addlast(processing)
        {
            action(DOPSWHSSummary)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Summary';
                Image = Document;
                ToolTip = 'Open the printable summary of this service: reported problem, technician, work done, labor, parts and notes.';

                trigger OnAction()
                var
                    Summary: Page "DOPSWHS Service Summary";
                begin
                    Summary.SetServiceOrder(Rec."No.");
                    Summary.Run();
                end;
            }
            action(DOPSWHSLog)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Log';
                Image = Log;
                ToolTip = 'Show every text entered for this service order and the steps of the job.';

                trigger OnAction()
                var
                    Entry: Record "DOPSWHS Service Log Entry";
                begin
                    Entry.SetRange("Service Order No.", Rec."No.");
                    Page.Run(Page::"DOPSWHS Service Log", Entry);
                end;
            }
        }
        addlast(Promoted)
        {
            group(DOPSWHSServiceGroup)
            {
                Caption = 'Service Terminal';
                actionref(DOPSWHSSummary_Promoted; DOPSWHSSummary) { }
                actionref(DOPSWHSLog_Promoted; DOPSWHSLog) { }
            }
        }
    }

    trigger OnOpenPage()
    var
        ServiceLog: Codeunit "DOPSWHS Service Log";
    begin
        ServiceOn := ServiceLog.IsServiceEnabled();
    end;

    trigger OnAfterGetCurrRecord()
    var
        ServiceLog: Codeunit "DOPSWHS Service Log";
    begin
        // Warehouse-only customers run the same build: nothing is read for them.
        if ServiceOn then
            TechnicianNames := ServiceLog.TechnicianNames(Rec."No.");
    end;

    local procedure ShowAllocations(OrderNo: Code[20])
    var
        Allocation: Record "Service Order Allocation";
    begin
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", OrderNo);
        Page.Run(0, Allocation);
    end;

    var
        TechnicianNames: Text;
        ServiceOn: Boolean;
}

pageextension 72123 "DOPSWHS Svc Order List" extends "Service Orders"
{
    layout
    {
        addafter(Name)
        {
            field(DOPSWHSTechnicians; TechnicianNames)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Technician';
                Editable = false;
                ToolTip = 'The technicians who work or worked on the service order.';
            }
            field("DOPSWHS Sales Order No."; Rec."DOPSWHS Sales Order No.")
            {
                ApplicationArea = DOPSWHSService;
                ToolTip = 'The sales order the service is for.';
            }
        }
    }
    actions
    {
        addlast(processing)
        {
            action(DOPSWHSSummary)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Summary';
                Image = Document;
                ToolTip = 'Open the printable summary of the selected service order.';

                trigger OnAction()
                var
                    Summary: Page "DOPSWHS Service Summary";
                begin
                    Summary.SetServiceOrder(Rec."No.");
                    Summary.Run();
                end;
            }
            action(DOPSWHSLog)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Log';
                Image = Log;
                RunObject = page "DOPSWHS Service Log";
                ToolTip = 'Show every text entered for service orders and the steps of the jobs.';
            }
        }
    }

    trigger OnOpenPage()
    var
        ServiceLog: Codeunit "DOPSWHS Service Log";
    begin
        ServiceOn := ServiceLog.IsServiceEnabled();
    end;

    trigger OnAfterGetRecord()
    var
        ServiceLog: Codeunit "DOPSWHS Service Log";
    begin
        if ServiceOn then
            TechnicianNames := ServiceLog.TechnicianNames(Rec."No.");
    end;

    var
        TechnicianNames: Text;
        ServiceOn: Boolean;
}

pageextension 72124 "DOPSWHS Svc Sales Order" extends "Sales Order"
{
    actions
    {
        addlast(processing)
        {
            group(DOPSWHSService)
            {
                Caption = 'Service';
                Image = ServiceItem;

                action(DOPSWHSServiceSummary)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Service Summary';
                    Image = Document;
                    ToolTip = 'Open the summary of every service done for this sales order.';

                    trigger OnAction()
                    var
                        Summary: Page "DOPSWHS Service Summary";
                    begin
                        Summary.SetSalesOrder(Rec."No.");
                        Summary.Run();
                    end;
                }
                action(DOPSWHSNewServiceOrder)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'New Service Order';
                    Image = NewOrder;
                    ToolTip = 'Open a service order for the customer of this sales order; the sales order number is kept on it.';

                    trigger OnAction()
                    var
                        ServiceHeader: Record "Service Header";
                    begin
                        Rec.TestField("Sell-to Customer No.");
                        ServiceHeader.Init();
                        ServiceHeader."Document Type" := ServiceHeader."Document Type"::Order;
                        ServiceHeader.Insert(true);
                        ServiceHeader.Validate("Customer No.", Rec."Sell-to Customer No.");
                        ServiceHeader.Validate("DOPSWHS Sales Order No.", Rec."No.");
                        ServiceHeader.Modify(true);
                        Commit();
                        Page.Run(Page::"Service Order", ServiceHeader);
                    end;
                }
            }
        }
        addlast(Promoted)
        {
            group(DOPSWHSServicePromoted)
            {
                Caption = 'Service';
                actionref(DOPSWHSServiceSummary_Promoted; DOPSWHSServiceSummary) { }
                actionref(DOPSWHSNewServiceOrder_Promoted; DOPSWHSNewServiceOrder) { }
            }
        }
    }
}
