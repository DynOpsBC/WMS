codeunit 72100 "DOPSWHS Service Terminal Mgt"
{
    Permissions = tabledata "Service Header" = RIMD,
        tabledata "Service Item Line" = RIMD,
        tabledata "Service Line" = RIMD,
        tabledata "Service Order Allocation" = RIMD,
        tabledata "Service Comment Line" = RIMD,
        tabledata "Document Attachment" = RIMD,
        tabledata "Repair Status" = RIMD,
        tabledata "DOPSWHS Service Setup" = RI,
        tabledata "DOPSWHS Service Technician" = R,
        tabledata "Fault Code" = RI,
        tabledata "Service Mgt. Setup" = R,
        tabledata "Fault Area" = R,
        tabledata "Symptom Code" = R,
        tabledata "Resolution Code" = R,
        tabledata Resource = R,
        tabledata "Service Item" = R,
        tabledata "Work Type" = R,
        tabledata Location = R;

    procedure EnsureSetup()
    var
        Setup: Record "DOPSWHS Service Setup";
    begin
        Setup.GetSetup();
    end;

    procedure CurrentTechnician(var Tech: Record "DOPSWHS Service Technician")
    begin
        if not TryCurrentTechnician(Tech) then
            Error(NoTechnicianErr);
    end;

    procedure TryCurrentTechnician(var Tech: Record "DOPSWHS Service Technician"): Boolean
    begin
        Clear(Tech);
        if not Tech.Get(UserId()) then
            exit(false);
        exit(Tech.Active);
    end;

    procedure AssertDispatcher()
    var
        Tech: Record "DOPSWHS Service Technician";
    begin
        CurrentTechnician(Tech);
        if not Tech.Dispatcher then
            Error(DispatcherErr);
    end;

    /// <summary>
    /// There is no assignment step: every active technician sees every service order and may
    /// work on it. Who did the work is recorded when he starts, enters labor or finishes.
    /// </summary>
    procedure AssertCanWork(OrderNo: Code[20])
    var
        Tech: Record "DOPSWHS Service Technician";
        Header: Record "Service Header";
    begin
        Header.Get(Header."Document Type"::Order, OrderNo);
        CurrentTechnician(Tech);
    end;

    procedure AssignTechnician(OrderNo: Code[20]; SILineNo: Integer; ResourceNo: Code[20]; AllocDate: Date; Hours: Decimal): Integer
    begin
        AssertDispatcher();
        exit(AllocateResource(OrderNo, SILineNo, ResourceNo, AllocDate, Hours, true));
    end;

    /// <summary>
    /// Opens a standard service order from the terminal (customer reported a new fault on site).
    /// Any active technician may open one. AssignToMe is only sent by terminals before 1.14.113,
    /// which listed a technician's own allocations; newer terminals list every open order.
    /// </summary>
    procedure CreateServiceOrder(CustomerNo: Code[20]; ServiceItemNo: Code[20]; OrderDescription: Text[100]; PriorityName: Text; AssignToMe: Boolean): Code[20]
    begin
        exit(CreateServiceOrder(CustomerNo, ServiceItemNo, OrderDescription, PriorityName, AssignToMe, ''));
    end;

    /// <summary>SalesOrderNo: the sales order this service is for (optional), kept on the order and in the log.</summary>
    procedure CreateServiceOrder(CustomerNo: Code[20]; ServiceItemNo: Code[20]; OrderDescription: Text[100]; PriorityName: Text; AssignToMe: Boolean; SalesOrderNo: Code[20]): Code[20]
    var
        Tech: Record "DOPSWHS Service Technician";
        Customer: Record Customer;
        ServiceItem: Record "Service Item";
        Header: Record "Service Header";
        ItemLine: Record "Service Item Line";
    begin
        CurrentTechnician(Tech);
        if CustomerNo = '' then
            Error(CustomerRequiredErr);
        Customer.Get(CustomerNo);
        if DelChr(OrderDescription, '<>', ' ') = '' then
            Error(DescriptionRequiredErr);
        if ServiceItemNo <> '' then begin
            ServiceItem.Get(ServiceItemNo);
            if ServiceItem."Customer No." <> CustomerNo then
                Error(ServiceItemCustomerErr, ServiceItemNo, CustomerNo);
        end;

        Header.Init();
        Header."Document Type" := Header."Document Type"::Order;
        Header.Insert(true);
        // API sessions run in UTC: without this the order (and its response time) is stamped three hours early.
        Header."Order Date" := LocalToday();
        Header."Order Time" := LocalTime();
        Header.Validate("Customer No.", CustomerNo);
        // Logged once below as "Service Opened", not also as a changed description.
        ServiceLog.Suppress(true);
        Header.Validate(Description, OrderDescription);
        ServiceLog.Suppress(false);
        Header.Validate(Priority, PriorityValue(PriorityName));
        Header."DOPSWHS Sales Order No." := SalesOrderNo;
        Header.Modify(true);

        ItemLine.Init();
        ItemLine."Document Type" := Header."Document Type";
        ItemLine."Document No." := Header."No.";
        ItemLine."Line No." := 10000;
        if ServiceItemNo <> '' then
            ItemLine.Validate("Service Item No.", ServiceItemNo)
        else
            ItemLine.Validate(Description, CopyStr(OrderDescription, 1, MaxStrLen(ItemLine.Description)));
        ItemLine.Validate(Priority, PriorityValue(PriorityName));
        ItemLine.Insert(true);
        ServiceLog.Add(Header."No.", ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::Created, OrderDescription);

        if AssignToMe then
            AllocateResource(Header."No.", ItemLine."Line No.", Tech."Resource No.", LocalToday(), 1, true);
        exit(Header."No.");
    end;

    local procedure PriorityValue(PriorityName: Text): Enum "Service Priority"
    begin
        case LowerCase(PriorityName) of
            'high':
                exit(Enum::"Service Priority"::High);
            'low':
                exit(Enum::"Service Priority"::Low);
        end;
        exit(Enum::"Service Priority"::Medium);
    end;

    /// <summary>
    /// Records on the standard allocation table that the technician works on the service item, so
    /// Business Central shows who did the job. Nothing is planned: no hours, no "assigned" log entry.
    /// </summary>
    local procedure RecordTechnician(OrderNo: Code[20]; SILineNo: Integer; ResourceNo: Code[20])
    var
        Allocation: Record "Service Order Allocation";
    begin
        if ResourceNo = '' then
            exit;
        FilterAllocations(Allocation, OrderNo, SILineNo, ResourceNo);
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        if not Allocation.IsEmpty() then
            exit;
        AllocateResource(OrderNo, SILineNo, ResourceNo, LocalToday(), 0, false);
    end;

    local procedure AllocateResource(OrderNo: Code[20]; SILineNo: Integer; ResourceNo: Code[20]; AllocDate: Date; Hours: Decimal; Planned: Boolean): Integer
    var
        Header: Record "Service Header";
        ItemLine: Record "Service Item Line";
        Allocation: Record "Service Order Allocation";
        IsNew: Boolean;
    begin
        GetWritableOrder(Header, OrderNo);
        GetItemLine(ItemLine, OrderNo, SILineNo);
        if Planned then
            CheckPositive(Hours);
        if ResourceNo = '' then
            Error(ResourceRequiredErr);
        if AllocDate = 0D then
            Error(AllocationDateErr);
        FilterAllocations(Allocation, OrderNo, ItemLine."Line No.", ResourceNo);
        Allocation.SetRange(Status, Allocation.Status::Active);
        Allocation.LockTable();
        IsNew := not Allocation.FindFirst();
        if IsNew then begin
            Allocation.Init();
            Allocation."Document Type" := Allocation."Document Type"::Order;
            Allocation."Document No." := OrderNo;
            Allocation."Service Item Line No." := ItemLine."Line No.";
        end;
        if IsNew then
            Allocation.Validate("Resource No.", ResourceNo);
        Allocation.TestField("Resource No.");
        Allocation.Validate("Allocation Date", AllocDate);
        if Planned then
            Allocation.Validate("Allocated Hours", Hours);
        Allocation."Service Item No." := ItemLine."Service Item No.";
        Allocation."Service Item Description" := ItemLine.Description;
        Allocation."Service Item Serial No." := ItemLine."Serial No.";
        Allocation.Status := Allocation.Status::Active;
        if IsNew then
            Allocation.Insert(true)
        else
            Allocation.Modify(true);
        // The callers of an unplanned allocation hold the item line themselves: it is not touched here.
        if not Planned then
            exit(Allocation."Entry No.");
        if ItemLine."Repair Status Code" = '' then begin
            ItemLine.Validate("Repair Status Code", FindRepairStatus(0));
            ItemLine.Modify(true);
        end;
        ServiceLog.Add(OrderNo, ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::Assigned,
            StrSubstNo(AssignedLogTxt, ResourceText(ResourceNo), Format(AllocDate, 0, '<Day,2>.<Month,2>.<Year4>'), NumText(Hours)));
        exit(Allocation."Entry No.");
    end;

    procedure StartWork(OrderNo: Code[20]; SILineNo: Integer)
    var
        ItemLine: Record "Service Item Line";
        Allocation: Record "Service Order Allocation";
        Tech: Record "DOPSWHS Service Technician";
        StartDate: Date;
        StartTime: Time;
    begin
        PrepareItem(ItemLine, OrderNo, SILineNo);
        if ItemLine."Starting Date" = 0D then
            ItemLine."Starting Date" := LocalToday();
        if ItemLine."Starting Time" = 0T then
            ItemLine."Starting Time" := LocalTime();
        StartDate := ItemLine."Starting Date";
        StartTime := ItemLine."Starting Time";
        ItemLine.Validate("Repair Status Code", FindRepairStatus(1));
        // Standard validation resets these to WorkDate/Time on every start.
        ItemLine."Starting Date" := StartDate;
        ItemLine."Starting Time" := StartTime;
        ItemLine.Modify(true);
        CurrentTechnician(Tech);
        RecordTechnician(OrderNo, ItemLine."Line No.", Tech."Resource No.");
        FilterAllocations(Allocation, OrderNo, ItemLine."Line No.", Tech."Resource No.");
        Allocation.SetRange(Status, Allocation.Status::Active);
        if Allocation.FindSet(true) then
            repeat
                Allocation."Starting Time" := LocalTime();
                Allocation."Service Started" := true;
                Allocation.Modify(true);
            until Allocation.Next() = 0;
        ServiceLog.Add(OrderNo, ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::Started, '');
    end;

    procedure SetRepairStatus(OrderNo: Code[20]; SILineNo: Integer; RepairStatusCode: Code[10])
    var
        ItemLine: Record "Service Item Line";
        Repair: Record "Repair Status";
    begin
        PrepareItem(ItemLine, OrderNo, SILineNo);
        // Terminal "Beklet" only: start/finish have their own actions with codes, times and allocations.
        if not Repair.Get(RepairStatusCode) then
            Error(HoldStatusErr, RepairStatusCode);
        if not (Repair."Waiting for Customer" or Repair."Spare Part Ordered") then
            Error(HoldStatusErr, RepairStatusCode);
        ItemLine.Validate("Repair Status Code", RepairStatusCode);
        ItemLine.Modify(true);
        ServiceLog.Add(OrderNo, ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::"On Hold", Repair.Description);
    end;

    procedure FinishWork(OrderNo: Code[20]; SILineNo: Integer; FaultArea: Code[10]; Symptom: Code[10]; Fault: Code[10]; Resolution: Code[10]; ResolutionNote: Text)
    var
        ItemLine: Record "Service Item Line";
        Allocation: Record "Service Order Allocation";
        Tech: Record "DOPSWHS Service Technician";
    begin
        PrepareItem(ItemLine, OrderNo, SILineNo);
        if FaultArea <> '' then
            ItemLine.Validate("Fault Area Code", FaultArea);
        if Symptom <> '' then
            ItemLine.Validate("Symptom Code", Symptom);
        Fault := ResolveFaultCode(ItemLine, Fault);
        if Fault <> '' then
            ItemLine.Validate("Fault Code", Fault);
        if Resolution <> '' then
            ItemLine.Validate("Resolution Code", Resolution);
        ServiceLog.Add(OrderNo, ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::Finished, FinishText(ItemLine));
        // Add the note before the repair status can finish the header.
        if ResolutionNote <> '' then
            AddComment(OrderNo, ItemLine."Line No.", 'Resolution', ResolutionNote);
        ItemLine."Finishing Date" := LocalToday();
        ItemLine."Finishing Time" := LocalTime();
        CurrentTechnician(Tech);
        RecordTechnician(OrderNo, ItemLine."Line No.", Tech."Resource No.");
        // "İşi Bitir" finishes the service item for everyone who worked on it, as the standard
        // Finished repair status does; nobody else has to finish it again.
        FilterAllocations(Allocation, OrderNo, ItemLine."Line No.", '');
        Allocation.SetRange(Status, Allocation.Status::Active);
        if Allocation.FindSet(true) then
            repeat
                Allocation.Status := Allocation.Status::Finished;
                Allocation."Finishing Time" := LocalTime();
                Allocation.Modify(true);
            until Allocation.Next() = 0;
        ItemLine.Validate("Repair Status Code", FindRepairStatus(2));
        // Standard repair validation uses WorkDate; terminal timestamps use today.
        ItemLine.Validate("Finishing Date", LocalToday());
        ItemLine.Validate("Finishing Time", LocalTime());
        ItemLine.Modify(true);
    end;

    procedure AddLabor(OrderNo: Code[20]; SILineNo: Integer; Hours: Decimal; WorkTypeCode: Code[10]; Description: Text): Integer
    var
        Line: Record "Service Line";
        ItemLine: Record "Service Item Line";
        Tech: Record "DOPSWHS Service Technician";
        Setup: Record "DOPSWHS Service Setup";
    begin
        PrepareItem(ItemLine, OrderNo, SILineNo);
        CheckPositive(Hours);
        CurrentTechnician(Tech);
        RecordTechnician(OrderNo, ItemLine."Line No.", Tech."Resource No.");
        Setup.GetSetup();
        NewLine(Line, OrderNo);
        Line.Validate(Type, Line.Type::Resource);
        Line.Validate("No.", Tech."Resource No.");
        Line.Validate("Service Item Line No.", ItemLine."Line No.");
        if WorkTypeCode = '' then
            WorkTypeCode := Setup."Default Work Type Code";
        if WorkTypeCode <> '' then
            Line.Validate("Work Type Code", WorkTypeCode);
        Line.Validate(Quantity, Hours);
        if Description <> '' then
            Line.Validate(Description, CopyStr(Description, 1, MaxStrLen(Line.Description)));
        Line.Modify(true);
        ServiceLog.Add(OrderNo, ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::Labor,
            JoinText(StrSubstNo(HoursLogTxt, NumText(Hours)), JoinText(WorkTypeCode, Description)));
        exit(Line."Line No.");
    end;

    procedure AddPart(OrderNo: Code[20]; SILineNo: Integer; ItemNo: Code[20]; Qty: Decimal; LocationCode: Code[10]): Integer
    var
        Line: Record "Service Line";
        ItemLine: Record "Service Item Line";
        Header: Record "Service Header";
        Tech: Record "DOPSWHS Service Technician";
        Setup: Record "DOPSWHS Service Setup";
    begin
        PrepareItem(ItemLine, OrderNo, SILineNo);
        CheckPositive(Qty);
        CurrentTechnician(Tech);
        Setup.GetSetup();
        Header.Get(Header."Document Type"::Order, OrderNo);
        if LocationCode = '' then
            LocationCode := Tech."Van Location Code";
        if LocationCode = '' then
            LocationCode := Setup."Default Location Code";
        if LocationCode = '' then
            LocationCode := Header."Location Code";
        NewLine(Line, OrderNo);
        Line.Validate(Type, Line.Type::Item);
        Line.Validate("No.", ItemNo);
        Line.Validate("Service Item Line No.", ItemLine."Line No.");
        Line.Validate("Location Code", LocationCode);
        Line.Validate(Quantity, Qty);
        Line.Modify(true);
        ServiceLog.Add(OrderNo, ItemLine."Line No.", Enum::"DOPSWHS Service Log Type"::Part,
            StrSubstNo(PartLogTxt, Line."No.", Line.Description, NumText(Line.Quantity), Line."Unit of Measure Code"));
        exit(Line."Line No.");
    end;

    procedure DeleteLine(OrderNo: Code[20]; LineNo: Integer)
    var
        Line: Record "Service Line";
        Header: Record "Service Header";
    begin
        GetWritableOrder(Header, OrderNo);
        Line.Get(Line."Document Type"::Order, OrderNo, LineNo);
        AssertCanWork(OrderNo);
        AssertUnpostedLine(Line);
        ServiceLog.Add(OrderNo, Line."Service Item Line No.", Enum::"DOPSWHS Service Log Type"::"Line Deleted",
            StrSubstNo(PartLogTxt, Line."No.", Line.Description, NumText(Line.Quantity), Line."Unit of Measure Code"));
        Line.Delete(true);
    end;

    procedure AddComment(OrderNo: Code[20]; SILineNo: Integer; CommentType: Text; CommentText: Text)
    var
        Header: Record "Service Header";
        ItemLine: Record "Service Item Line";
        Comment: Record "Service Comment Line";
        NextNo: Integer;
    begin
        // Notes stay allowed after FinishWork: the order is finished but not posted yet.
        Header.Get(Header."Document Type"::Order, OrderNo);
        AssertCanWork(OrderNo);
        if SILineNo <> 0 then begin
            GetItemLine(ItemLine, OrderNo, SILineNo);
        end;
        Comment."Table Name" := Comment."Table Name"::"Service Header";
        Comment."Table Subtype" := "Service Comment Table Subtype".FromInteger(Header."Document Type".AsInteger());
        Comment."No." := OrderNo;
        Comment."Table Line No." := SILineNo;
        case LowerCase(CommentType) of
            'general': Comment.Type := Comment.Type::General;
            'fault': Comment.Type := Comment.Type::Fault;
            'resolution': Comment.Type := Comment.Type::Resolution;
            'internal': Comment.Type := Comment.Type::Internal;
            else Error(CommentTypeErr, CommentType);
        end;
        Comment.LockTable();
        Comment.SetRange("Table Name", Comment."Table Name");
        Comment.SetRange("Table Subtype", Comment."Table Subtype");
        Comment.SetRange("No.", OrderNo);
        Comment.SetRange("Table Line No.", SILineNo);
        Comment.SetRange(Type, Comment.Type);
        if Comment.FindLast() then
            NextNo := Comment."Line No.";
        // One log entry with the whole text; the 80-character comment lines are not logged again.
        ServiceLog.Add(OrderNo, SILineNo, CommentLogType(Comment), CommentText);
        ServiceLog.Suppress(true);
        while CommentText <> '' do begin
            NextNo += 10000;
            Comment."Line No." := NextNo;
            Comment.Date := LocalToday();
            Comment.Comment := CopyStr(CommentText, 1, MaxStrLen(Comment.Comment));
            Comment.Insert(true);
            CommentText := CopyStr(CommentText, MaxStrLen(Comment.Comment) + 1);
        end;
        ServiceLog.Suppress(false);
    end;

    local procedure CommentLogType(Comment: Record "Service Comment Line"): Enum "DOPSWHS Service Log Type"
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

    procedure AddAttachment(OrderNo: Code[20]; FileName: Text; Base64: Text; Kind: Text): Integer
    var
        Header: Record "Service Header";
        Attachment: Record "Document Attachment";
        TempBlob: Codeunit "Temp Blob";
        Base64Convert: Codeunit "Base64 Convert";
        RecRef: RecordRef;
        ContentIn: InStream;
        ContentOut: OutStream;
    begin
        // Photos and the customer signature are taken after FinishWork, before posting.
        Header.Get(Header."Document Type"::Order, OrderNo);
        AssertCanWork(OrderNo);
        if LowerCase(Kind) = 'signature' then
            FileName := 'IMZA-' + OrderNo + '-' + Format(LocalNow(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>') + '.png'
        else
            if UpperCase(CopyStr(FileName, 1, 5)) = 'IMZA-' then
                // Only the signature action may produce IMZA- files (signature requirement check).
                FileName := 'EK-' + FileName;
        TempBlob.CreateOutStream(ContentOut);
        Base64Convert.FromBase64(Base64, ContentOut);
        if TempBlob.Length() = 0 then
            Error(EmptyAttachmentErr);
        TempBlob.CreateInStream(ContentIn);
        RecRef.GetTable(Header);
        Attachment.SaveAttachmentFromStream(ContentIn, RecRef, FileName);
        if LowerCase(Kind) = 'signature' then
            ServiceLog.Add(OrderNo, 0, Enum::"DOPSWHS Service Log Type"::Attachment, SignatureLogTxt)
        else
            ServiceLog.Add(OrderNo, 0, Enum::"DOPSWHS Service Log Type"::Attachment, StrSubstNo(PhotoLogTxt, FileName));
        exit(Attachment.ID);
    end;

    procedure PostShipment(OrderNo: Code[20]; Consume: Boolean): Code[20]
    var
        Header: Record "Service Header";
        Line: Record "Service Line";
        TempLine: Record "Service Line" temporary;
        Setup: Record "DOPSWHS Service Setup";
        Attachment: Record "Document Attachment";
        ServicePost: Codeunit "Service-Post";
        Ship: Boolean;
        Invoice: Boolean;
    begin
        // Finished orders must remain postable after FinishWork.
        Header.Get(Header."Document Type"::Order, OrderNo);
        AssertCanWork(OrderNo);
        Setup.GetSetup();
        if not Setup."Allow Terminal Posting" then
            Error(PostingErr);
        if Setup."Require Signature" then begin
            Attachment.SetRange("Table ID", Database::"Service Header");
            Attachment.SetRange("Document Type", Attachment."Document Type"::Order);
            Attachment.SetRange("No.", OrderNo);
            Attachment.SetFilter("File Name", 'IMZA-*');
            if Attachment.IsEmpty() then
                Error(SignatureErr);
        end;
        Line.SetRange("Document Type", Line."Document Type"::Order);
        Line.SetRange("Document No.", OrderNo);
        if Line.FindSet(true) then
            repeat
                if Line.Type <> Line.Type::" " then begin
                    Line.Validate("Qty. to Ship", Line."Outstanding Quantity");
                    if Consume then
                        Line.Validate("Qty. to Consume", Line."Outstanding Quantity")
                    else
                        Line.Validate("Qty. to Consume", 0);
                    Line.Modify(true);
                end;
            until Line.Next() = 0;
        Ship := true;
        Invoice := false;
        ServicePost.PostWithLines(Header, TempLine, Ship, Consume, Invoice);
        Header.Get(Header."Document Type"::Order, OrderNo);
        ServiceLog.Add(OrderNo, 0, Enum::"DOPSWHS Service Log Type"::Posted, StrSubstNo(PostedLogTxt, Header."Last Shipping No."));
        exit(Header."Last Shipping No.");
    end;

    procedure ElapsedHours(StartDate: Date; StartTime: Time; Rounding: Decimal): Decimal
    var
        Elapsed: Decimal;
    begin
        if StartDate = 0D then
            exit(0);
        Elapsed := (LocalNow() - CreateDateTime(StartDate, StartTime)) / 3600000;
        if Elapsed < 0 then
            exit(0);
        if Rounding > 0 then
            exit(Round(Elapsed, Rounding, '>'));
        exit(Elapsed);
    end;

    procedure TechnicianNames(OrderNo: Code[20]): Text
    var
        Allocation: Record "Service Order Allocation";
        Res: Record Resource;
        Seen: List of [Code[20]];
        Names: Text;
    begin
        // Finished allocations too: the office must still see who did a finished or posted job.
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", OrderNo);
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        Allocation.SetFilter("Resource No.", '<>%1', '');
        if Allocation.FindSet() then
            repeat
                if not Seen.Contains(Allocation."Resource No.") then begin
                    Seen.Add(Allocation."Resource No.");
                    if Res.Get(Allocation."Resource No.") then begin
                        if Names <> '' then
                            Names += ', ';
                        Names += Res.Name;
                    end;
                end;
            until Allocation.Next() = 0;
        exit(Names);
    end;

    procedure AllocatedHours(OrderNo: Code[20]): Decimal
    var
        Allocation: Record "Service Order Allocation";
    begin
        FilterAllocations(Allocation, OrderNo, 0, '');
        Allocation.SetRange(Status, Allocation.Status::Active);
        Allocation.CalcSums("Allocated Hours");
        exit(Allocation."Allocated Hours");
    end;

    /// <summary>
    /// True while something is still to be posted: a typed line with unshipped quantity, or no
    /// typed line at all (the office has to look at such an order before it can be closed).
    /// </summary>
    procedure HasUnshippedLines(OrderNo: Code[20]): Boolean
    var
        ServiceLine: Record "Service Line";
    begin
        ServiceLine.SetRange("Document Type", ServiceLine."Document Type"::Order);
        ServiceLine.SetRange("Document No.", OrderNo);
        ServiceLine.SetFilter(Type, '<>%1', ServiceLine.Type::" ");
        if ServiceLine.IsEmpty() then
            exit(true);
        ServiceLine.SetFilter("Qty. to Ship", '<>0');
        if not ServiceLine.IsEmpty() then
            exit(true);
        ServiceLine.SetRange("Qty. to Ship");
        ServiceLine.SetLoadFields(Quantity, "Quantity Shipped");
        if ServiceLine.FindSet() then
            repeat
                if ServiceLine.Quantity > ServiceLine."Quantity Shipped" then
                    exit(true);
            until ServiceLine.Next() = 0;
        exit(false);
    end;

    procedure FirstServiceItemLineNo(OrderNo: Code[20]): Integer
    var
        ItemLine: Record "Service Item Line";
    begin
        ItemLine.SetRange("Document Type", ItemLine."Document Type"::Order);
        ItemLine.SetRange("Document No.", OrderNo);
        if ItemLine.FindFirst() then
            exit(ItemLine."Line No.");
        Error(NoItemErr, OrderNo);
    end;

    /// <summary>
    /// The terminal asks only "where" (fault area) and "what" (symptom); the fault code follows from
    /// them. Standard BC keeps a fault code per area + symptom pair, so a code defined for the area
    /// alone (blank symptom, like the default GENEL) is copied to the chosen symptom instead of
    /// failing the lookup ("GENEL, Fault Code listesinde tanımlı değil").
    /// </summary>
    local procedure ResolveFaultCode(ItemLine: Record "Service Item Line"; Fault: Code[10]): Code[10]
    var
        ServiceMgtSetup: Record "Service Mgt. Setup";
        FaultCode: Record "Fault Code";
        Generic: Record "Fault Code";
        FullLevel: Boolean;
    begin
        // Fault codes are keyed by area + symptom only at the full (IRIS) reporting level.
        FullLevel := ServiceMgtSetup.Get() and
            (ServiceMgtSetup."Fault Reporting Level" = ServiceMgtSetup."Fault Reporting Level"::"Fault+Symptom+Area (IRIS)");
        if Fault = '' then begin
            // A code the office already put on the line (and that survived the area/symptom validation) stays.
            if (ItemLine."Fault Code" <> '') or not FullLevel or (ItemLine."Fault Area Code" = '') then
                exit('');
            // Exactly one code defined for this area + symptom (e.g. Rulo + Ses = RULMAN): that is the fault.
            if ItemLine."Symptom Code" <> '' then begin
                FaultCode.SetRange("Fault Area Code", ItemLine."Fault Area Code");
                FaultCode.SetRange("Symptom Code", ItemLine."Symptom Code");
                if FaultCode.Count() = 1 then begin
                    FaultCode.FindFirst();
                    exit(FaultCode.Code);
                end;
                FaultCode.Reset();
            end;
            if not FaultCode.Get(ItemLine."Fault Area Code", ItemLine."Symptom Code", GeneralFaultTok) and
               not FaultCode.Get(ItemLine."Fault Area Code", '', GeneralFaultTok)
            then
                exit('');
            Fault := GeneralFaultTok;
        end;
        // An explicit code (older terminal) at another reporting level goes to the standard validation as it is.
        if not FullLevel then
            exit(Fault);
        if FaultCode.Get(ItemLine."Fault Area Code", ItemLine."Symptom Code", Fault) then
            exit(Fault);
        if (ItemLine."Symptom Code" <> '') and Generic.Get(ItemLine."Fault Area Code", '', Fault) then begin
            FaultCode.Init();
            FaultCode."Fault Area Code" := ItemLine."Fault Area Code";
            FaultCode."Symptom Code" := ItemLine."Symptom Code";
            FaultCode.Code := Fault;
            FaultCode.Description := Generic.Description;
            FaultCode.Insert(true);
            exit(Fault);
        end;
        Error(FaultCodeErr, Fault, ItemLine."Fault Area Code", ItemLine."Symptom Code");
    end;

    local procedure FinishText(ItemLine: Record "Service Item Line"): Text
    var
        FaultArea: Record "Fault Area";
        SymptomCode: Record "Symptom Code";
        ResolutionCode: Record "Resolution Code";
        Result: Text;
    begin
        if FaultArea.Get(ItemLine."Fault Area Code") then
            Result := JoinText(Result, StrSubstNo(FaultAreaLogTxt, DescriptionOrCode(FaultArea.Description, FaultArea.Code)));
        if SymptomCode.Get(ItemLine."Symptom Code") then
            Result := JoinText(Result, StrSubstNo(SymptomLogTxt, DescriptionOrCode(SymptomCode.Description, SymptomCode.Code)));
        if ResolutionCode.Get(ItemLine."Resolution Code") then
            Result := JoinText(Result, StrSubstNo(ResolutionLogTxt, DescriptionOrCode(ResolutionCode.Description, ResolutionCode.Code)));
        exit(Result);
    end;

    local procedure DescriptionOrCode(Description: Text; Code: Text): Text
    begin
        if Description <> '' then
            exit(Description);
        exit(Code);
    end;

    local procedure JoinText(First: Text; Second: Text): Text
    begin
        if First = '' then
            exit(Second);
        if Second = '' then
            exit(First);
        exit(First + ' · ' + Second);
    end;

    /// <summary>Log texts are read in Turkish whatever the session language (API sessions are en-US).</summary>
    local procedure NumText(Value: Decimal): Text
    begin
        exit(ConvertStr(Format(Value, 0, 9), '.', ','));
    end;

    local procedure ResourceText(ResourceNo: Code[20]): Text
    var
        Res: Record Resource;
    begin
        if Res.Get(ResourceNo) and (Res.Name <> '') then
            exit(Res.Name);
        exit(ResourceNo);
    end;

    /// <summary>
    /// BC online runs AL in UTC, while Time fields on service documents are shown
    /// without conversion. Technicians must see the clock time of their own zone.
    /// </summary>
    local procedure LocalNow(): DateTime
    var
        TypeHelper: Codeunit "Type Helper";
    begin
        exit(TypeHelper.GetCurrentDateTimeInUserTimeZone());
    end;

    procedure LocalToday(): Date
    begin
        exit(DT2Date(LocalNow()));
    end;

    local procedure LocalTime(): Time
    begin
        exit(DT2Time(LocalNow()));
    end;

    local procedure GetWritableOrder(var Header: Record "Service Header"; OrderNo: Code[20])
    begin
        Header.Get(Header."Document Type"::Order, OrderNo);
        if Header.Status = Header.Status::Finished then
            Error(FinishedErr, OrderNo);
    end;

    local procedure GetItemLine(var ItemLine: Record "Service Item Line"; OrderNo: Code[20]; SILineNo: Integer)
    begin
        if SILineNo = 0 then
            SILineNo := FirstServiceItemLineNo(OrderNo);
        ItemLine.Get(ItemLine."Document Type"::Order, OrderNo, SILineNo);
    end;

    local procedure PrepareItem(var ItemLine: Record "Service Item Line"; OrderNo: Code[20]; SILineNo: Integer)
    var
        Header: Record "Service Header";
    begin
        GetWritableOrder(Header, OrderNo);
        GetItemLine(ItemLine, OrderNo, SILineNo);
        AssertCanWork(OrderNo);
        // Notes, attachments and posting do not use PrepareItem and stay allowed.
        if IsFinishedRepairStatus(ItemLine."Repair Status Code") then
            Error(ItemFinishedErr, ItemLine.Description);
    end;

    local procedure IsFinishedRepairStatus(RepairCode: Code[10]): Boolean
    var
        Repair: Record "Repair Status";
    begin
        if RepairCode = '' then
            exit(false);
        if not Repair.Get(RepairCode) then
            exit(false);
        exit(Repair.Finished);
    end;

    local procedure AssertUnpostedLine(Line: Record "Service Line")
    begin
        if (Line."Quantity Shipped" <> 0) or (Line."Quantity Consumed" <> 0) or (Line."Quantity Invoiced" <> 0) then
            Error(PostedErr, Line."Line No.");
    end;

    local procedure FilterAllocations(var Allocation: Record "Service Order Allocation"; OrderNo: Code[20]; SILineNo: Integer; ResourceNo: Code[20])
    begin
        Allocation.Reset();
        Allocation.SetHideDialog(true);
        Allocation.SetRange("Document Type", Allocation."Document Type"::Order);
        Allocation.SetRange("Document No.", OrderNo);
        Allocation.SetRange(Posted, false);
        if SILineNo <> 0 then
            Allocation.SetRange("Service Item Line No.", SILineNo);
        if ResourceNo <> '' then
            Allocation.SetRange("Resource No.", ResourceNo);
    end;

    local procedure FindRepairStatus(Kind: Integer): Code[10]
    var
        Repair: Record "Repair Status";
    begin
        case Kind of
            0: Repair.SetRange(Initial, true);
            1: Repair.SetRange("In Process", true);
            2: Repair.SetRange(Finished, true);
        end;
        if not Repair.FindFirst() then
            Error(RepairStatusErr);
        exit(Repair.Code);
    end;

    local procedure CheckPositive(Value: Decimal)
    begin
        if Value <= 0 then
            Error(PositiveErr);
    end;

    local procedure NewLine(var Line: Record "Service Line"; OrderNo: Code[20])
    var
        NextNo: Integer;
    begin
        Line.LockTable();
        Line.SetRange("Document Type", Line."Document Type"::Order);
        Line.SetRange("Document No.", OrderNo);
        if Line.FindLast() then
            NextNo := Line."Line No.";
        Line.Init();
        Line."Document Type" := Line."Document Type"::Order;
        Line."Document No." := OrderNo;
        Line."Line No." := NextNo + 10000;
        Line.Insert(true);
    end;

    var
        ServiceLog: Codeunit "DOPSWHS Service Log";
        GeneralFaultTok: Label 'GENEL', Locked = true;
        FaultCodeErr: Label '%1 arıza kodu, %2 arıza alanı ve %3 belirtisi için tanımlı değil. BC''de Arıza Kodları sayfasından tanımlayın veya başka bir seçim yapın.', Comment = '%1 = Arıza kodu, %2 = Arıza alanı kodu, %3 = Belirti kodu';
        AssignedLogTxt: Label '%1 · %2 · %3 saat', Comment = '%1 = Teknisyen adı, %2 = Tarih, %3 = Planlanan saat';
        HoursLogTxt: Label '%1 saat', Comment = '%1 = İşçilik saati';
        PartLogTxt: Label '%1 %2 · %3 %4', Comment = '%1 = No, %2 = Açıklama, %3 = Miktar, %4 = Birim';
        FaultAreaLogTxt: Label 'Arıza yeri: %1', Comment = '%1 = Arıza alanı';
        SymptomLogTxt: Label 'Sorun: %1', Comment = '%1 = Belirti';
        ResolutionLogTxt: Label 'Yapılan: %1', Comment = '%1 = Çözüm';
        SignatureLogTxt: Label 'Müşteri imzası alındı';
        PhotoLogTxt: Label 'Fotoğraf: %1', Comment = '%1 = Dosya adı';
        PostedLogTxt: Label 'Servis sevkiyatı %1', Comment = '%1 = Sevkiyat no';
        ResourceRequiredErr: Label 'Teknisyen kaynağı boş olamaz.';
        AllocationDateErr: Label 'Tahsis tarihi boş olamaz.';
        NoTechnicianErr: Label 'Bu kullanıcı servis teknisyeni olarak tanımlı değil (Servis Teknisyenleri sayfası).';
        DispatcherErr: Label 'Bu işlem için servis yöneticisi yetkisi gereklidir.';
        FinishedErr: Label '%1 servis siparişi tamamlandı; değişiklik yapılamaz.', Comment = '%1 = Servis siparişi numarası';
        PostedErr: Label '%1 satırı kaydedilmiş; değişiklik yapılamaz.', Comment = '%1 = Servis satırı numarası';
        PositiveErr: Label 'Miktar veya saat sıfırdan büyük olmalıdır.';
        NoItemErr: Label '%1 siparişinde servis kalemi satırı bulunamadı.', Comment = '%1 = Servis siparişi numarası';
        RepairStatusErr: Label 'Gerekli onarım durumu tanımlı değil. Varsayılan servis kodlarını oluşturun.';
        CommentTypeErr: Label 'Geçersiz yorum türü: %1.', Comment = '%1 = Yorum türü';
        PostingErr: Label 'Terminalden servis kaydına izin verilmiyor.';
        SignatureErr: Label 'Servis kaydından önce müşteri imzası eklenmelidir.';
        HoldStatusErr: Label '%1 bir bekletme durumu değil. Müşteri bekleniyor veya parça sipariş edildi durumlarından birini seçin.', Comment = '%1 = Onarım durumu kodu';
        ItemFinishedErr: Label '%1 için iş bitirildi; yeni işlem yapılamaz. Not, fotoğraf ve imza eklenebilir.', Comment = '%1 = Servis kalemi açıklaması';
        EmptyAttachmentErr: Label 'Ek dosyası boş.';
        CustomerRequiredErr: Label 'Müşteri seçin.';
        DescriptionRequiredErr: Label 'Arıza açıklaması girin.';
        ServiceItemCustomerErr: Label '%1 servis maddesi %2 müşterisine ait değil.', Comment = '%1 = Servis maddesi no, %2 = Müşteri no';
}
