page 72102 "DOPSWHS Service Dispatch"
{
    PageType = List;
    SourceTable = "Service Header";
    SourceTableView = where("Document Type" = const(Order));
    Caption = 'Service Management';
    UsageCategory = Lists;
    ApplicationArea = All;
    Editable = false;
    CardPageId = "Service Order";
    layout
    {
        area(Content)
        {
            repeater(Orders)
            {
                field(No; Rec."No.") { ApplicationArea = All; Caption = 'No.';  }
                field(CustomerNo; Rec."Customer No.") { ApplicationArea = All; Caption = 'Customer No.';  }
                field(Name; Rec."Name") { ApplicationArea = All; Caption = 'Name';  }
                field(City; Rec."City") { ApplicationArea = All; Caption = 'City';  }
                field(Description; Rec."Description") { ApplicationArea = All; Caption = 'Description';  }
                field(Status; Rec."Status") { ApplicationArea = All; Caption = 'Status';  }
                field(Priority; Rec."Priority") { ApplicationArea = All; Caption = 'Priority';  }
                field(OrderDate; Rec."Order Date") { ApplicationArea = All; Caption = 'Order Date';  }
                field(ResponseDate; Rec."Response Date") { ApplicationArea = All; Caption = 'Response Date';  }
                field(ResponseTime; Rec."Response Time") { ApplicationArea = All; Caption = 'Response Time';  }
                field(TechnicianNamesField; TechnicianNames) { ApplicationArea = All; Caption = 'Technicians';  }
                field(AllocatedHours; Hours) { ApplicationArea = All; Caption = 'Allocated Hours';  }
                field(RepairStatus; RepairStatus) { ApplicationArea = All; Caption = 'Repair Status';  }
                field(Overdue; IsOverdue) { ApplicationArea = All; Caption = 'Overdue'; StyleExpr = DelayStyle; }
            }
        }
        area(FactBoxes)
        {
            part(ServiceCues; "DOPSWHS Service Dispatch Cue") { ApplicationArea = All; }
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
            action(AssignTechnician)
            {
                ApplicationArea = All;
                Caption = 'Assign Technician';
                Image = Resource;
                trigger OnAction()
                var
                    AssignDialog: Page "DOPSWHS Svc Assign Dialog";
                begin
                    Mgt.AssertDispatcher();
                    AssignDialog.SetOrder(Rec."No.");
                    if AssignDialog.RunModal() = Action::OK then begin
                        AssignDialog.Assign();
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(ResourceAllocations)
            {
                ApplicationArea = All;
                Caption = 'Resource Allocations';
                RunObject = page "Resource Allocations";
                RunPageLink = "Document Type" = const(Order), "Document No." = field("No.");
            }
            action(OpenOrder)
            {
                ApplicationArea = All;
                Caption = 'Open Service Order';
                RunObject = page "Service Order";
                RunPageLink = "Document Type" = field("Document Type"), "No." = field("No.");
            }
            action(Shipments)
            {
                ApplicationArea = All;
                Caption = 'Posted Service Shipments';
                RunObject = page "Posted Service Shipments";
                RunPageLink = "Order No." = field("No.");
            }
            action(ServiceItems) { ApplicationArea = All; Caption = 'Service Items'; RunObject = page "Service Item List"; }
            action(Technicians) { ApplicationArea = All; Caption = 'Service Technicians'; RunObject = page "DOPSWHS Service Technicians"; }
            action(Setup) { ApplicationArea = All; Caption = 'Service Terminal Setup'; RunObject = page "DOPSWHS Service Setup"; }
            action(RefreshList)
            {
                ApplicationArea = All;
                Caption = 'Refresh';
                Image = Refresh;
                trigger OnAction()
                begin
                    CurrPage.Update(false);
                end;
            }
            action(CreateDefaults)
            {
                ApplicationArea = All;
                Caption = 'Create Default Service Codes';
                Image = Setup;
                trigger OnAction()
                var
                    Defaults: Codeunit "DOPSWHS Service Defaults";
                begin
                    Defaults.CreateMissingDefaults();
                end;
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';
                actionref(NewOrder_Promoted; NewOrder) { }
                actionref(AssignTechnician_Promoted; AssignTechnician) { }
                actionref(OpenOrder_Promoted; OpenOrder) { }
                actionref(ResourceAllocations_Promoted; ResourceAllocations) { }
            }
            group(Category_Related)
            {
                Caption = 'Related';
                actionref(Shipments_Promoted; Shipments) { }
                actionref(Technicians_Promoted; Technicians) { }
                actionref(Setup_Promoted; Setup) { }
            }
        }
    }
    procedure SetRecordSet(var Header: Record "Service Header")
    begin
        Rec.Copy(Header);
    end;
    trigger OnOpenPage()
    begin
        // Preserve explicit drilldown filters, including Finished.
        if Rec.GetFilter(Status) = '' then
            Rec.SetFilter(Status, '<>%1', Rec.Status::Finished);
        // Newest orders first.
        Rec.Ascending(false);
    end;
    trigger OnAfterGetRecord()
    var
        ItemLine: Record "Service Item Line";
    begin
        TechnicianNames := Mgt.TechnicianNames(Rec."No.");
        Hours := Mgt.AllocatedHours(Rec."No.");
        Clear(RepairStatus);
        ItemLine.SetRange("Document Type", Rec."Document Type");
        ItemLine.SetRange("Document No.", Rec."No.");
        if ItemLine.FindFirst() then
            RepairStatus := ItemLine."Repair Status Code";
        IsOverdue := (Rec."Response Date" <> 0D) and (Rec."Response Date" < Mgt.LocalToday()) and (Rec.Status <> Rec.Status::Finished);
        Clear(DelayStyle);
        if IsOverdue then
            DelayStyle := 'Unfavorable';
    end;
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
        TechnicianNames: Text;
        Hours: Decimal;
        RepairStatus: Code[10];
        IsOverdue: Boolean;
        DelayStyle: Text;
}
