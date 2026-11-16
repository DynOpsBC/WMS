permissionset 72100 "DOPSWHS SERVICE"
{
    Assignable = true;
    Caption = 'Servis Terminali';
    Permissions =
        tabledata "DOPSWHS Service Setup" = RIMD,
        table "DOPSWHS Service Setup" = X,
        tabledata "DOPSWHS Service Technician" = RIMD,
        table "DOPSWHS Service Technician" = X,
        tabledata "DOPSWHS Service Cue" = RIMD,
        table "DOPSWHS Service Cue" = X,
        codeunit "DOPSWHS Service Terminal Mgt" = X,
        codeunit "DOPSWHS Service Defaults" = X,
        tabledata "Service Header" = RIMD,
        tabledata "Service Item Line" = RIMD,
        tabledata "Service Line" = RIMD,
        tabledata "Service Order Allocation" = RIMD,
        tabledata "Service Comment Line" = RIMD,
        tabledata "Document Attachment" = RIMD,
        tabledata "Repair Status" = RIMD,
        tabledata "Fault Area" = R,
        tabledata "Symptom Code" = R,
        tabledata "Fault Code" = R,
        tabledata "Resolution Code" = R,
        tabledata "Work Type" = R,
        tabledata "Resource" = R,
        tabledata "Service Item" = R,
        tabledata "Service Mgt. Setup" = R,
        tabledata "Service Status Priority Setup" = R,
        tabledata "Unit of Measure" = R,
        tabledata Customer = R,
        tabledata Item = R,
        tabledata Location = R,
        codeunit "Service-Post" = X;
}
