/// <summary>Service log: every text typed for a service order and the steps of the job.</summary>
page 72125 "DOPSWHS Service Log"
{
    PageType = List;
    SourceTable = "DOPSWHS Service Log Entry";
    SourceTableView = sorting("Entry No.") order(descending);
    Caption = 'Service Log';
    ApplicationArea = DOPSWHSService;
    UsageCategory = History;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Entries)
            {
                field("Logged At"; Rec."Logged At") { ApplicationArea = All; ToolTip = 'When the text was entered or the step was done.'; }
                field("Service Order No."; Rec."Service Order No.") { ApplicationArea = All; ToolTip = 'The service order the entry belongs to.'; }
                field("Entry Type"; Rec."Entry Type") { ApplicationArea = All; StyleExpr = TypeStyle; ToolTip = 'What was entered: a note, the description, or a step of the job.'; }
                field("Entry Text"; Rec."Entry Text") { ApplicationArea = All; ToolTip = 'The text as it was typed.'; }
                field("Technician Name"; Rec."Technician Name") { ApplicationArea = All; ToolTip = 'The technician who made the entry.'; }
                field("Customer Name"; Rec."Customer Name") { ApplicationArea = All; ToolTip = 'The customer of the service order.'; }
                field("Service Item Description"; Rec."Service Item Description") { ApplicationArea = All; ToolTip = 'The equipment the entry is about.'; }
                field("Sales Order No."; Rec."Sales Order No.") { ApplicationArea = All; ToolTip = 'The sales order the service was opened for.'; }
                field("From Terminal"; Rec."From Terminal") { ApplicationArea = All; ToolTip = 'Entered on the handheld terminal; otherwise in Business Central.'; }
                field("User ID"; Rec."User ID") { ApplicationArea = All; ToolTip = 'The user who made the entry.'; }
                field("Customer No."; Rec."Customer No.") { ApplicationArea = All; Visible = false; ToolTip = 'The customer of the service order.'; }
                field("Service Item No."; Rec."Service Item No.") { ApplicationArea = All; Visible = false; ToolTip = 'The service item the entry is about.'; }
                field("Entry No."; Rec."Entry No.") { ApplicationArea = All; Visible = false; ToolTip = 'The number of the log entry.'; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ServiceSummary)
            {
                ApplicationArea = All;
                Caption = 'Service Summary';
                Image = Document;
                ToolTip = 'Open the summary of the selected service order.';

                trigger OnAction()
                var
                    Summary: Page "DOPSWHS Service Summary";
                begin
                    Rec.TestField("Service Order No.");
                    Summary.SetServiceOrder(Rec."Service Order No.");
                    Summary.Run();
                end;
            }
            action(SalesOrderSummary)
            {
                ApplicationArea = All;
                Caption = 'Sales Order Summary';
                Image = Sales;
                ToolTip = 'Open the summary of every service opened for the sales order of the selected entry.';

                trigger OnAction()
                var
                    Summary: Page "DOPSWHS Service Summary";
                begin
                    Rec.TestField("Sales Order No.");
                    Summary.SetSalesOrder(Rec."Sales Order No.");
                    Summary.Run();
                end;
            }
            action(ServiceOrder)
            {
                ApplicationArea = All;
                Caption = 'Service Order';
                Image = ServiceItem;
                ToolTip = 'Open the service order of the selected entry.';

                trigger OnAction()
                var
                    Header: Record "Service Header";
                begin
                    if Header.Get(Header."Document Type"::Order, Rec."Service Order No.") then
                        Page.Run(Page::"Service Order", Header)
                    else
                        Message(OrderClosedMsg, Rec."Service Order No.");
                end;
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';
                actionref(ServiceSummary_Promoted; ServiceSummary) { }
                actionref(SalesOrderSummary_Promoted; SalesOrderSummary) { }
                actionref(ServiceOrder_Promoted; ServiceOrder) { }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        // Typed texts stand out; steps of the job stay in the background.
        if Rec."Entry Type" in [Rec."Entry Type"::Note, Rec."Entry Type"::"Fault Note", Rec."Entry Type"::"Resolution Note",
            Rec."Entry Type"::"Internal Note", Rec."Entry Type"::"Order Description", Rec."Entry Type"::Created]
        then
            TypeStyle := 'Strong'
        else
            TypeStyle := 'Subordinate';
    end;

    var
        TypeStyle: Text;
        OrderClosedMsg: Label 'Service order %1 is closed; it can no longer be opened.', Comment = '%1 = service order no.';
}
