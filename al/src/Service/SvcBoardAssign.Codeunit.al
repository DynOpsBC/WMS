/// <summary>
/// Runs a technician assignment from the Service Management board through Codeunit.Run,
/// so a validation error is returned to the board instead of breaking the page.
/// </summary>
codeunit 72103 "DOPSWHS Svc Board Assign"
{
    Access = Internal;

    trigger OnRun()
    var
        Tech: Record "DOPSWHS Service Technician";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        if not Tech.Get(TechnicianUser) then
            Error(TechnicianNotFoundErr, TechnicianUser);
        Tech.TestField(Active, true);
        if ItemLineNo = 0 then
            ItemLineNo := Mgt.FirstServiceItemLineNo(OrderNo);
        Mgt.AssignTechnician(OrderNo, ItemLineNo, Tech."Resource No.", AllocationDate, AllocatedHours);
    end;

    procedure SetParameters(NewOrderNo: Code[20]; NewItemLineNo: Integer; NewTechnicianUser: Code[50]; NewAllocationDate: Date; NewHours: Decimal)
    begin
        OrderNo := NewOrderNo;
        ItemLineNo := NewItemLineNo;
        TechnicianUser := NewTechnicianUser;
        AllocationDate := NewAllocationDate;
        AllocatedHours := NewHours;
    end;

    var
        OrderNo: Code[20];
        ItemLineNo: Integer;
        TechnicianUser: Code[50];
        AllocationDate: Date;
        AllocatedHours: Decimal;
        TechnicianNotFoundErr: Label 'Technician %1 is not defined on the Service Technicians page.', Comment = '%1 = BC user name';
}
