/// <summary>
/// Writes the service log ("DOPSWHS Service Log Entry"). The terminal procedures log their own
/// full texts; the subscribers below catch what the office types in Business Central itself.
/// Logging never blocks service work: a user who cannot write the log is skipped silently.
/// </summary>
codeunit 72105 "DOPSWHS Service Log"
{
    SingleInstance = true;
    // The subscribers run for every user who touches a service comment or description, also users
    // without any BCWMS permission set; they must never see a permission error because of the log.
    InherentEntitlements = X;
    InherentPermissions = X;
    Permissions = tabledata "DOPSWHS Service Log Entry" = RIM,
        tabledata "DOPSWHS Service Setup" = R,
        tabledata "DOPSWHS Service Technician" = R,
        tabledata "Service Header" = R,
        tabledata "Service Item Line" = R,
        tabledata "Service Order Allocation" = R,
        tabledata Resource = R;

    var
        Suppressed: Boolean;

    /// <summary>
    /// The terminal splits a long note into 80-character comment lines and logs the whole text
    /// once; while suppressed the comment line subscribers stay quiet.
    /// </summary>
    procedure Suppress(NewValue: Boolean)
    begin
        Suppressed := NewValue;
    end;

    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Log Entry", 'RIM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Setup", 'R')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Technician", 'R')]
    procedure Add(OrderNo: Code[20]; SILineNo: Integer; EntryType: Enum "DOPSWHS Service Log Type"; EntryText: Text)
    var
        Entry: Record "DOPSWHS Service Log Entry";
        Header: Record "Service Header";
        ItemLine: Record "Service Item Line";
        Tech: Record "DOPSWHS Service Technician";
    begin
        if not IsOn() then
            exit;
        Entry.Init();
        Entry."Logged At" := CurrentDateTime();
        Entry."User ID" := CopyStr(UserId(), 1, MaxStrLen(Entry."User ID"));
        if Tech.ReadPermission() and Tech.Get(UserId()) then begin
            Tech.CalcFields("Resource Name");
            Entry."Resource No." := Tech."Resource No.";
            Entry."Technician Name" := CopyStr(Tech."Resource Name", 1, MaxStrLen(Entry."Technician Name"));
        end;
        Entry."Service Order No." := OrderNo;
        Entry."Service Item Line No." := SILineNo;
        if Header.Get(Header."Document Type"::Order, OrderNo) then begin
            Entry."Customer No." := Header."Customer No.";
            Entry."Customer Name" := Header.Name;
            Entry."Sales Order No." := Header."DOPSWHS Sales Order No.";
            if SILineNo = 0 then begin
                ItemLine.SetRange("Document Type", Header."Document Type");
                ItemLine.SetRange("Document No.", OrderNo);
                if ItemLine.Count() = 1 then
                    ItemLine.FindFirst();
            end else
                if not ItemLine.Get(Header."Document Type", OrderNo, SILineNo) then
                    Clear(ItemLine);
            Entry."Service Item No." := ItemLine."Service Item No.";
            Entry."Service Item Description" := ItemLine.Description;
        end;
        Entry."Entry Type" := EntryType;
        Entry."Entry Text" := CopyStr(EntryText, 1, MaxStrLen(Entry."Entry Text"));
        Entry."From Terminal" := CurrentClientType() in [ClientType::Api, ClientType::ODataV4];
        Entry.Insert(true);
    end;

    /// <summary>The sales order was set or changed after the first entries were written.</summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Log Entry", 'RIM')]
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Setup", 'R')]
    procedure SetSalesOrder(OrderNo: Code[20]; SalesOrderNo: Code[20])
    var
        Entry: Record "DOPSWHS Service Log Entry";
    begin
        if (OrderNo = '') or not IsOn() then
            exit;
        Entry.SetRange("Service Order No.", OrderNo);
        Entry.SetFilter("Sales Order No.", '<>%1', SalesOrderNo);
        if not Entry.IsEmpty() then
            Entry.ModifyAll("Sales Order No.", SalesOrderNo);
    end;

    local procedure IsOn(): Boolean
    var
        Entry: Record "DOPSWHS Service Log Entry";
    begin
        // ReadPermission, not WritePermission: write also asks for delete, which nobody has on a log.
        // Whoever can read the log here (permission set or the inherent permission above) can add to it.
        if not Entry.ReadPermission() then
            exit(false);
        exit(IsServiceEnabled());
    end;

    /// <summary>
    /// True where Service Terminal Setup exists and is enabled. Warehouse-only customers run the
    /// same build: for them nothing is logged and the standard service pages read nothing extra.
    /// </summary>
    [InherentPermissions(PermissionObjectType::TableData, Database::"DOPSWHS Service Setup", 'R')]
    procedure IsServiceEnabled(): Boolean
    var
        Setup: Record "DOPSWHS Service Setup";
    begin
        if not Setup.ReadPermission() then
            exit(false);
        if not Setup.Get('') then
            exit(false);
        exit(Setup.Enabled);
    end;

    /// <summary>
    /// Technicians of a service order for the standard Service Order pages (active and finished
    /// allocations). Lives here, not in the terminal codeunit, so the pages of users without a
    /// BCWMS permission set keep working.
    /// </summary>
    procedure TechnicianNames(OrderNo: Code[20]): Text
    var
        Allocation: Record "Service Order Allocation";
        Res: Record Resource;
        Seen: List of [Code[20]];
        Names: Text;
    begin
        if (OrderNo = '') or not Allocation.ReadPermission() or not Res.ReadPermission() then
            exit('');
        Allocation.SetLoadFields("Resource No.");
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", OrderNo);
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        Allocation.SetFilter("Resource No.", '<>%1', '');
        Res.SetLoadFields(Name);
        if Allocation.FindSet() then
            repeat
                if not Seen.Contains(Allocation."Resource No.") then begin
                    Seen.Add(Allocation."Resource No.");
                    if Names <> '' then
                        Names += ', ';
                    if Res.Get(Allocation."Resource No.") and (Res.Name <> '') then
                        Names += Res.Name
                    else
                        Names += Allocation."Resource No.";
                end;
            until Allocation.Next() = 0;
        exit(Names);
    end;

    local procedure NoteType(Comment: Record "Service Comment Line"): Enum "DOPSWHS Service Log Type"
    begin
        case Comment.Type of
            Comment.Type::Fault:
                exit(Enum::"DOPSWHS Service Log Type"::"Fault Note");
            Comment.Type::Resolution:
                exit(Enum::"DOPSWHS Service Log Type"::"Resolution Note");
            Comment.Type::Internal:
                exit(Enum::"DOPSWHS Service Log Type"::"Internal Note");
        end;
        exit(Enum::"DOPSWHS Service Log Type"::Note);
    end;

    local procedure IsOrderComment(Comment: Record "Service Comment Line"): Boolean
    begin
        if Comment.IsTemporary() or Suppressed or (Comment.Comment = '') then
            exit(false);
        exit((Comment."Table Name" = Comment."Table Name"::"Service Header") and
            (Comment."Table Subtype" = Comment."Table Subtype"::"1"));
    end;

    [EventSubscriber(ObjectType::Table, Database::"Service Comment Line", OnAfterInsertEvent, '', false, false)]
    local procedure LogCommentInsert(var Rec: Record "Service Comment Line")
    begin
        if IsOrderComment(Rec) then
            Add(Rec."No.", Rec."Table Line No.", NoteType(Rec), Rec.Comment);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Service Comment Line", OnAfterModifyEvent, '', false, false)]
    local procedure LogCommentModify(var Rec: Record "Service Comment Line"; var xRec: Record "Service Comment Line")
    begin
        if IsOrderComment(Rec) and (Rec.Comment <> xRec.Comment) then
            Add(Rec."No.", Rec."Table Line No.", NoteType(Rec), Rec.Comment);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Service Header", OnAfterValidateEvent, Description, false, false)]
    local procedure LogDescription(var Rec: Record "Service Header"; var xRec: Record "Service Header")
    begin
        if Rec.IsTemporary() or Suppressed then
            exit;
        if (Rec."Document Type" <> Rec."Document Type"::Order) or (Rec."No." = '') then
            exit;
        if (Rec.Description = '') or (Rec.Description = xRec.Description) then
            exit;
        Add(Rec."No.", 0, Enum::"DOPSWHS Service Log Type"::"Order Description", Rec.Description);
    end;
}
