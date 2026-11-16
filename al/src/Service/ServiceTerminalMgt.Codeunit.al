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
        tabledata Resource = R,
        tabledata "Service Item" = R,
        tabledata "Work Type" = R,
        tabledata Location = R;

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

    procedure AssertCanWork(OrderNo: Code[20]; SILineNo: Integer)
    var
        Tech: Record "DOPSWHS Service Technician";
        Allocation: Record "Service Order Allocation";
        Header: Record "Service Header";
    begin
        Header.Get(Header."Document Type"::Order, OrderNo);
        CurrentTechnician(Tech);
        if Tech.Dispatcher then
            exit;
        FilterAllocations(Allocation, OrderNo, SILineNo, Tech."Resource No.");
        Allocation.SetFilter(Status, '%1|%2', Allocation.Status::Active, Allocation.Status::Finished);
        if Allocation.IsEmpty() then
            Error(NotAssignedErr, OrderNo);
    end;

    procedure AssignTechnician(OrderNo: Code[20]; SILineNo: Integer; ResourceNo: Code[20]; AllocDate: Date; Hours: Decimal): Integer
    var
        Header: Record "Service Header";
        ItemLine: Record "Service Item Line";
        Allocation: Record "Service Order Allocation";
        IsNew: Boolean;
    begin
        AssertDispatcher();
        GetWritableOrder(Header, OrderNo);
        GetItemLine(ItemLine, OrderNo, SILineNo);
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
        Allocation.Validate("Allocated Hours", Hours);
        Allocation."Service Item No." := ItemLine."Service Item No.";
        Allocation."Service Item Description" := ItemLine.Description;
        Allocation."Service Item Serial No." := ItemLine."Serial No.";
        Allocation.Status := Allocation.Status::Active;
        if IsNew then
            Allocation.Insert(true)
        else
            Allocation.Modify(true);
        if ItemLine."Repair Status Code" = '' then begin
            ItemLine.Validate("Repair Status Code", FindRepairStatus(0));
            ItemLine.Modify(true);
        end;
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
            ItemLine."Starting Date" := Today();
        if ItemLine."Starting Time" = 0T then
            ItemLine."Starting Time" := Time();
        StartDate := ItemLine."Starting Date";
        StartTime := ItemLine."Starting Time";
        ItemLine.Validate("Repair Status Code", FindRepairStatus(1));
        // Standard validation resets these to WorkDate/Time on every start.
        ItemLine."Starting Date" := StartDate;
        ItemLine."Starting Time" := StartTime;
        ItemLine.Modify(true);
        CurrentTechnician(Tech);
        FilterAllocations(Allocation, OrderNo, ItemLine."Line No.", Tech."Resource No.");
        Allocation.SetRange(Status, Allocation.Status::Active);
        if Allocation.FindSet(true) then
            repeat
                Allocation."Starting Time" := Time();
                Allocation."Service Started" := true;
                Allocation.Modify(true);
            until Allocation.Next() = 0;
    end;

    procedure SetRepairStatus(OrderNo: Code[20]; SILineNo: Integer; RepairStatusCode: Code[10])
    var
        ItemLine: Record "Service Item Line";
    begin
        PrepareItem(ItemLine, OrderNo, SILineNo);
        ItemLine.Validate("Repair Status Code", RepairStatusCode);
        ItemLine.Modify(true);
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
        if Fault <> '' then
            ItemLine.Validate("Fault Code", Fault);
        if Resolution <> '' then
            ItemLine.Validate("Resolution Code", Resolution);
        // Add the note before the repair status can finish the header.
        if ResolutionNote <> '' then
            AddComment(OrderNo, ItemLine."Line No.", 'Resolution', ResolutionNote);
        ItemLine."Finishing Date" := Today();
        ItemLine."Finishing Time" := Time();
        CurrentTechnician(Tech);
        FilterAllocations(Allocation, OrderNo, ItemLine."Line No.", Tech."Resource No.");
        Allocation.SetRange(Status, Allocation.Status::Active);
        if Allocation.FindSet(true) then
            repeat
                Allocation.Status := Allocation.Status::Finished;
                Allocation."Finishing Time" := Time();
                Allocation.Modify(true);
            until Allocation.Next() = 0;
        ItemLine.Validate("Repair Status Code", FindRepairStatus(2));
        // Standard repair validation uses WorkDate; terminal timestamps use today.
        ItemLine.Validate("Finishing Date", Today());
        ItemLine.Validate("Finishing Time", Time());
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
        exit(Line."Line No.");
    end;

    procedure DeleteLine(OrderNo: Code[20]; LineNo: Integer)
    var
        Line: Record "Service Line";
        Header: Record "Service Header";
    begin
        GetWritableOrder(Header, OrderNo);
        Line.Get(Line."Document Type"::Order, OrderNo, LineNo);
        AssertCanWork(OrderNo, Line."Service Item Line No.");
        AssertUnpostedLine(Line);
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
        AssertCanWork(OrderNo, SILineNo);
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
        while CommentText <> '' do begin
            NextNo += 10000;
            Comment."Line No." := NextNo;
            Comment.Date := Today();
            Comment.Comment := CopyStr(CommentText, 1, MaxStrLen(Comment.Comment));
            Comment.Insert(true);
            CommentText := CopyStr(CommentText, MaxStrLen(Comment.Comment) + 1);
        end;
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
        AssertCanWork(OrderNo, 0);
        if LowerCase(Kind) = 'signature' then
            FileName := 'IMZA-' + OrderNo + '-' + Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>') + '.png';
        TempBlob.CreateOutStream(ContentOut);
        Base64Convert.FromBase64(Base64, ContentOut);
        TempBlob.CreateInStream(ContentIn);
        RecRef.GetTable(Header);
        Attachment.SaveAttachmentFromStream(ContentIn, RecRef, FileName);
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
        AssertCanWork(OrderNo, 0);
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
                AssertCanWork(OrderNo, Line."Service Item Line No.");
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
        exit(Header."Last Shipping No.");
    end;

    procedure ElapsedHours(StartDate: Date; StartTime: Time; Rounding: Decimal): Decimal
    var
        Elapsed: Decimal;
    begin
        if StartDate = 0D then
            exit(0);
        Elapsed := (CurrentDateTime() - CreateDateTime(StartDate, StartTime)) / 3600000;
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
        FilterAllocations(Allocation, OrderNo, 0, '');
        Allocation.SetRange(Status, Allocation.Status::Active);
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
        AssertCanWork(OrderNo, ItemLine."Line No.");
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
        ResourceRequiredErr: Label 'Teknisyen kaynağı boş olamaz.';
        AllocationDateErr: Label 'Tahsis tarihi boş olamaz.';
        NoTechnicianErr: Label 'Bu kullanıcı servis teknisyeni olarak tanımlı değil (Servis Teknisyenleri sayfası).';
        DispatcherErr: Label 'Bu işlem için servis yöneticisi yetkisi gereklidir.';
        NotAssignedErr: Label '%1 servis siparişinde bu işlem için kaynak tahsisiniz yok.', Comment = '%1 = Servis siparişi numarası';
        FinishedErr: Label '%1 servis siparişi tamamlandı; değişiklik yapılamaz.', Comment = '%1 = Servis siparişi numarası';
        PostedErr: Label '%1 satırı kaydedilmiş; değişiklik yapılamaz.', Comment = '%1 = Servis satırı numarası';
        PositiveErr: Label 'Miktar veya saat sıfırdan büyük olmalıdır.';
        NoItemErr: Label '%1 siparişinde servis kalemi satırı bulunamadı.', Comment = '%1 = Servis siparişi numarası';
        RepairStatusErr: Label 'Gerekli onarım durumu tanımlı değil. Varsayılan servis kodlarını oluşturun.';
        CommentTypeErr: Label 'Geçersiz yorum türü: %1.', Comment = '%1 = Yorum türü';
        PostingErr: Label 'Terminalden servis kaydına izin verilmiyor.';
        SignatureErr: Label 'Servis kaydından önce müşteri imzası eklenmelidir.';
}
