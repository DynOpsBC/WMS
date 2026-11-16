page 72103 "DOPSWHS Svc Assign Dialog"
{
    PageType = StandardDialog;
    Caption = 'Assign Technician';
    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'Assignment';
                field(ServiceItemLineNo; ItemLineNo)
                {
                    ApplicationArea = All;
                    Caption = 'Service Item Line No.';
                    trigger OnLookup(var Text: Text): Boolean
                    var
                        ItemLine: Record "Service Item Line";
                        LineNumbers: List of [Integer];
                        Choices: Text;
                        Selection: Integer;
                    begin
                        ItemLine.SetRange("Document Type", ItemLine."Document Type"::Order);
                        ItemLine.SetRange("Document No.", OrderNo);
                        if ItemLine.FindSet() then
                            repeat
                                LineNumbers.Add(ItemLine."Line No.");
                                if Choices <> '' then
                                    Choices += ',';
                                Choices += Format(ItemLine."Line No.") + ' - ' + ConvertStr(ItemLine.Description, ',', ' ');
                            until ItemLine.Next() = 0;
                        if Choices = '' then
                            exit(false);
                        Selection := StrMenu(Choices, 1, SelectItemLineLbl);
                        if Selection = 0 then
                            exit(false);
                        ItemLineNo := LineNumbers.Get(Selection);
                        UpdateItemDescription();
                        exit(true);
                    end;

                    trigger OnValidate()
                    begin
                        UpdateItemDescription();
                    end;
                }
                field(ServiceItem; ItemDescription)
                {
                    ApplicationArea = All;
                    Caption = 'Service Item';
                    Editable = false;
                }
                field(Technician; TechnicianUser)
                {
                    ApplicationArea = All;
                    Caption = 'Technician';
                    TableRelation = "DOPSWHS Service Technician"."User Name" where(Active = const(true));
                    trigger OnLookup(var Text: Text): Boolean
                    var
                        Tech: Record "DOPSWHS Service Technician";
                        Technicians: Page "DOPSWHS Service Technicians";
                    begin
                        Tech.SetRange(Active, true);
                        Technicians.SetTableView(Tech);
                        Technicians.LookupMode(true);
                        if Technicians.RunModal() = Action::LookupOK then begin
                            Technicians.GetRecord(Tech);
                            TechnicianUser := Tech."User Name";
                            exit(true);
                        end;
                    end;
                }
                field(AllocationDate; AssignDate) { ApplicationArea = All; Caption = 'Allocation Date'; }
                field(Hours; AssignHours) { ApplicationArea = All; Caption = 'Allocated Hours'; MinValue = 0; }
            }
        }
    }
    trigger OnOpenPage()
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        AssignDate := Mgt.LocalToday();
        AssignHours := 1;
    end;
    procedure SetOrder(NewOrderNo: Code[20])
    var
        ItemLine: Record "Service Item Line";
    begin
        OrderNo := NewOrderNo;
        ItemLine.SetRange("Document Type", ItemLine."Document Type"::Order);
        ItemLine.SetRange("Document No.", OrderNo);
        if ItemLine.FindFirst() then begin
            ItemLineNo := ItemLine."Line No.";
            UpdateItemDescription();
        end;
    end;

    local procedure UpdateItemDescription()
    var
        ItemLine: Record "Service Item Line";
    begin
        ItemDescription := '';
        if ItemLineNo = 0 then
            exit;
        if not ItemLine.Get(ItemLine."Document Type"::Order, OrderNo, ItemLineNo) then
            Error(ItemLineNotFoundErr, ItemLineNo, OrderNo);
        ItemDescription := CopyStr(DelChr(ItemLine."Service Item No." + ' ' + ItemLine.Description, '<>', ' '), 1, MaxStrLen(ItemDescription));
    end;
    procedure Assign()
    var
        Tech: Record "DOPSWHS Service Technician";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        if TechnicianUser = '' then
            Error(SelectTechnicianErr);
        Tech.Get(TechnicianUser);
        if ItemLineNo = 0 then
            ItemLineNo := Mgt.FirstServiceItemLineNo(OrderNo);
        Mgt.AssignTechnician(OrderNo, ItemLineNo, Tech."Resource No.", AssignDate, AssignHours);
    end;
    var
        SelectItemLineLbl: Label 'Select a service item line';
        SelectTechnicianErr: Label 'Select a technician before assigning the service order.';
        ItemLineNotFoundErr: Label 'Service item line %1 does not exist on service order %2.', Comment = '%1 = line no., %2 = order no.';
        OrderNo: Code[20];
        ItemLineNo: Integer;
        ItemDescription: Text[150];
        TechnicianUser: Code[50];
        AssignDate: Date;
        AssignHours: Decimal;
}
